#!/usr/bin/env python3
"""Convert a verilator-record port journal into the Bucky replay table."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def jsonl(path: Path) -> list[dict]:
    records: list[dict] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip():
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as error:
                raise ValueError(f"{path}:{number}: {error}") from error
    return records


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--journal", type=Path, required=True)
    parser.add_argument("--fields", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    fields = jsonl(args.fields)
    events = jsonl(args.journal)
    replayable_masks: dict[str, int] = {}
    defaults: dict[str, int] = {}
    for field in fields:
        port = field["port"]
        mask = int(field["mask"])
        defaults[port] = defaults.get(port, 0) | (int(field["defvalue"]) & mask)
        if field.get("replayable"):
            replayable_masks[port] = replayable_masks.get(port, 0) | mask

    p1p3: list[tuple[int, int]] = []
    previous_frame = -1
    for event in events:
        if event.get("schema") != "mame-port-event-v2":
            raise ValueError(f"unsupported event schema: {event.get('schema')!r}")
        if event.get("phase") != "machine_frame_complete":
            raise ValueError(f"unsupported event phase: {event.get('phase')!r}")
        frame = int(event["frame"])
        if frame < previous_frame:
            raise ValueError("journal frames move backwards")
        previous_frame = frame
        port = event["port"]
        mask = int(event["mask"])
        value = int(event["value"])
        allowed = replayable_masks.get(port, 0)
        if mask & ~allowed:
            raise ValueError(f"{port} journal mask 0x{mask:x} includes non-replayable fields")
        if port == ":P1_P3":
            if mask != 0xFFFF or value < 0 or value > 0xFFFF:
                raise ValueError("Bucky requires full 16-bit P1_P3 journal values")
            p1p3.append((frame, value))
        elif (value & mask) != (defaults.get(port, 0) & mask):
            raise ValueError(f"unsupported non-default replay event on {port} at frame {frame}")

    if not p1p3:
        raise ValueError("journal contains no P1_P3 events")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("".join(f"{frame:08x}{value:04x}\n" for frame, value in p1p3),
                           encoding="ascii", newline="\n")
    manifest = {
        "schema": "bucky-verilator-record-replay-v1",
        "source_phase": "machine_frame_complete",
        "apply_phase": "before_next_frame",
        "journal": str(args.journal.resolve()),
        "journal_sha256": sha256(args.journal),
        "io_fields": str(args.fields.resolve()),
        "io_fields_sha256": sha256(args.fields),
        "p1p3_table": str(args.output.resolve()),
        "p1p3_table_sha256": sha256(args.output),
        "p1p3_event_count": len(p1p3),
        "first_frame": p1p3[0][0],
        "last_frame": p1p3[-1][0],
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                             encoding="utf-8", newline="\n")
    print(json.dumps(manifest, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
