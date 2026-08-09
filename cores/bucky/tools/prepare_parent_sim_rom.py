#!/usr/bin/env python3
"""Build private Verilator images for the parent bucky.zip set only."""

from __future__ import annotations

import argparse
import hashlib
import json
import zlib
import zipfile
from pathlib import Path


ZIP_SHA256 = "d9eab6109959a7a77e83871ea775954d10f0a607fa320b81d75713dc12f38987"
MEMBERS = {
    "173eab01.q5": 0x7785AC8A,
    "173eab02.q6": 0x9B45F122,
    "173a03.t5": 0xCD724026,
    "173a04.t6": 0x7DD54D6F,
    "173a07.f5": 0x4CDAEE71,
    "173a05.t8": 0xD14333B4,
    "173a06.t10": 0x6541A34F,
    "173a10.b8": 0x42FB0A0C,
    "173a11.a8": 0xB0D747C4,
    "173a12.b10": 0x0FC2AD24,
    "173a13.a10": 0x4CF85439,
    "173a08.b6": 0xDCDDED95,
    "173a09.a6": 0xC93697C4,
    "bucky.nv": 0x6A5986F3,
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_byte_hex(path: Path, data: bytes) -> None:
    with path.open("w", encoding="ascii", newline="\n") as stream:
        for value in data:
            stream.write(f"{value:02x}\n")


def write_word_hex(path: Path, data: bytes, width: int, byteorder: str) -> None:
    if len(data) % width:
        raise ValueError(f"{path.name}: byte length is not divisible by {width}")
    digits = width * 2
    with path.open("w", encoding="ascii", newline="\n") as stream:
        for offset in range(0, len(data), width):
            value = int.from_bytes(data[offset : offset + width], byteorder)
            stream.write(f"{value:0{digits}x}\n")


def interleave_word_lanes(parts: list[bytes], stride: int) -> bytes:
    if any(len(part) != len(parts[0]) for part in parts):
        raise ValueError("interleaved ROM members have different lengths")
    if stride != len(parts) * 2:
        raise ValueError("each source supplies one 16-bit lane")
    region = bytearray((len(parts[0]) // 2) * stride)
    for source_index, part in enumerate(parts):
        lane = source_index * 2
        for source_offset in range(0, len(part), 2):
            target = (source_offset // 2) * stride + lane
            region[target : target + 2] = part[source_offset : source_offset + 2]
    return bytes(region)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("zip", type=Path, help="private parent bucky.zip")
    parser.add_argument("output", type=Path, help="private output directory")
    args = parser.parse_args()

    archive = args.zip.resolve()
    output = args.output.resolve()
    if sha256(archive) != ZIP_SHA256:
        raise SystemExit("bucky.zip SHA-256 does not match the locked parent archive")

    with zipfile.ZipFile(archive) as source:
        blobs = {}
        for name, expected_crc in MEMBERS.items():
            data = source.read(name)
            actual_crc = zlib.crc32(data) & 0xFFFFFFFF
            if actual_crc != expected_crc:
                raise SystemExit(
                    f"{name}: CRC {actual_crc:08x}, expected {expected_crc:08x}"
                )
            blobs[name] = data

    output.mkdir(parents=True, exist_ok=True)

    main_region = bytearray(b"\xff" * 0x240000)
    for index, (high, low) in enumerate(
        zip(blobs["173eab01.q5"], blobs["173eab02.q6"])
    ):
        main_region[index * 2] = high
        main_region[index * 2 + 1] = low
    for index, (high, low) in enumerate(
        zip(blobs["173a03.t5"], blobs["173a04.t6"])
    ):
        target = 0x200000 + index * 2
        main_region[target] = high
        main_region[target + 1] = low

    tile_region = interleave_word_lanes(
        [blobs["173a05.t8"], blobs["173a06.t10"]], 4
    )
    sprite_region = interleave_word_lanes(
        [
            blobs["173a10.b8"],
            blobs["173a11.a8"],
            blobs["173a12.b10"],
            blobs["173a13.a10"],
        ],
        8,
    )
    pcm_region = blobs["173a08.b6"] + blobs["173a09.a6"]

    # 68000 words are big-endian values. Graphics memories are packed as
    # {byte3,byte2,byte1,byte0}, so their textual 32-bit value is little-endian.
    write_word_hex(output / "main.hex", main_region, 2, "big")
    write_byte_hex(output / "snd.hex", blobs["173a07.f5"])
    write_word_hex(output / "tile.hex", tile_region, 4, "little")
    write_word_hex(output / "sprite.hex", sprite_region, 4, "little")
    write_byte_hex(output / "pcm.hex", pcm_region)
    write_byte_hex(output / "nvram.hex", blobs["bucky.nv"])

    files = {}
    for name in ("main.hex", "snd.hex", "tile.hex", "sprite.hex", "pcm.hex", "nvram.hex"):
        path = output / name
        files[name] = {"bytes": path.stat().st_size, "sha256": sha256(path)}
    manifest = {
        "set": "bucky",
        "archive_sha256": ZIP_SHA256,
        "files": files,
    }
    (output / "parent-rom.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Prepared locked parent set in {output}")


if __name__ == "__main__":
    main()
