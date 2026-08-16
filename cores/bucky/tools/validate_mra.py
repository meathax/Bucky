#!/usr/bin/env python3
"""Validate generated Bucky MRAs against current MiSTer conventions."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

EXPECTED = {"bucky"}
EXPECTED_RBF = "Arcade-Bucky"
EXPECTED_HEADER = [
    0x00, 0x00,  # bank 0: maincpu
    0x40, 0x02,  # bank 1: soundcpu + PCM
    0x80, 0x06,  # bank 2: K056832 tiles
    0x80, 0x08,  # bank 3: K053246 objects
    0x80, 0x10,  # PROM start: EEPROM
]
EXPECTED_REGION_MARKERS = [
    "maincpu - starts at 0x0 - length 0x240000",
    "soundcpu - starts at 0x240000 - length 0x40000",
    "pcm - starts at 0x280000 - length 0x400000",
    "k056832 - starts at 0x680000 - length 0x200000",
    "obj - starts at 0x880000 - length 0x800000",
    "eeprom - starts at 0x1080000 - length 0x80",
]
FORBIDDEN_TAGS = {
    "about", "mratimestamp", "mameversion", "year", "manufacturer",
    "players", "region", "homebrew", "bootleg",
}
PARENT_ROMS = {
    "173eab02.q6": "9b45f122",
    "173eab01.q5": "7785ac8a",
    "173a04.t6": "7dd54d6f",
    "173a03.t5": "cd724026",
    "173a07.f5": "4cdaee71",
    "173a05.t8": "d14333b4",
    "173a06.t10": "6541a34f",
    "173a10.b8": "42fb0a0c",
    "173a11.a8": "b0d747c4",
    "173a12.b10": "0fc2ad24",
    "173a13.a10": "4cf85439",
    "173a08.b6": "dcdded95",
    "173a09.a6": "c93697c4",
    "bucky.nv": "6a5986f3",
}


def text(root: ET.Element, tag: str) -> str:
    node = root.find(tag)
    return "" if node is None or node.text is None else node.text.strip()


def setname(root: ET.Element) -> str:
    return text(root, "setname")


def validate(path: Path) -> str:
    root = ET.parse(path).getroot()
    errors: list[str] = []
    name = setname(root)
    if text(root, "rbf") != EXPECTED_RBF:
        errors.append(f"<rbf> must be {EXPECTED_RBF}")
    if text(root, "resolution") != "15kHz":
        errors.append("<resolution> must be 15kHz")
    if name not in EXPECTED:
        errors.append(f"unexpected setname {name!r}")
    present_forbidden = sorted(tag for tag in FORBIDDEN_TAGS if root.find(tag) is not None)
    if present_forbidden:
        errors.append("unused catalog metadata must be omitted: " + ", ".join(present_forbidden))
    for rom in root.findall("rom"):
        if "type" in rom.attrib:
            errors.append("ROM type attribute must be omitted")
    main_rom = root.find("rom[@index='0']")
    header = [] if main_rom is None else [int(x, 16) for x in (main_rom.findtext("part") or "").split()]
    if header[:10] != EXPECTED_HEADER:
        errors.append(
            "ROM header must map sound+PCM to SDRAM bank 1 and reserve "
            "boundary 4 for PROM: " + " ".join(f"{value:02X}" for value in EXPECTED_HEADER)
        )
    raw = path.read_text(encoding="utf-8")
    marker_positions = [raw.find(marker) for marker in EXPECTED_REGION_MARKERS]
    if any(position < 0 for position in marker_positions):
        missing_markers = [
            marker for marker, position in zip(EXPECTED_REGION_MARKERS, marker_positions)
            if position < 0
        ]
        errors.append("missing corrected ROM layout marker(s): " + "; ".join(missing_markers))
    elif marker_positions != sorted(marker_positions):
        errors.append("ROM regions must be ordered maincpu,soundcpu,pcm,k056832,obj,eeprom")
    buttons = root.find("buttons")
    if buttons is None or buttons.attrib.get("count") != "3":
        errors.append("three action buttons are required")
    elif name == "bucky":
        expected_names = "Shoot,Jump,Special,Start,Coin,Pause,Service,Test"
        expected_default = "A,B,X,Start,Select,-,L,R"
        if buttons.attrib.get("names") != expected_names:
            errors.append(
                "Bucky button positions must be "
                "Shoot,Jump,Special,Start,Coin,Pause,Service,Test"
            )
        if buttons.attrib.get("default") != expected_default:
            errors.append(
                "Bucky Service/Test defaults must map to L/R "
                "(not the unmapped '-')"
            )
    if main_rom is not None and "md5" in main_rom.attrib:
        errors.append("disabled ROM md5 attribute must be omitted")
    if "Core credits" in (buttons.attrib.get("names", "") if buttons is not None else ""):
        errors.append("JTFRAME Core credits button label must be omitted")
    if "Jotego" in raw or "JTFRAME" in raw:
        errors.append("JT/JTFRAME branding must be omitted")
    if name == "bucky":
        main_rom = root.find("rom[@index='0']")
        parts = {} if main_rom is None else {
            node.attrib.get("name", ""): node.attrib.get("crc", "")
            for node in main_rom.findall(".//part[@name]")
        }
        if parts != PARENT_ROMS:
            errors.append("parent ROM names/CRCs do not match MAME EAB declarations")
        interleave = [] if main_rom is None else main_rom.findall("interleave")
        if [node.attrib.get("output") for node in interleave] != ["16", "16", "32", "64"]:
            errors.append("parent interleave widths must be 16,16,32,64")
    if errors:
        raise ValueError(f"{path}: " + "; ".join(errors))
    return name


def main() -> int:
    # The parent EAB set is the only currently verified/distributable target.
    # Clone metadata can be added later only after its ROM and behavior are
    # independently validated.
    parent_only = False
    args = list(sys.argv[1:])
    if "--parent-only" in args:
        parent_only = True
        args.remove("--parent-only")
    roots = [Path(arg) for arg in args] or [Path(__file__).parents[1] / "releases"]
    files = sorted({p for root in roots for p in ([root] if root.is_file() else root.glob("*.mra"))})
    found = {validate(path) for path in files}
    if parent_only and "bucky" not in found:
        raise ValueError("parent-only validation requires Bucky O'Hare.mra")
    missing = set() if parent_only else EXPECTED - found
    if missing:
        raise ValueError("missing sets: " + ", ".join(sorted(missing)))
    print(f"PASS: {len(files)} Bucky MRAs satisfy MiSTer conventions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
