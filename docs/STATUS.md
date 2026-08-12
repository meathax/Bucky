# Project status

This is a human summary. Machine state lives in `.mister/state.json` and generated reports.

## Current objective

Close the real-MiSTer missing-shadow and cross-line sprite corruption shown in
the 2026-08-12 hardware video without changing the native video cadence.

## Current workflow

| Field | Value |
|---|---|
| Action | Shadow priority and sprite line-ownership fixes implemented |
| Scenario | Focused sprite regressions plus 60-frame cold parent run |
| Stage | Strict RTL/component regressions passed; hardware build deliberately not run |
| Last completed run | `video-fix-parent-60f`, 60 frames / 47,849,489 clocks |
| Last matching event/checkpoint | Final VBlank, zero PCM deadline misses and zero post-reset sprite-line overruns |
| First mismatch/evidence gap | Corrected shadows and dense intro still require a new real-MiSTer RBF test |
| RTL edits permitted | YES, one evidenced causal correction at a time |
| Quartus state | Not invoked for this task, per user request; no RBF built |
| Hardware state | Source video shows inverted shadow acceptance and sprite data crossing a line-buffer flip |

## Next valid action

When the user explicitly requests an RBF, build and deploy it, then replay the
same Stage 1 sequence on MiSTer and confirm full circular shadows and absence
of opaque center blocks.  Until then, preserve the current source/test state.

## Blocking evidence gaps

| ID | Gap | Why blocking | Smallest next experiment |
|---|---|---|---|
| HW-PERF-1 | No automated dense moving-gameplay PCB capture | Static/early simulation cannot prove absence of late sprite ownership errors | Load the fresh RBF and repeat the known dense scene while moving |
| VIDEO-1 | Exact PCB raster totals are not measured | MAME's configured 60 Hz is HLE and not physical timing proof | Measure CE/HS/VS totals on the deployed RBF before changing 512x264 timing |
| HW-VIDEO-2 | Fixed RTL has not been loaded on MiSTer | Camera footage proves the old RBF symptom, while simulation proves only the causal contracts | Build only on explicit request, then recapture 0:00.7-0:01.4 of the same sequence |

## Implemented throughput contracts

- Only SDRAM bank 3 retains the four-beat sprite-line burst; banks 0-2 use
  their normal cache geometry.
- The generated wrapper must instantiate `cowboys_lyro64`; validation rejects
  a stock `jtframe_rom_1slot` on bank 3.
- K054539 sample commits remain 384 enables apart, CPU data-port reads do not
  freeze the 48 kHz counter, and any missed boundary is a release failure.
- Parent simulation counts PCM deadline misses and completed-line sprite
  overruns after reset transients.
- K053251 shadows pass when their numerically lower priority is in front of
  the winning layer (`PRSHA < winning_pri`); Bucky boot values 5 versus 16 are
  a permanent focused regression.
- The delayed shadow RMW path carries its producer-bank epoch and rejects a
  write if the line buffer has flipped.
- An in-flight draw that crosses HS is quarantined until its old-line tail
  finishes; the next tile is then allowed to write normally.
