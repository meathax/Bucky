#!/usr/bin/env python3
"""Validate generated Bucky MRAs against current MiSTer conventions."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

EXPECTED = {"bucky", "buckyea", "buckyjaa", "buckyuab", "buckyaab", "buckyaa"}


def text(root: ET.Element, tag: str) -> str:
    node = root.find(tag)
    return "" if node is None or node.text is None else node.text.strip()


def setname(root: ET.Element) -> str:
    return text(root, "setname")


def validate(path: Path) -> str:
    root = ET.parse(path).getroot()
    errors: list[str] = []
    name = setname(root)
    if text(root, "rbf") != "Bucky":
        errors.append("<rbf> must be Bucky")
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
    if errors:
        raise ValueError(f"{path}: " + "; ".join(errors))
    return name


def main() -> int:
    roots = [Path(arg) for arg in sys.argv[1:]] or [Path(__file__).parents[1] / "releases"]
    files = sorted({p for root in roots for p in ([root] if root.is_file() else root.glob("*.mra"))})
    found = {validate(path) for path in files}
    missing = EXPECTED - found
    if missing:
        raise ValueError("missing sets: " + ", ".join(sorted(missing)))
    print(f"PASS: {len(files)} Bucky MRAs satisfy MiSTer conventions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
