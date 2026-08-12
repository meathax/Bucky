# Bucky O'Hare implementation status

## Baseline - 2026-08-08

- This is a Git source repository containing only the independent Bucky core;
  the original multi-core donor trees are not distributed here.
- Current gate: Bucky source fork and focused device verification.
- Reference driver: MAME 0.289 `src/mame/konami/moo.cpp`, system `bucky`.
- ROM archive SHA-256: `D9EAB6109959A7A77E83871EA775954D10F0A607FA320B81D75713DC12F38987`.
- MAME executable: `D:\arcade\ai\mameexe\mame.exe`, SHA-256
  `AF6966108D9B52C22465C6D50F4E5D50CC371B50F2D27DC443935F287AAD37A3`.
- Hardware evidence copied to ignored `.workbench/upstream`; source identities are in `SOURCES.md`.
- The original Moo Mesa donor remains pinned by remote repository and commit in
  `SOURCES.md`; adapted files retain their provenance notices.
- No Bucky Verilator, Quartus or hardware result exists yet.

## Known reference limitations

- MAME marks every Bucky set `MACHINE_IMPERFECT_GRAPHICS`.
- Known MAME/source comments include incomplete shadow-priority modes, sprite zoom rounding gaps and
  zero-Z sprite filtering. PCB and silicon evidence supersede MAME for these cases.
- The existing Moo Mesa K054338/color mixer and K054539 contain documented approximations/TODOs.

## First implementation boundary

The first acceptance gate is a compiling Bucky fork with exact ROM layout, address decode and focused
K054000/K054338 tests. Real-game accuracy claims begin only after deterministic MAME and Verilator runs.

## Implementation checkpoint - 2026-08-08

- Forked the pinned Moo Mesa donor into the independent `cores/bucky` source
  tree; the donor tree itself is not part of this repository.
- Added the exact Bucky main map, including separate RAM banks at `0x080000`, `0x0a0000`, and
  `0x184000-0x187fff`, exact custom-chip windows, 4096-color palette RAM, and data ROM.
- Added an independent K054000 implementation and byte-lane wrapper. A live MAME 0.289 probe passed
  the complete published 20-step register/status sequence; parent ROM audit also passed.
- Added a schematic-derived K054338 color pipeline: two-bit MIX selection, interpolation/addition,
  three signed shadow/highlight tables, clamp disable, background force, input-delay controls, and
  external-DAC brightness scaling. K053251 remains a separate priority device.
- Widened tile MIX attributes to two bits, expanded palette storage to 4096 xRGB888 entries, applied
  Bucky layer offsets and sprite offset, and enabled zero-Z object suppression (`zmask=0x00ff`).
- Generated and validated six MAME 0.289 MRAs. The main stream ends with EEPROM at `0x1080000` and
  JTFRAME also receives its writable 128-byte NVRAM payload.
- Yosys syntax/elaboration checks pass for K054000, K054338, and modified main/video integration.
- Strict Verilator tests remain queued: the global Verilator mutex is owned by other processes. No
  pass is claimed until both focused testbenches actually execute through the safe wrappers.
- No Quartus build, RBF generation, MiSTer deployment, or hardware claim has been made.
- A live long-run sound-bus probe observed 71,825 K054539 writes and 1,014 key-ons with zero reverse-playback configurations; reverse playback is deferred unless a Bucky scenario or higher-tier evidence requires it.

## Parent POST/attract verification - 2026-08-09

- Parent-only `bucky.zip` Verilator integration now runs with the exact MAME ROM layout,
  generated SDRAM model and matching default DIP word (`0x00a00000`).
- The Z80/K054321 exchange reaches the expected status `0x0f`; the earlier apparent sound
  failure was a diagnostic mistake, not a proven RTL mismatch.
- The POST mailbox at 68000 `$080bfc`/`$080bfe` is written as `0x0000/0x0000`, matching a
  known-good MAME attract state. Later differential work corrected the original interpretation
  of `PC=$1d24`: the renderer entry is `$1d24`, but a CPU parked there is the post-fetch PC of
  the generic `$1d22` exception loop (`bra $1d22`). Vector/bus evidence is required to distinguish
  a transient legitimate entry from the persistent exception state.
