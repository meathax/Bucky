# Project status

This is a human summary. Machine state lives in `.mister/state.json` and generated reports.

## Current objective

Close the real-MiSTer K054539 missing-effects and intermittent-high-tone report
without regressing the previously corrected shadow priority and sprite
line-ownership paths.

## Current workflow

| Field | Value |
|---|---|
| Action | Three causal K054539 corrections implemented in RTL; focused tests duplicated |
| Scenario | Reverb RMW, rapid voice replacement, held Z80 write, gated sample ROM and 48 kHz deadline |
| Stage | Focused/complete component suites and duplicate fresh strict parent cold runs pass |
| Last completed run | `task-audio_boot_capture-20260812T054826223124Z`, 35 frames / 27,574,289 cycles |
| Last matching event/checkpoint | Duplicate frame-35 stop with zero PCM misses and byte-identical K054539 write/context/span/latch evidence |
| First mismatch/evidence gap | No source-level mismatch remains; only new real-MiSTer audio verification is pending |
| RTL edits permitted | YES, one evidenced causal correction at a time |
| Quartus state | Not invoked for the audio correction; no new RBF built |
| Hardware state | Reported RBF SHA-256 `b4cc50b2...e14f` has missing effects/high tone and predates these fixes; prior video fixes also await hardware confirmation |

## Next valid action

A new explicit RBF request is required before Quartus may run.  The resulting
MiSTer test must exercise rapid gameplay effects and
confirm all sounds, no intermittent tone, full circular shadows and no opaque
center blocks.

## Blocking evidence gaps

| ID | Gap | Why blocking | Smallest next experiment |
|---|---|---|---|
| HW-AUDIO-1 | Fixed RTL has not been loaded on MiSTer | The reported RBF predates the fixes, so only hardware can confirm all gameplay effects and absence of the tone | On a freshly authorized RBF, replay the same gameplay sequence and record direct/camera audio |
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
- K054539 reverb keeps the selected `widx` on the synchronous read port through
  `S_MIX`/`S_RVWR` and switches to the delayed address only for the actual
  write; feedback clear and channel RMW must never touch a stale slot.
- A pending or same-edge key-on outranks the retiring voice's live-position
  mirror and EOF key-off in 8-bit, 16-bit and DPCM modes; the next `S_LOAD`
  consumes the committed replacement start exactly once.
- K054539 CPU writes preserve the decapped hybrid bus phases: transparent
  fields follow the active strobe, key-off is level-visible, and key-on,
  `0x22d` and release-latched fields commit exactly once when `/WR` rises.
- Parent simulation counts PCM deadline misses and completed-line sprite
  overruns after reset transients.
- K053251 shadows pass when their numerically lower priority is in front of
  the winning layer (`PRSHA < winning_pri`); Bucky boot values 5 versus 16 are
  a permanent focused regression.
- The delayed shadow RMW path carries its producer-bank epoch and rejects a
  write if the line buffer has flipped.
- An in-flight draw that crosses HS is quarantined until its old-line tail
  finishes; the next tile is then allowed to write normally.
