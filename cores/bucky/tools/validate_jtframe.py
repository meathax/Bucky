#!/usr/bin/env python3
"""Check the generated JTFRAME parent wrapper without running Quartus.

JTFRAME deliberately generates ``mister/`` and ``files.qip`` outside this
source-only repository.  This checker is therefore pointed at a staged
``jtcores/cores/bucky`` directory after ``jtframe mem/mmr/files`` has run.
It validates only the parent integration contract; clone MRAs do not affect
this gate.
"""

from __future__ import annotations

from pathlib import Path
import sys


REQUIRED_QIP = (
    "bucky_main.v",
    "bucky_video.v",
    "bucky_colmix.v",
    "bucky_k054000.v",
    "bucky_k054338.v",
    "k054539.v",
    "k053246.sv",
    "k053246_scan.sv",
    "jtbucky_game.v",
)
FORBIDDEN_QIP = ("jtsimson_obj.v", "jtmoomesa_game.v", "jtbuckyaa_game.v")


def require(needle: str, haystack: str, label: str) -> None:
    if needle not in haystack:
        raise ValueError(f"{label}: missing {needle!r}")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <jtcores/cores/bucky>", file=sys.stderr)
        return 2

    core = Path(sys.argv[1]).resolve()
    wrapper = core / "mister" / "jtbucky_game_sdram.v"
    ports = core / "mister" / "mem_ports.inc"
    qip = core / "files.qip"
    for path in (wrapper, ports, qip):
        if not path.is_file():
            raise ValueError(f"generated JTFRAME artifact is missing: {path}")

    wrapper_text = wrapper.read_text(encoding="utf-8", errors="replace")
    ports_text = ports.read_text(encoding="utf-8", errors="replace")
    qip_text = qip.read_text(encoding="utf-8", errors="replace")

    require("module jtbucky_game_sdram", wrapper_text, "generated wrapper")
    require("jtbucky_game u_game", wrapper_text, "generated wrapper")
    require("[21:0] pcm_addr", wrapper_text, "generated wrapper")
    require("[22:2] lyro_addr", wrapper_text, "generated wrapper")
    require("[21:1] main_addr", wrapper_text, "generated wrapper")
    require("[6:0] nvram_addr", wrapper_text, "generated wrapper")
    require("pcm_addr", ports_text, "generated memory ports")
    require("lyro_addr", ports_text, "generated memory ports")

    for name in REQUIRED_QIP:
        require(name, qip_text, "generated files.qip")
    for name in FORBIDDEN_QIP:
        if name in qip_text:
            raise ValueError(f"generated files.qip includes stale/foreign source {name!r}")

    print("PASS: parent Bucky JTFRAME wrapper/memory/source closure")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
