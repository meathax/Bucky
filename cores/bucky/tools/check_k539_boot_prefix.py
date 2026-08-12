#!/usr/bin/env python3
"""Strict domain-local K054539 boot-write prefix comparator.

This comparator intentionally stops at the first insertion, deletion or value
mismatch.  It never resynchronizes the streams, so the matching-prefix extent
is suitable for the active-divergence closure gate.
"""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path


MAME_EVENT = re.compile(r"\baddr=([0-9a-fA-F]+)\s+data=([0-9a-fA-F]+)\b")
RTL_EVENT = re.compile(r"^\s*([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s*$")


def digest(path: Path) -> str:
	return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path: Path, pattern: re.Pattern[str]) -> list[tuple[int, int]]:
	events: list[tuple[int, int]] = []
	for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
		match = pattern.search(line)
		if match is None:
			continue
		try:
			events.append((int(match.group(1), 16), int(match.group(2), 16)))
		except ValueError as exc:
			raise SystemExit(f"malformed event at {path}:{line_number}: {line}") from exc
	return events


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--mame", required=True, type=Path)
	parser.add_argument("--rtl", required=True, type=Path)
	parser.add_argument("--events", required=True, type=int)
	args = parser.parse_args()

	if args.events < 1:
		raise SystemExit("--events must be positive")
	for path in (args.mame, args.rtl):
		if not path.is_file():
			raise SystemExit(f"missing trace: {path}")

	mame = load(args.mame, MAME_EVENT)
	rtl = load(args.rtl, RTL_EVENT)
	if len(mame) < args.events or len(rtl) < args.events:
		print(
			f"FAIL insufficient events requested={args.events} "
			f"mame={len(mame)} rtl={len(rtl)}"
		)
		return 1

	for ordinal in range(args.events):
		if mame[ordinal] != rtl[ordinal]:
			last = ordinal - 1
			print(
				f"FAIL first_mismatch={ordinal} last_match={last} "
				f"mame={mame[ordinal][0]:03x}:{mame[ordinal][1]:02x} "
				f"rtl={rtl[ordinal][0]:03x}:{rtl[ordinal][1]:02x} "
				f"mame_sha256={digest(args.mame)} rtl_sha256={digest(args.rtl)}"
			)
			return 1

	print(
		f"PASS matched_prefix={args.events} last_match={args.events - 1} "
		f"mame_sha256={digest(args.mame)} rtl_sha256={digest(args.rtl)}"
	)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