- A 400-frame parent run completed with no non-zero mailbox stop. The final strict safe-wrapper
  run reached `PC=$1a80` and wrote both mailbox words `0x0000/0x0000`; the phase-gated stop then
  finished successfully. A sparse-PC 280-frame run reaches the expected diagnostic renderer at
  `$1d24` with a zero mailbox; the subsequent attract-loop PC transition is still not locked as
  a checkpoint. No Quartus/RBF or MiSTer hardware test has been performed.

## Pre-hardware recheck - 2026-08-09

- Re-ran the strict K053252, K054000, K054338, K056832 ROM-readback and K054539 component
  benches through the safe Verilator path; all five passed.
- Re-ran the parent-only source/MRA/JTFRAME/Yosys audit; it passed with zero Yosys `check`
  errors. The emitted memory/register notices are expected elaboration warnings, not functional
  failures.
- A three-frame parent smoke run produced a valid 384x224 PPM capture and deterministic trace.
  The captured frame is the reset/POST black scene, so it is a format/timing smoke result only;
  it is not yet a gameplay video match.
- The stale repository-level `hdl-trace.jsonl` remains an empty artifact from an earlier failed
  differential attempt; it is not used as acceptance evidence. A fresh pair was generated from
  the parent `bucky.zip` ROM and MAME 0.289: `.workbench/mame-parent-trace.jsonl` contains 475
  normalized reset/POST events, and the three-frame RTL trace continues for 1,000 events. The
  complete MAME prefix matches exactly; this is an initial prefix match, not yet a gameplay-length
  differential closure.
- Corrected the parent integration bench's cabinet defaults to JTFRAME's active-low convention:
  released coin/start/service/joystick inputs are now all ones. Added optional deterministic
  `COIN_FRAME`, `START_FRAME`, `INPUT_PULSE`, `GAMEPLAY_DIAG` and `REQUIRE_GAMEPLAY` controls to
  [tb_bucky_parent.sv](cores/bucky/hdl/sim/tb_bucky_parent.sv) and its PowerShell runner. A three-
  frame directed test showed the expected one-frame pulses (`coin=e`, then `start=e`) without
  disturbing reset/POST.
- The first long-run gameplay assertion also demonstrated that an address-only `PC=$3a92` watch
  is insufficient: that address occurs during early boot. The detector is now gated to the
  post-POST window (frame 280 or after the requested start pulse), so a future `REQUIRE_GAMEPLAY`
  pass cannot be satisfied by the boot helper.
- The first valid-ROM directed gameplay run (340 frames, coin at 300, start at 320) intentionally
  failed the hardened gate: at frame 320 the CPU was parked at `$1d24` with mailbox `0/0`. This is
  now classified as the generic exception loop, not a long-running renderer. The next run uses the
  MAME-derived two-credit schedule (coin frames 240 and 320, start frame 460, 20-frame pulses)
  and runs through frame 520.

## MAME differential blocker iteration - 2026-08-09

- Locked reference: MAME 0.289 parent `bucky`, executable SHA-256
  `AF6966108D9B52C22465C6D50F4E5D50CC371B50F2D27DC443935F287AAD37A3`, parent ROM SHA-256
  `D9EAB6109959A7A77E83871EA775954D10F0A607FA320B81D75713DC12F38987`, default DIPs, fresh workdir,
  no input. ROM audit passes.
- Untainted MAME captures in `.workbench/mame/blocker-diff-2` and `blocker-diff-3` prove that the
  real `$1d24` routine executes its descending K056832 VRAM clear at `$1dd8-$1dde`, returns, and
  reaches attract around reference frame 425. MAME was not mutated.
- First meaningful RTL divergence: the parent J68 model reaches the POST/init region, then remains
  at reported PC `$1d24` indefinitely and never reaches the post-POST/gameplay milestone. ROM
  disassembly proves `$1d22` is the common exception-vector self-loop, so `$1d24` is its post-fetch
  PC rather than evidence that the renderer itself is stalled.
