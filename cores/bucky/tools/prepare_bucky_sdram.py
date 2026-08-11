#!/usr/bin/env python3
"""Create Bucky's derived JTFRAME SDRAM wrapper without editing upstream output."""

from __future__ import annotations

import argparse
from pathlib import Path


MAIN_SLOT = """    // main
    .SLOT1_AW(21),
    .SLOT1_DW(16)
"""

MAIN_SLOT_DERIVED = """    // main
    // Cache only explicitly requested words.  The two-line burst cache can
    // overwrite a live tag with an adjacent 64-bit return word.
    .CACHE1_SIZE(8),
    .SLOT1_AW(21),
    .SLOT1_DW(16)
"""

# The parent Verilator bench initializes its behavioral RAM array to zero.  The
# generated JTFRAME wrapper's default RAM erase would otherwise replay 131072
# SDRAM writes before releasing the CPU reset, dominating every audio run.
# This derived wrapper is simulation-only; Quartus still uses the unmodified
# core manifest and keeps the hardware erase contract.
def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--skip-ram-erase",
        action="store_true",
        help="exploratory simulation only: RAM is already initialized to zero",
    )
    args = parser.parse_args()

    source = args.source.read_text(encoding="utf-8")
    count = source.count(MAIN_SLOT)
    # A prior JTFRAME generation may already contain the derived cache size.
    # Preserve that valid generated wrapper instead of failing a rebuild merely
    # because the workbench artifact is no longer the pristine template.
    if count == 0 and ".CACHE1_SIZE(8)" in source:
        derived = source
    elif count != 1:
        raise SystemExit(
            f"expected exactly one Bucky main SDRAM slot in {args.source}, found {count}"
        )
    else:
        derived = source.replace(MAIN_SLOT, MAIN_SLOT_DERIVED)
    if args.skip_ram_erase and "SLOT0_ERASE(0)" not in derived:
        ram_slot = "    .SLOT0_AW(17),\n    .SLOT0_DW(16),"
        if derived.count(ram_slot) != 1:
            raise SystemExit("expected exactly one Bucky RAM slot in generated SDRAM wrapper")
        derived = derived.replace(
            ram_slot,
            "    .SLOT0_ERASE(0),\n" + ram_slot,
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(derived, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
