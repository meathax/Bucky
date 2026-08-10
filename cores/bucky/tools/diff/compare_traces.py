#!/usr/bin/env python3
"""Compare two normalized MiSTer/MAME JSONL event traces."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from collections import defaultdict
from typing import Any, Iterable


DEFAULT_FIELDS = "cpu,event,rw,address,data,lanes,device"
REQUIRED_EVENT_FIELDS = {"cpu", "event", "rw", "address", "data", "lanes", "device"}


def load_events(path: pathlib.Path) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as source:
        for line_number, line in enumerate(source, 1):
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f"{path}:{line_number}: {error}") from error
            if not isinstance(event, dict):
                raise ValueError(f"{path}:{line_number}: event is not an object")
            missing = REQUIRED_EVENT_FIELDS - set(event)
            if missing:
                raise ValueError(f"{path}:{line_number}: missing schema fields {sorted(missing)}")
            events.append(event)
    return events


def parse_masks(values: Iterable[str]) -> dict[str, int]:
    masks: dict[str, int] = {}
    for value in values:
        if "=" not in value:
            raise ValueError(f"invalid mask {value!r}; expected FIELD=INTEGER")
        field, raw_mask = value.split("=", 1)
        masks[field] = int(raw_mask, 0)
    return masks


def normalize_integer(value: Any) -> Any:
    if isinstance(value, str):
        try:
            return int(value, 0)
        except ValueError:
            return value
    return value


def projected(event: dict[str, Any], fields: list[str],
              masks: dict[str, int], mask_inactive_data: bool) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for field in fields:
        value = normalize_integer(event.get(field))
        if field == "rw" and isinstance(value, str):
            value = value.lower()
        if field == "event" and isinstance(value, str):
            value = value.lower().replace("write", "wr").replace("read", "rd")
        if field == "data" and mask_inactive_data:
            lanes = normalize_integer(event.get("lanes"))
            if isinstance(value, int) and isinstance(lanes, int):
                lane_mask = (0xff00 if lanes & 2 else 0) | (0x00ff if lanes & 1 else 0)
                value &= lane_mask
        if field in masks and isinstance(value, int):
            value &= masks[field]
        result[field] = value
    return result


def compare_stream(label: str, left: list[dict[str, Any]],
                   right: list[dict[str, Any]], fields: list[str],
                   masks: dict[str, int], context: int,
                   allow_candidate_tail: bool, mask_inactive_data: bool,
                   failure: dict[str, Any] | None) -> bool:
    common = min(len(left), len(right))
    mismatch = next(
        (index for index in range(common)
         if projected(left[index], fields, masks, mask_inactive_data) !=
         projected(right[index], fields, masks, mask_inactive_data)),
        None,
    )
    if mismatch is None and len(left) == len(right):
        print(f"MATCH {label}: {len(left)} events")
        return True

    # A bounded RTL run often produces a strict prefix of a longer reference
    # trace, while a long run may intentionally continue past the reference
    # checkpoint.  Make the latter explicit rather than silently accepting any
    # length mismatch.  The reference must still be completely present and
    # every projected event must match.
    if (mismatch is None and allow_candidate_tail and
            len(right) >= len(left)):
        print(f"MATCH {label}: reference prefix {len(left)} events; "
              f"candidate continues for {len(right) - len(left)} events")
        return True

    if mismatch is None:
        mismatch = common
        reason = f"length differs: reference={len(left)} candidate={len(right)}"
    else:
        reason = "event fields differ"

    print(f"MISMATCH {label} at event {mismatch}: {reason}")
    if failure is not None:
        failure.update({"stream": label, "index": mismatch, "reason": reason,
                        "reference_length": len(left), "candidate_length": len(right)})
    start = max(0, mismatch - context)
    stop = min(max(len(left), len(right)), mismatch + context + 1)
    for index in range(start, stop):
        marker = ">" if index == mismatch else " "
        lhs = projected(left[index], fields, masks, mask_inactive_data) if index < len(left) else None
        rhs = projected(right[index], fields, masks, mask_inactive_data) if index < len(right) else None
        if failure is not None:
            failure.setdefault("context", []).append({"index": index, "reference": lhs, "candidate": rhs})
        print(f"{marker} {index:8d} REF {json.dumps(lhs, sort_keys=True)}")
        print(f"{marker} {index:8d} HDL {json.dumps(rhs, sort_keys=True)}")
    return False


def split_by_cpu(events: list[dict[str, Any]]) -> dict[Any, list[dict[str, Any]]]:
    result: dict[Any, list[dict[str, Any]]] = defaultdict(list)
    for event in events:
        if "cpu" not in event:
            raise ValueError("cannot use --per-cpu when an event lacks 'cpu'")
        result[event["cpu"]].append(event)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=pathlib.Path)
    parser.add_argument("candidate", type=pathlib.Path)
    parser.add_argument("--fields", default=DEFAULT_FIELDS,
                        help="comma-separated fields compared in order")
    parser.add_argument("--mask", action="append", default=[],
                        metavar="FIELD=INTEGER",
                        help="bit-mask an integer field before comparison")
    parser.add_argument("--context", type=int, default=3)
    parser.add_argument("--per-cpu", action="store_true",
                        help="compare each CPU stream independently")
    parser.add_argument("--allow-candidate-tail", action="store_true",
                        help="accept a candidate trace that continues after "
                             "the complete reference trace")
    parser.add_argument("--mask-inactive-data", action="store_true",
                        help="ignore bytes whose lane-enable bit is inactive")
    parser.add_argument("--failure-report", type=pathlib.Path,
                        help="write the first mismatch and bounded context as JSON")
    args = parser.parse_args()

    if args.context < 0:
        parser.error("--context cannot be negative")
    fields = [field.strip() for field in args.fields.split(",") if field.strip()]
    if not fields:
        parser.error("--fields must contain at least one field")

    try:
        masks = parse_masks(args.mask)
        reference = load_events(args.reference)
        candidate = load_events(args.candidate)
        failure: dict[str, Any] = {}
        if args.per_cpu:
            ref_cpus = split_by_cpu(reference)
            cand_cpus = split_by_cpu(candidate)
            cpus = sorted(set(ref_cpus) | set(cand_cpus), key=str)
            matched = all(
                compare_stream(f"cpu={cpu}", ref_cpus.get(cpu, []),
                               cand_cpus.get(cpu, []), fields, masks,
                               args.context, args.allow_candidate_tail,
                               args.mask_inactive_data, failure)
                for cpu in cpus
            )
        else:
            matched = compare_stream("global", reference, candidate, fields,
                                     masks, args.context,
                                     args.allow_candidate_tail,
                                     args.mask_inactive_data, failure)
        if args.failure_report:
            if matched:
                args.failure_report.unlink(missing_ok=True)
            else:
                args.failure_report.parent.mkdir(parents=True, exist_ok=True)
                args.failure_report.write_text(json.dumps(failure, indent=2, sort_keys=True) + "\n",
                                               encoding="utf-8")
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    return 0 if matched else 1


if __name__ == "__main__":
    raise SystemExit(main())
