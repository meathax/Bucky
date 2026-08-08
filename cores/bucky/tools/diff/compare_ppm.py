#!/usr/bin/env python3
"""Compare two unfiltered binary P6 PPM framebuffer captures."""

from __future__ import annotations

import argparse
import pathlib
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Image:
    width: int
    height: int
    pixels: bytes


def read_token(data: bytes, offset: int) -> tuple[bytes, int]:
    length = len(data)
    while offset < length:
        if data[offset] == ord("#"):
            newline = data.find(b"\n", offset)
            if newline < 0:
                raise ValueError("unterminated PPM comment")
            offset = newline + 1
        elif chr(data[offset]).isspace():
            offset += 1
        else:
            break
    start = offset
    while offset < length and not chr(data[offset]).isspace():
        offset += 1
    if start == offset:
        raise ValueError("truncated PPM header")
    return data[start:offset], offset


def read_ppm(path: pathlib.Path) -> Image:
    data = path.read_bytes()
    magic, offset = read_token(data, 0)
    width_raw, offset = read_token(data, offset)
    height_raw, offset = read_token(data, offset)
    maximum_raw, offset = read_token(data, offset)
    if magic != b"P6":
        raise ValueError(f"{path}: expected binary P6 PPM")
    width, height, maximum = map(int, (width_raw, height_raw, maximum_raw))
    if width <= 0 or height <= 0 or maximum != 255:
        raise ValueError(f"{path}: unsupported dimensions or maxval")
    if offset >= len(data) or not chr(data[offset]).isspace():
        raise ValueError(f"{path}: missing pixel-data delimiter")
    if data[offset:offset + 2] == b"\r\n":
        offset += 2
    else:
        offset += 1
    pixels = data[offset:]
    expected = width * height * 3
    if len(pixels) != expected:
        raise ValueError(
            f"{path}: expected {expected} pixel bytes, got {len(pixels)}")
    return Image(width, height, pixels)


def rotate(image: Image, direction: str) -> Image:
    if direction == "none":
        return image
    if direction == "180":
        new_width, new_height = image.width, image.height
    else:
        new_width, new_height = image.height, image.width
    output = bytearray(len(image.pixels))
    for y in range(image.height):
        for x in range(image.width):
            if direction == "cw":
                nx, ny = image.height - 1 - y, x
            elif direction == "ccw":
                nx, ny = y, image.width - 1 - x
            elif direction == "180":
                nx, ny = image.width - 1 - x, image.height - 1 - y
            else:
                raise ValueError(f"unsupported rotation {direction}")
            source = (y * image.width + x) * 3
            target = (ny * new_width + nx) * 3
            output[target:target + 3] = image.pixels[source:source + 3]
    return Image(new_width, new_height, bytes(output))


def write_ppm(path: pathlib.Path, image: Image) -> None:
    path.write_bytes(
        f"P6\n{image.width} {image.height}\n255\n".encode("ascii") +
        image.pixels)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=pathlib.Path)
    parser.add_argument("candidate", type=pathlib.Path)
    parser.add_argument("--rotate-candidate",
                        choices=("none", "cw", "ccw", "180"), default="none")
    parser.add_argument("--channel-tolerance", type=int, default=0)
    parser.add_argument("--max-different-pixels", type=int, default=0)
    parser.add_argument("--diff", type=pathlib.Path,
                        help="write an amplified RGB difference PPM")
    args = parser.parse_args()

    if not 0 <= args.channel_tolerance <= 255:
        parser.error("--channel-tolerance must be between 0 and 255")
    if args.max_different_pixels < 0:
        parser.error("--max-different-pixels cannot be negative")

    try:
        reference = read_ppm(args.reference)
        candidate = rotate(read_ppm(args.candidate), args.rotate_candidate)
        if (reference.width, reference.height) != (
                candidate.width, candidate.height):
            raise ValueError(
                "dimension mismatch: "
                f"reference={reference.width}x{reference.height}, "
                f"candidate={candidate.width}x{candidate.height}")

        different = 0
        first: tuple[int, int] | None = None
        min_x, min_y = reference.width, reference.height
        max_x = max_y = -1
        channel_max = [0, 0, 0]
        difference = bytearray(len(reference.pixels))

        for pixel in range(reference.width * reference.height):
            base = pixel * 3
            deltas = [
                abs(reference.pixels[base + channel] -
                    candidate.pixels[base + channel])
                for channel in range(3)
            ]
            for channel, delta in enumerate(deltas):
                channel_max[channel] = max(channel_max[channel], delta)
                difference[base + channel] = min(255, delta * 4)
            if any(delta > args.channel_tolerance for delta in deltas):
                x, y = pixel % reference.width, pixel // reference.width
                different += 1
                if first is None:
                    first = (x, y)
                min_x, min_y = min(min_x, x), min(min_y, y)
                max_x, max_y = max(max_x, x), max(max_y, y)

        total = reference.width * reference.height
        percent = (different * 100.0 / total) if total else 0.0
        bbox = "none" if first is None else f"{min_x},{min_y}-{max_x},{max_y}"
        print(
            f"different_pixels={different}/{total} ({percent:.6f}%) "
            f"first={first or 'none'} bbox={bbox} "
            f"max_rgb={tuple(channel_max)}")
        if args.diff:
            write_ppm(args.diff, Image(reference.width, reference.height,
                                       bytes(difference)))
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    return 0 if different <= args.max_different_pixels else 1


if __name__ == "__main__":
    raise SystemExit(main())