- Root validation defect: `run_parent_verilator.sh` alone forced `JTFRAME_J68`; production synthesis
  does not define it and therefore instantiates fx68k. The differential acceptance model was testing
  a different 68000 implementation from the RBF path and converting a J68-specific exception into
  an apparent GX173/core failure.
- Fix implemented: the parent build now defaults to fx68k and accepts `BUCKY_SIM_CPU=j68` only as an
  explicit diagnostic option. Trace/frame/gameplay PC visibility uses `bucky_main.pc_last`, avoiding
  a J68-only hierarchy. A compact J68-only exception probe reports vector/fault registers without
  transaction-history arrays.
- Verification status: `git diff --check` passes. The fx68k build and post-fix parent regression are
  no longer pending. The machine-wide cap has been removed and concurrent Verilator models were
  observed running; the safe wrappers remain in use for process safety without serialization.
- The parent harness now selects fx68k by default, substitutes fx68k's upstream
  `hdl/verilator` source variants, and stages both fx68k decode ROMs. This removes the prior
  time-zero zero-decode assertion without changing production CPU RTL.
- First fx68k divergence: the default 12-bit JTFRAME DTACK recovery accumulator overflowed during
  the parent's long startup stream at frame 12. The parent now sets `WD=12` (18 total bits), which
  changes only accumulator capacity and prevents the production fx68k clock-recovery state from
  wrapping after 4095 delayed phases.
- Focused verification passed at 32 and 64 cold-boot frames. The 64-frame run reached POST
  `PC=$19c8`, retained mailbox `0000/0000`, and completed with an explicit testbench PASS marker;
  logs are `.workbench/fx68k-recovery.log` and `.workbench/fx68k-64.log`.
- The runner now uses a per-process runtime directory and requires a testbench-written PASS marker,
  so an assertion/watchdog `$finish` can no longer be mislabeled as success merely because the
  Verilator process returned exit code zero.
- Strict K053252, K054000, K054338, K056832 ROM-readback and K054539 component tests pass. The
  parent-only MRA/source/provenance/JTFRAME/Yosys pre-hardware audit also passes.
- Remaining parent gate: run production fx68k through the complete POST and MAME-aligned attract
  milestone (MAME reaches attract around frame 425), then execute the directed coin/start gameplay
  scenario. No Quartus/RBF build or hardware result is claimed.

## Hash-valid parent gate correction - 2026-08-09

- Retracted the apparent 600-frame gameplay PASS and black frame-580 comparison produced with
  `-RomDir rom`: that directory contains only `bucky.zip`, while the bench expected six generated
  `.hex` images. Verilator only warned when `$readmemh` files were absent, allowing an all-zero ROM
  model to scan addresses and falsely satisfy PC-only milestones.
- Added `prepare_parent_sim_rom.py`. It accepts only the locked parent archive SHA-256, verifies all
  parent-member CRCs, reconstructs MAME's 16/32/64-bit lane interleaves, and writes private images
  plus `parent-rom.json` under `.workbench/parent-rom`. Clone program ROMs in the merged ZIP are not
  read. `run_parent_sim.ps1` now fails before Verilator on a missing/empty image or manifest/hash
  mismatch; the old `rom` directory fails this gate as intended.
- A strict hash-valid 16-frame run loaded every image and restored the expected early alignment:
  RTL frame 16 `PC=$001554`, MAME frame 16 `PC=$001550`. K054338 REG15 reached `0x0003`, K053251
  priorities reached `16/32/63`, and non-zero tile-layer pixels were present during initialization.
- The complete strict hash-valid run reached the exact attract PC `$003644` at RTL frame 482 versus
  MAME frame 425 (57 frames late), with mailbox `0000/0000`. Coin was asserted at frame 470. By RTL
  frame 496 the CPU had entered the generic `$001d22/$001d24` exception loop; Start at frame 510 was
  therefore never accepted and the directed gameplay gate correctly failed at frame 600.
