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
FORBIDDEN_QIP = (
    "jtsimson_obj.v",
    "jtmoomesa_game.v",
    "jtbuckyaa_game.v",
    # Disconnected Bucky experiments must not enter the production source
    # closure. Their modules are retained for historical reference only.
    "k053246_draw.v",
    "k053246_objdraw.v",
    "k053246_skid.v",
    "jt053246_dma.v",
    "jt053246_mmr.v",
    "jtcolmix_053251.v",
    "jtaliens_scroll.v",
    "jt052109.v",
    "jt051962.v",
    "jt051960.v",
    "jtriders_dump.v",
    "jtriders_sound.v",
    "jt053260.v",
    "jt053260_channel.v",
    "jt053260_timer.v",
)


def require(needle: str, haystack: str, label: str) -> None:
    if needle not in haystack:
        raise ValueError(f"{label}: missing {needle!r}")


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(
            f"usage: {Path(sys.argv[0]).name} <jtcores/cores/bucky> [derived-wrapper]",
            file=sys.stderr,
        )
        return 2

    core = Path(sys.argv[1]).resolve()
    # jtcore's normal build directory is cores/<core>/<target>. Older
    # staging helpers placed files.qip at the core root, so accept both
    # locations while always validating the same generated target set.
    generated = core / "mister"
    if not (generated / "files.qip").is_file():
        generated = core
    wrapper = Path(sys.argv[2]).resolve() if len(sys.argv) == 3 else generated / "jtbucky_game_sdram.v"
    ports = generated / "mem_ports.inc"
    qip = generated / "files.qip"
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
    require("cowboys_lyro64", wrapper_text, "generated sprite bank")
    if "jtframe_rom_1slot #(\n    .SDRAMW(SDRAMW-1),\n    // lyro" in wrapper_text:
        raise ValueError("generated sprite bank still uses the stock 32-bit slot")
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
