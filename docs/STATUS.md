# Project status

This is a human summary. Machine state lives in `.mister/state.json` and generated reports.

## Current objective

Close the real-MiSTer K054539 missing-effects and intermittent-high-tone report
without regressing the previously corrected shadow priority and sprite
line-ownership paths.

## Current workflow

| Field | Value |
|---|---|
| Action | Corrected the MRA download layout so all 4 MiB of K054539 PCM enter SDRAM bank 1 |
| Scenario | Real non-XL `jtframe_dwnld` with the release MRA header and all PCM seam/boundary addresses |
| Stage | Old MRA fails the new release validator; corrected MRA, source gate and complete audio component suite pass |
| Last completed run | `cores/bucky/tools/run_component_tests.ps1 -AudioOnly`, including `tb_bucky_download_layout` |
| Last matching event/checkpoint | PCM offsets `0`, `0x1fffff`, `0x200000`, `0x3fffff` route to bank 1; tile/object/PROM starts route to banks 2/3/PROM |
| First mismatch/evidence gap | Corrected MRA has not yet been replayed on real MiSTer |
| RTL edits permitted | YES, one evidenced causal correction at a time |
| Quartus state | Not invoked; the dominant fix is MRA-only and does not require a new RBF |
| Hardware state | Fresh RBF `23bf8b4a...30cd` reproduced the symptom with installed broken MRA `0f58f825...7500`; corrected MRA is `6f7b36b6...32ce` |

## Next valid action

Install the corrected `Bucky O'Hare.mra`, relaunch the existing fresh RBF through that
MRA, and exercise rapid gameplay effects.  No Quartus/RBF build is needed for
this test.  Confirm all sounds and absence of the intermittent tone; video
fixes remain a separate hardware gate.

## Blocking evidence gaps

| ID | Gap | Why blocking | Smallest next experiment |
|---|---|---|---|
| HW-AUDIO-1 | Corrected MRA has not been replayed on MiSTer | The fresh RBF still received no PCM because the old MRA routed that region to `prom_we` | Install MRA SHA-256 `6f7b36b6...32ce`, relaunch the existing RBF and replay the same gameplay sequence |
| HW-PERF-1 | No automated dense moving-gameplay PCB capture | Static/early simulation cannot prove absence of late sprite ownership errors | Load the fresh RBF and repeat the known dense scene while moving |
| VIDEO-1 | Exact PCB raster totals are not measured | MAME's configured 60 Hz is HLE and not physical timing proof | Measure CE/HS/VS totals on the deployed RBF before changing 512x264 timing |
| HW-VIDEO-2 | Fixed RTL has not been loaded on MiSTer | Camera footage proves the old RBF symptom, while simulation proves only the causal contracts | Build only on explicit request, then recapture 0:00.7-0:01.4 of the same sequence |

## Implemented throughput contracts

- Only SDRAM bank 3 retains the four-beat sprite-line burst; banks 0-2 use
  their normal cache geometry.
- The non-XL five-entry download header maps bank starts 0-3 followed by PROM
  start.  K054539 PCM immediately follows the sound ROM in bank 1 at local byte
  offset `0x40000`; EEPROM, not PCM, owns the fifth/PROM boundary.
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