- The hash-valid Verilator frame 580 is 384x224 but entirely black (0/86,016 non-black pixels). The
  locked MAME frame 580 with identical inputs has 86,016/86,016 non-black pixels and 176 colors.
  This remains a real downstream symptom, but the earlier causal blocker is the unexpected 68000
  exception immediately after attract.
- Normal IRQ4/IRQ5 vectors point to `$002bba/$002b8a`, not `$001d22`; the latter is shared by most
  unexpected vectors. The first exception-vector probe produced no vector evidence because it was
  accidentally inside the optional `JTFRAME_J68` guard and was absent from the fx68k build. Its
  source placement is corrected for the next session, but it has not been rebuilt or rerun because
  the user requested all Verilator work stop.
- All Verilator processes started by this task are stopped. No Quartus build, RBF generation, or
  MiSTer hardware deployment was performed.

## Main-ROM cache blocker - 2026-08-10

- The production fx68k failure is deterministic at parent RTL frame 488.  A completed program
  fetch at `$0056f2` returns `$ffea` although the ROM contains `$20db`; fx68k then correctly takes
  Line-F through vector `$2c/$2e` and reaches the common `$1d22/$1d24` exception loop.
- The accepted-transaction probe proved this is upstream of fx68k and the CPU input mux: at the
  bad edge, both `cpu_din` and raw JTFRAME `rom_data` are `$ffea` with `rom_ok=1`.  `$ffea` is the
  real preceding word at `$0056fa`; ROM reconstruction and endianness are correct.
- One-bit request arming, registered-address `rom_ok` qualification, DSn-gating, and a broad
  address-valid bubble were rejected by strict cold runs.  The first three leave the same bad
  frame-488 transaction; the broad bubble over-stalls normal fetches and overflows DTACK recovery
  at frame 249.
- Root cause is the two-line JTFRAME burst cache on the 64-bit bank-0 return path retaining the
  wrong adjacent burst word for a live main-ROM request.  `OKLATCH=0` is ineffective in this
  JTFRAME revision because the bcache's `data_ok` expression does not use that parameter.
- Fix: `main.cache_size: 8` in `cfg/mem.yaml` selects JTFRAME's requested-word cache, which stores
  only the explicitly served 16-bit word instead of adjacent burst companions.  The local
  workbench wrapper predates this manifest change, so `prepare_bucky_sdram.py` creates an asserted,
  derived wrapper for Verilator without modifying the upstream generated file.
- A complete strict, visible-SDL, hash-valid parent run reached attract at frame 476 (previously
  482), crossed the former failure, and ended frame 500 at normal PC `$0014c4`.  Its journal has no
  `$2c/$2e` or other unexpected vector reads and its log has no `FX68K_LINEF`; only IRQ4/IRQ5
  `$70-$76` and intentional TRAP #0 `$80/$82` reads occur.
- The first `REQUIRE_NO_EXCEPTION` implementation falsely treated any normal visit to `$1d24` as
  an exception.  It now gates on actual unexpected low-vector reads.  A clean-marker rerun of that
  corrected gate was externally terminated at frame 362 (exit `-1`), not by an RTL assertion.
  Directed coin/start gameplay and a fresh uninterrupted automated PASS remain pending.
- No Quartus build, RBF generation, or MiSTer hardware deployment was performed.

## Sprite-source mapping blocker - 2026-08-10

- The parent reaches directed gameplay (`START_ACCEPTED` at RTL frame 512 and
  `GAMEPLAY` at frame 515), but the frame-580 image still contains only the
  card labels/starfield: the K053246/K053247 character artwork is absent.
- A MAME Lua probe at frame 580 confirmed valid source entries in the Bucky
  `0x090000` sprite window (slots `0x50`-`0x6d`, with the first eight words of
  each `0x80`-word slot populated). The RTL object diagnostic confirmed that
  the CPU address presented to `bucky_video` is already relative to this
  window (`0x8000` at the physical `0x090000` base).
- The compacting expression used the wrong slot slice, `[15:8]`; for source
  slot `0x50` this generated compact address `0x140`, while the K053247 RAM
  requires `0x280` (`slot * 8`). The expression is corrected to use
  `[14:7]` while retaining the documented active-word gate `[6:3]==0`.
