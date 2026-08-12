#!/usr/bin/env python3
"""Fail-closed static contracts for the Bucky GX173 production RTL.

This checker deliberately does not invoke an HDL compiler or simulator.  It
guards the source manifest, unique module ownership, MAME-visible address map,
byte lanes, interrupt levels, protection windows, and Quartus-17-hostile memory
declarations before generated project files exist.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys
import tomllib


PRODUCTION = (
    "bucky_colmix.v", "bucky_k053252.v", "bucky_k054000.v",
    "bucky_k054338.v", "bucky_k056832_romrd.v", "bucky_main.v",
    "bucky_video.v", "cowboys_k056832.v", "cowboys_lyro64.v",
    "cowboys_obj.v", "cowboys_sound.v", "jtbucky_game.v",
    "k053246_dma.v", "k053246_mmr.v", "k053247.v",
    "k053247_buffer.v", "k053247_draw.v", "k053247_gate.v",
    "k053251.v", "k054539.v", "k053246.sv", "k053246_scan.sv",
)
DISCONNECTED = {"k053246_draw.v", "k053246_objdraw.v", "k053246_skid.v"}
FOREIGN_MODULES = {
    "jtsimson_obj", "jtmoomesa_game", "jtbuckyaa_game", "jt053246_dma",
    "jt053246_mmr", "jtcolmix_053251", "jtaliens_scroll", "jt052109",
    "jt051962", "jt051960", "jtriders_dump", "jtriders_sound",
    "jt053260", "jt053260_channel", "jt053260_timer",
}

MAME_MAP = (
    r"map\(0x000000, 0x07ffff\)\.rom",
    r"map\(0x080000, 0x08ffff\)\.ram",
    r"map\(0x090000, 0x09ffff\)\.ram\(\)\.share\(m_spriteram\)",
    r"map\(0x0a0000, 0x0affff\)\.ram",
    r"map\(0x0c0000, 0x0c003f\)\.w\(m_k056832",
    r"map\(0x0c2000, 0x0c2007\)\.w\(m_k053246",
    r"map\(0x0c4000, 0x0c4001\)\.r\(m_k053246",
    r"map\(0x0ca000, 0x0ca01f\)\.w\(m_k054338",
    r"map\(0x0cc000, 0x0cc01f\).*umask16\(0x00ff\)",
    r"map\(0x0ce000, 0x0ce01f\).*moo_prot_w",
    r"map\(0x0d0000, 0x0d001f\).*umask16\(0x00ff\)",
    r"map\(0x0d2000, 0x0d203f\).*k054000.*umask16\(0x00ff\)",
    r"map\(0x0d6000, 0x0d601f\).*umask16\(0x00ff\)",
    r"map\(0x180000, 0x181fff\)\.mirror\(0x002000\)",
    r"map\(0x184000, 0x187fff\)\.ram",
    r"map\(0x190000, 0x191fff\)\.r\(m_k056832",
    r"map\(0x1b0000, 0x1b3fff\)\.ram",
    r"map\(0x200000, 0x23ffff\)\.rom",
)

RTL_CONTRACTS = (
    r"rom_cs\s*=.*eff_addr\[23:19\].*eff_addr\[23:18\]",
    r"ram_cs\s*=.*eff_addr\[23:16\].*8'h08.*8'h0a.*eff_addr\[23:14\].*10'h061",
    r"obj_cs\s*=.*eff_addr\[23:16\].*8'h09",
    r"vram_cs\s*=.*eff_addr\[23:14\].*0110_0000",
    r"romrd_cs\s*=.*eff_addr\[23:13\].*1100_1000",
    r"pal_cs\s*=.*eff_addr\[23:14\].*0110_1100",
    r"collision_cs\s*=.*eff_addr\[23:\s*6\].*03480",
    r"pair_we\s*=\s*pair_cs\s*&\s*~RnW\s*&\s*~LDSn",
    r"collision_cs\s*&\s*~eff_dsn\[0\]",
    r"cur_control2\[\s*7:0\].*cpu_dout\[\s*7:0\]",
    r"cur_control2\[15:8\].*cpu_dout\[15:8\]",
    r"irq5en\s*=\s*cur_control2\[5\]",
    r"irq4en\s*=\s*cur_control2\[11\]",
    r"irq5_ack\s*=\s*iack\s*&\s*\(A\[3:1\]==3'd5\)",
    r"irq4_ack\s*=\s*iack\s*&\s*\(A\[3:1\]==3'd4\)",
    r"eff_addr\[4:1\]==4'hc",
    r"blt_isobj\s*=.*8'h09",
    r"blt_isvram\s*=.*10'h060",
    r"blt_ispal\s*=.*10'h06c",
)


def manifest_files(text: str) -> list[str]:
    block = text.split("\nriders:", 1)[0]
    return re.findall(r"^\s*-\s+([A-Za-z0-9_]+\.(?:v|sv))\s*$", block, re.M)


def modules(text: str) -> list[str]:
    return re.findall(r"(?m)^\s*module\s+([A-Za-z_][A-Za-z0-9_$]*)\b", text)


def require(pattern: str, text: str, label: str) -> None:
    if re.search(pattern, text, re.S | re.M) is None:
        raise ValueError(f"{label}: missing contract /{pattern}/")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mame", type=Path,
                        default=Path("D:/Arcade/AI/mame289/src/mame/konami/moo.cpp"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    core = root / "cores" / "bucky"
    hdl = core / "hdl"

    listed = manifest_files((core / "cfg" / "files.yaml").read_text(encoding="utf-8"))
    if listed != list(PRODUCTION):
        missing = sorted(set(PRODUCTION) - set(listed))
        extra = sorted(set(listed) - set(PRODUCTION))
        raise ValueError(f"files.yaml production closure/order differs; missing={missing}, extra={extra}")
    if set(listed) & DISCONNECTED:
        raise ValueError("files.yaml includes a disconnected sprite experiment")

    owners: dict[str, list[str]] = {}
    production_text = ""
    for name in PRODUCTION:
        path = hdl / name
        text = path.read_text(encoding="utf-8")
        production_text += f"\n/* {name} */\n{text}"
        for module in modules(text):
            owners.setdefault(module, []).append(name)
    duplicates = {m: f for m, f in owners.items() if len(f) != 1}
    if duplicates:
        raise ValueError(f"duplicate production module definitions: {duplicates}")
    present_foreign = sorted(FOREIGN_MODULES & set(owners))
    if present_foreign:
        raise ValueError(f"foreign production modules: {present_foreign}")

    # Quartus 17 silently maps multidimensional unpacked arrays into logic.
    multidim = re.findall(
        r"(?m)^\s*(?:\(\*.*?\*\)\s*)?(?:reg|logic)\s*(?:signed\s*)?"
        r"\[[^\]]+\]\s+[A-Za-z_]\w*\s*\[[^\]]+\]\s*\[[^\]]+\]",
        production_text,
    )
    if multidim:
        raise ValueError(f"Quartus-17-hostile multidimensional memories: {multidim}")

    main_text = (hdl / "bucky_main.v").read_text(encoding="utf-8")
    for pattern in RTL_CONTRACTS:
        require(pattern, main_text, "bucky_main.v")

    # JTFRAME supplies active-low service and test signals.  Keep the OSD test
    # control enabled and preserve both signals without polarity inversion at
    # the GX173 input ports.
    macros_text = (core / "cfg" / "macros.def").read_text(encoding="utf-8")
    require(r"(?m)^JTFRAME_OSD_TEST\s*$", macros_text, "macros.def")
    game_text = (hdl / "jtbucky_game.v").read_text(encoding="utf-8")
    require(r"\.service\s*\(\s*\{4\{service\}\}\s*\)", game_text,
            "jtbucky_game.v")
    require(r"\.dip_test\s*\(\s*dip_test\s*\)", game_text, "jtbucky_game.v")
    require(r"if\s*\(\s*in0_cs\s*\)\s*port_in\s*=\s*"
            r"\{\s*8'hff\s*,\s*service\[3:0\]\s*,\s*coin\[3:0\]\s*\}",
            main_text, "bucky_main.v")
    require(r"if\s*\(\s*in1_cs\s*\)\s*port_in\s*=\s*"
            r"\{\s*8'hff\s*,\s*dipsw\[23:20\]\s*,\s*dip_test\s*,\s*1'b1\s*,"
            r"\s*eep_rdy\s*,\s*eep_do\s*\}", main_text, "bucky_main.v")

    dma_text = (hdl / "k053246_dma.v").read_text(encoding="utf-8")
    require(r"if\( rst \) dmaen_l <= 1'b0", dma_text, "k053246_dma.v")
    require(r"dma_ok\s*<=\s*0;.*lvbl_sh\s*<=\s*0", dma_text, "k053246_dma.v")
    buffer_text = (hdl / "k053247_buffer.v").read_text(encoding="utf-8")
    require(r"if\( rst \).*line\s*<=\s*1'b0;.*last_LHBL\s*<=\s*1'b0", buffer_text,
            "k053247_buffer.v")
    require(r"if\( rst \).*dly\s*<=.*rd_data\s*<=", buffer_text, "k053247_buffer.v")

    # GX173 keeps one full CPU-visible 64 KiB sprite-source RAM.  K053246 DMA
    # reads only words 0..7 from each 0x80-word slot through the RAM's second
    # registered port; metadata addresses must never alias onto draw words.
    video_text = (hdl / "bucky_video.v").read_text(encoding="utf-8")
    require(r"cowboys_obj\s*#\s*\(\s*\.RAMW\(15\)", video_text, "bucky_video.v")
    require(r"assign\s+orama\s*=\s*obj_cpu_addr\[14:0\]", video_text, "bucky_video.v")
    require(r"assign\s+orama_we\s*=\s*oram_we\s*&\s*\{2\{objsys_cs\}\}", video_text,
            "bucky_video.v")
    obj_text = (hdl / "cowboys_obj.v").read_text(encoding="utf-8")
    require(r"\.dma_data\s*\(\s*dma_source_data\s*\)", obj_text, "cowboys_obj.v")
    require(r"\.addr1a\s*\(\s*dma_src_addr\[RAMW-1:0\]\s*\)", obj_text,
            "cowboys_obj.v")
    require(r"assign\s+dma_src_addr\s*=\s*\{dma_addr\[11:4\],7'd0\}", obj_text,
            "cowboys_obj.v")
    require(r"assign\s+dma_source_data\s*=\s*dma_addr\[12\]\s*\?\s*16'h0000\s*:\s*ram_dma_data",
            obj_text, "cowboys_obj.v")

    mame_text = args.mame.read_text(encoding="utf-8")
    bucky_start = mame_text.index("void moo_prot_state::bucky_map")
    bucky_end = mame_text.index("void moo_prot_state::sound_map", bucky_start)
    bucky_map = mame_text[bucky_start:bucky_end]
    for pattern in MAME_MAP:
        require(pattern, bucky_map, "MAME 0.289 bucky_map")

    scenarios = tomllib.loads((core / "cfg" / "regressions.toml").read_text(encoding="utf-8"))
    scenario_rows = scenarios.get("scenario", [])
    scenario_sets = {row.get("set") for row in scenario_rows}
    expected_sets = {"bucky", "buckyea", "buckyjaa", "buckyuab", "buckyaab", "buckyaa"}
    if scenario_sets != expected_sets:
        raise ValueError(f"clone scenario coverage differs: {scenario_sets} != {expected_sets}")
    ids = [row.get("id") for row in scenario_rows]
    if len(ids) != len(set(ids)) or any(not value for value in ids):
        raise ValueError("regression scenario IDs must be nonempty and unique")
    policy = scenarios.get("checkpoint_policy", {})
    for key in ("save_before_input", "automatic_save", "require_save_confirmation",
                "reject_layout_mismatch", "reject_prior_frame_completion"):
        if policy.get(key) is not True:
            raise ValueError(f"checkpoint policy must enable {key}")

    print("PASS: static GX173 map/lane/IRQ/input/protection/source/memory contracts")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
