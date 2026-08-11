#!/usr/bin/env python3
"""Compare a MAME WAV against the parent bench's native final-mix CSV.

The Bucky JTFRAME mix is sampled at 192 kHz while MAME's reference capture is
normally 48 kHz.  The Verilator stream is decimated by four, then a bounded
lag search is used to absorb the frame-callback/audio-buffer phase difference.
This reports both scale-insensitive correlation and absolute sample error; it
does not silently declare a pass when one side is silent.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import wave
from pathlib import Path


def read_csv(path: Path):
    left, right = [], []
    with path.open(newline="") as fh:
        for row in csv.reader(line for line in fh if not line.startswith("#")):
            if len(row) != 3:
                continue
            left.append(int(row[1]))
            right.append(int(row[2]))
    return left, right


def read_wav(path: Path):
    with wave.open(str(path), "rb") as fh:
        if fh.getnchannels() != 2 or fh.getsampwidth() != 2:
            raise ValueError("MAME WAV must be signed 16-bit stereo")
        raw = fh.readframes(fh.getnframes())
        vals = [int.from_bytes(raw[i : i + 2], "little", signed=True)
                for i in range(0, len(raw), 2)]
        return fh.getframerate(), vals[0::2], vals[1::2]


def rms(values):
    if not values:
        return 0.0
    return math.sqrt(sum(v * v for v in values) / len(values))


def corr(a, b):
    if not a or not b or len(a) != len(b):
        return 0.0
    ma = sum(a) / len(a)
    mb = sum(b) / len(b)
    da = [x - ma for x in a]
    db = [x - mb for x in b]
    den = math.sqrt(sum(x * x for x in da) * sum(x * x for x in db))
    return sum(x * y for x, y in zip(da, db)) / den if den else 0.0


def score(ref_l, ref_r, dut_l, dut_r):
    if len(ref_l) != len(dut_l):
        n = min(len(ref_l), len(dut_l))
        ref_l, ref_r, dut_l, dut_r = ref_l[:n], ref_r[:n], dut_l[:n], dut_r[:n]
    n = len(ref_l)
    if not n:
        return {"samples": 0, "correlation": 0.0, "mae": None, "rms_ref": 0.0, "rms_dut": 0.0}
    mae = (sum(abs(a - b) for a, b in zip(ref_l, dut_l)) +
           sum(abs(a - b) for a, b in zip(ref_r, dut_r))) / (2 * n)
    return {
        "samples": n,
        "correlation": (corr(ref_l, dut_l) + corr(ref_r, dut_r)) / 2,
        "mae": mae,
        "rms_ref": (rms(ref_l) + rms(ref_r)) / 2,
        "rms_dut": (rms(dut_l) + rms(dut_r)) / 2,
        "max_ref": max(max(map(abs, ref_l)), max(map(abs, ref_r))),
        "max_dut": max(max(map(abs, dut_l)), max(map(abs, dut_r))),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mame", type=Path, required=True)
    ap.add_argument("--verilator", type=Path, required=True)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--start-frame", type=float, default=520)
    ap.add_argument("--end-frame", type=float, default=650)
    ap.add_argument("--fps", type=float, default=59.19)
    ap.add_argument("--max-lag-ms", type=float, default=20)
    args = ap.parse_args()

    rate, ml, mr = read_wav(args.mame)
    vl, vr = read_csv(args.verilator)
    if rate <= 0 or len(vl) < 2:
        raise SystemExit("audio capture is empty")
    # The testbench records 192 kHz; decimate to MAME's WAV rate.  If the
    # generated stream changes rate, derive the integer ratio explicitly.
    native_rate = 192000
    if native_rate % rate:
        raise SystemExit(f"unsupported rate ratio {native_rate}/{rate}")
    decim = native_rate // rate
    vl, vr = vl[::decim], vr[::decim]
    start = round(args.start_frame * rate / args.fps)
    end = min(len(ml), round(args.end_frame * rate / args.fps))
    ref_l, ref_r = ml[start:end], mr[start:end]
    # Search only a small phase window; a large lag would mean the stimulus or
    # clock alignment is wrong, not an audio mixer detail.
    max_lag = round(args.max_lag_ms * rate / 1000)
    best = None
    for lag in range(-max_lag, max_lag + 1):
        a0 = max(0, lag)
        b0 = max(0, -lag)
        n = min(len(ref_l) - a0, len(vl) - b0)
        if n <= rate // 100:
            continue
        cur = score(ref_l[a0:a0 + n], ref_r[a0:a0 + n], vl[b0:b0 + n], vr[b0:b0 + n])
        cur["lag_samples"] = lag
        cur["lag_ms"] = lag * 1000 / rate
        if best is None or cur["correlation"] > best["correlation"]:
            best = cur
    report = {"mame_rate": rate, "native_verilator_rate": native_rate,
              "decimation": decim, "mame_frame_rate": args.fps,
              "window_frames": [args.start_frame, args.end_frame],
              "mame_window_samples": len(ref_l), "verilator_samples": len(vl),
              "best": best}
    text = json.dumps(report, indent=2) + "\n"
    if args.out:
        args.out.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
