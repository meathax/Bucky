#!/usr/bin/env python3
"""Validate generated Bucky MRAs against current MiSTer conventions."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

EXPECTED = {"bucky", "buckyea", "buckyjaa", "buckyuab", "buckyaab", "buckyaa"}
EXPECTED_RBF = "Arcade-Bucky"
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
    for tag in ("homebrew", "bootleg"):
        value = text(root, tag)
        if value and value not in {"yes", "no"}:
            errors.append(f"<{tag}> must be yes/no")
    for rom in root.findall("rom"):
        if "type" in rom.attrib:
            errors.append("ROM type attribute must be omitted")
    main_rom = root.find("rom[@index='0']")
    header = [] if main_rom is None else [int(x, 16) for x in (main_rom.findtext("part") or "").split()]
    if header[:10] != [0x00,0x00,0x40,0x02,0x80,0x02,0x80,0x04,0x80,0x0c]:
        errors.append("ROM header offsets do not match GX173 stream layout")
    raw = path.read_text(encoding="utf-8")
    if "eeprom - starts at 0x1080000 - length 0x80" not in raw:
        errors.append("EEPROM is not at stream offset 0x1080000")
    buttons = root.find("buttons")
    if buttons is None or buttons.attrib.get("count") != "3":
        errors.append("three action buttons are required")
    if text(root, "players") != "4":
        errors.append("four-player metadata is required")
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
    # The parent EAB set is the current bring-up/acceptance target.  Keep the
    # historical six-set validation available for release metadata audits, but
    # allow CI and hardware bring-up to validate only the ROM that is actually
    # loaded.  This avoids treating clone metadata as a functional requirement.
    parent_only = False
    args = list(sys.argv[1:])
    if "--parent-only" in args:
        parent_only = True
        args.remove("--parent-only")
    roots = [Path(arg) for arg in args] or [Path(__file__).parents[1] / "releases"]
    files = sorted({p for root in roots for p in ([root] if root.is_file() else root.glob("*.mra"))})
    found = {validate(path) for path in files}
    if parent_only and "bucky" not in found:
        raise ValueError("parent-only validation requires bucky.mra")
    missing = set() if parent_only else EXPECTED - found
    if missing:
        raise ValueError("missing sets: " + ", ".join(sorted(missing)))
    print(f"PASS: {len(files)} Bucky MRAs satisfy MiSTer conventions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