- A strict fx68k Verilator rebuild succeeds after this RTL fix. The required
  gameplay-length regression is still pending because this full visible-SDL
  bench advances at roughly 0.5 frames/second; no hardware/RBF claim is made.

## Pre-RBF RTL cleanup - 2026-08-10

- Removed the JTFRAME test/debug OSD controls and tied all production debug
  buses away from functional paths. The release no longer permits debug-bus
  audio gain changes or exposes the diagnostic status overlay.
- Removed the rejected K053247 draw-stage X-culling scaffold. Disabled the
  scan-stage X-culling experiment because its own required broad scene matrix
  was never completed; release RTL keeps the established full sprite traversal.
- Removed the unity-default FM/PCM debug gain stages. This eliminates four
  variable audio multipliers while leaving the normal gain-8 divided-by-8
  output numerically identical. JTFRAME rcmix remains the fixed balance owner.
- Guarded K053251 writes to its physical 0-12 register range, and removed
  generated trace, config and NVRAM artifacts from the tracked source set.
- Parent-only source/MRA/JTFRAME/Yosys pre-hardware audit passes. No Verilator,
  Quartus, RBF generation or hardware test was run during this cleanup. The
  gameplay-length sprite-source regression remains the functional release gate.

## Safe throughput and video-control pass - 2026-08-11

- Retained the measured production throughput path: 64-bit sprite line caching,
  64-word SDRAM bursts on BA0..BA3, tile producer/consumer overlap, registered
  tile line buffers and the compact GX173 sprite-source mirror. No speculative
  scan culling, skid FIFO, audio-table retiming or SDRAM precharge change was
  enabled without a focused gameplay/audio proof.
- Documented the existing JTFRAME Scale menu names: Normal, V-Integer,
  Narrower HV-Integer and Wider HV-Integer. All six Bucky MRAs retain the
  correct game controls (`Shoot,Jump,Special`) plus Start/Coin/Core credits;
  the MRA validator passes.
- Validation completed: static RTL/source closure, six-MRA convention checks,
  and standalone SystemVerilog syntax checks.
  No Verilator, Quartus, RBF generation or MiSTer hardware test was run for this
  source-only pass.

## Gameplay-transition first divergence - 2026-08-11

- Locked scenario: MAME 0.289 parent `bucky`, default DIPs, coin held on
  frames 470-489 and P1 Start held on frames 510-529. The exact Verilator
  replay reaches the same Start-input reads (`$0da000=$ff7f`) and performs the
  same initial player-record setup at frame 511.
- The earliest confirmed data divergence is the byte write at PC `$004566`.
  MAME writes `$02` to the low byte of work-RAM word `$080944`; Verilator
  writes `$00`. Disassembly proves this instruction copies global byte
  `$080062` to player byte `$45(a0)`. The later missing object-selection block
  is downstream: Verilator consequently reads `$080944=$0200` at PC `$003b2e`
  where MAME reads `$0202` at PC `$003b2c` and then selects object `$091420`.
- Do not patch the object renderer or force the player byte. The next causal
  probe must find why `$080062` is `00` in RTL versus `02` in MAME and repair
  its producer. `sim_savable.cpp` now includes host-side visibility for
  `$080050-$080069` without changing serialized RTL state.
- Preserved exact checkpoints:
  `.workbench/gameplay-exact/bucky-start-transition.vltsv` at frame 510 and
  `.workbench/gameplay-exact/bucky-fullschedule-preinput.vltsv` at frame 450.
  Evidence is in `.workbench/gameplay-exact/host-bus.log` and
  `mame-player-input517-a/player-watch.log`. Both completed RTL frame-517 runs
  have explicit testbench PASS markers; this proves deterministic execution,
  not gameplay/frame equivalence.
- The diagnostic-only rebuild requested after extending the host probe was
  stopped before completion at the user's request. No speculative RTL fix,
  Quartus build, RBF generation, or hardware claim was made.
