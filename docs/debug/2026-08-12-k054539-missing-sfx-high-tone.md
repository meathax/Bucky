# K054539 missing effects and intermittent high tone

## Symptom

The affected MiSTer setup plays background music and the player's shooting
sound, but most other effects are absent.  An intermittent high-pitched tone
also appears during play.  The first reported RBF was
`Arcade-Bucky_20260812.rbf`, 3,756,204 bytes, SHA-256
`b4cc50b287c0dda7da6b5ee9d756109395446bdf04681e386fb4f8a31a6ee14f`.
A fresh post-RTL-fix RBF, SHA-256
`23bf8b4abc3322363f5198cccbc592a94d8e81d88b55dbef60eda0d7948530cd`,
reproduced the same dominant missing-sound symptom.  That hardware result
rejects the earlier assumption that the K054539 RTL corrections alone closed
the release failure.

Focused strict RTL tests still close three independently reproduced K054539
defects.  The complete component suite and duplicate parent runs pass, but the
parent harness preloads PCM directly and therefore masked the real
hardware-only download-layout failure described next.

## Hardware retest and true release root cause

The installed MRA places PCM at stream byte `0xC80000`, exactly at header
boundary 4.  The generated non-XL target instantiates `jtframe_dwnld` with
`BALUT_LEN=5`.  In that configuration entries 0-3 are SDRAM bank starts and
entry 4 is **PROM start**.  Every PCM byte therefore asserted `prom_we` while
`prog_we` was suppressed.  Bucky has no PCM consumer on `prom_we`, yet runtime
K054539 reads target SDRAM bank 1 at local byte offset `0x40000`.  The complete
4 MiB sample region was never written where the core reads it.

The old stream was:

```text
bank 0  maincpu   0x000000-0x23ffff
bank 1  soundcpu  0x240000-0x27ffff
bank 2  tiles     0x280000-0x47ffff
bank 3  objects   0x480000-0xc7ffff
PROM    PCM       0xc80000-0x107ffff  <- wrong
```

This explains both the breadth and hardware-only nature of the symptom.  The
YM2151 can still produce music/tone content, while K054539 voices read
unwritten or stale SDRAM.  The missing PCM is **KNOWN** from downloader logic
and exact installed-MRA bytes; attribution of the intermittent high tone to
the stale PCM contents remains **INFERRED** until the corrected MRA is heard
on hardware.

The parent Verilator harness did not traverse `jtframe_dwnld` or the MRA.  It
loaded `pcm.hex` into a private array and fabricated bank-1 responses at the
runtime offset, so all prior K054539 tests could pass while the hardware ROM
download remained broken.

## Minimal release fix

No RTL or RBF change is required for this causal error.  The MRA generator now
orders regions `maincpu,soundcpu,pcm,k056832,obj,eeprom` and emits bank/PROM
boundaries:

```text
00 00 40 02 80 06 80 08 80 10
```

PCM starts at stream `0x280000`, which is bank-1 local byte offset `0x40000`
and exactly matches `PCM_OFFSET=0x20000` SDRAM words.  Tiles and objects begin
at `0x680000` and `0x880000`; EEPROM remains at `0x1080000` and now correctly
owns PROM start.

The old installed MRA is SHA-256
`0f58f825b29a5689833612ef0a17962621653a7d524cb1e4f9fc402472e47500`.
The corrected release MRA is SHA-256
`6f7b36b6ff00c9cbcdcc3bcc4c3dbd126346e01b211890a257473074f75332ce`.

`validate_mra.py` fails the old header/order and passes the corrected release.
`tb_bucky_download_layout` drives the real `jtframe_dwnld` implementation and
proves PCM offsets `0`, `0x1fffff`, `0x200000` and `0x3fffff` all reach SDRAM
bank 1 with the correct word address/lane.  It also proves tile, object and
EEPROM starts route to bank 2, bank 3 and PROM respectively.  The complete
strict audio component suite and source/provenance gate pass with this new
regression.

## Scenario and first divergence

The boot write-stream comparison was deterministic on both sides.  MAME and
RTL match exactly through K054539 write ordinal 33.  At ordinal 34 MAME writes
`0x22f=0x90`; RTL first executes the sound program's eight-write key-off loop
to `0x215` (`01,02,04,08,10,20,40,80`) and then writes `0x22f=0x90`.

That difference is an expected-reference exception, not the missing-effects
defect.  RTL instrumentation traces the loop to command `0x00` dispatched by
the YM2151 NMI before the sound-program POST.  The PCB path is YM2151 `/IRQ`
through the documented inverter/74LS74 network to Z80 NMI; the MAME `moo`
driver does not install the corresponding YM IRQ callback.  Disconnecting the
RTL NMI would discard PCB-supported behaviour and was therefore rejected.

After binding that exception, three focused hardware contracts expose the
first causal RTL error in their own domains:

1. Reverb RMW: the first channel read uses the previous delayed-write address,
   reading `0x1111` instead of the selected slot's `0x2222`.
2. Voice replacement: an old voice's `S_MIX` or EOF action wins over a queued
   key-on and destroys the replacement start/active state.
3. CPU write phase: one Z80 write held across multiple 48 MHz clocks executes
   release-triggered side effects multiple times instead of once at `/WR`
   release.

## Evidence identities

- RTL base: Git `d3aafad7a0bdfa9552f82536234c167300408b34`.
- Fixed `cores/bucky/hdl/k054539.v` SHA-256
  `ebdfd6b0af36c9fc20027a59b156dd0db5f13d9f1deb83ff88468bfb8b99d825`.
- MAME: 0.289 executable SHA-256
  `af6966108d9b52c22465c6d50f4e5d50cc371b50f2d27dc443935f287aad37a3`.
- Parent ROM archive SHA-256
  `d9eab6109959a7a77e83871ea775954d10f0a607fa320b81d75713dc12f38987`.
- Parent ROM mapping: `.workbench/parent-rom/parent-rom.json`.
- PCM image SHA-256 begins `3b0cd91b`; the complete value remains in the
  parent-ROM manifest/run evidence.
- Duplicate MAME gameplay K054539 logs: 49,919 events each, common SHA-256
  `a6d39d1f8fbe497bda673e068a4e03ed16081a27e1ba42242d3ae1be5eb7b468`.
- Duplicate RTL boot K054539 logs: 8,297 events each, common SHA-256
  `8dc9d626aae0138e8f271c0274235b2904ce26f028ddb9b17127eb4e0db2fe36`.
- Verilator 5.050 strict, headless tests use runtime `--threads 1`; individual
  commands, source-closure fingerprints and logs are preserved by each task
  receipt under `.mister/runs/`.
- Final strict parent build receipt
  `task-verilator_build-20260812T054440913702Z`; binary SHA-256
  `ce086b8d65bc59f48d75ed033f4f10107c78d8ff8116c4715b82218ef430c22c`.

Copyrighted ROM contents are not tracked by this repository.

## Causal chain

### Reverb corruption and the high tone

The BRAM conversion connected audio port 1 to `rr_addr`, but `rr_addr` is the
registered address of a delayed write.  During `S_MIX`/`S_RVWR`, the read side
therefore returned a stale slot and fed that unrelated word into the reverb
read-modify-write.  Repeated stale-word feedback can create the reported
intermittent high-pitched tone and corrupt the wet mix.

The corrected contract holds `widx` as the synchronous read address through
both `S_MIX` and `S_RVWR`, then selects `rr_addr` only while the delayed write
is actually enabled.  The focused test also proves feedback-slot clear,
non-zero contribution, correct target update and no overwrite of the stale
source slot under sparse K054539 clock enables.

### Replacement voices and missing effects

Bucky rapidly keys off, updates and rekeys the same K054539 channels for event
effects.  The FPGA implementation serializes eight voices through one FSM, so
CPU writes can arrive while an old instance of that channel is still in
flight.

- `S_MIX` mirrored the old `w_pos` into registers `0x0c..0x0e` after a new
  UPDATE_AT_KEYON position had committed.  The next `S_LOAD` then restarted
  from the old/end address.
- The 8-bit, 16-bit and DPCM EOF paths cleared `active[ch]` even when an
  earlier key-on had already armed `restart[ch]`.  The replacement was left
  inactive and could never reach the `S_LOAD` that consumes its restart.

The correction gives a pending or same-edge key-on priority over both retiring
actions.  Normal live-position mirroring and normal EOF retirement are retained
when no replacement is queued.

### Hybrid CPU write phase and multiplicity

The original register process treated `cs && we` as a new transaction on every
48 MHz master-clock edge.  A Z80 bus write can remain asserted for several of
those clocks.  Decapped K054539 evidence distinguishes transparent fields from
release-captured side effects:

- ordinary register data, global-control D7 and odd-control D2/D4/D5 are
  transparent while the decoded write strobe is active;
- key-on, data-port write/pointer increment, global-control D0/D1/D4/D5 and
  odd-control loop-enable D0 capture once on the rising edge of their decoded
  active-low write strobe;
- key-off remains level-visible while its strobe is active and must not be
  repeated on release.

The RTL now retains the stable address/data of an active write and emits one
`cpu_write_commit` when `/WR` is released.  Each field or side effect is routed
to its physical transparent, level or release phase.  This prevents held
key-on writes from continually rearming `restart`, and prevents held `0x22d`
writes from corrupting several RAM bytes while advancing the pointer several
times.  The first fresh parent run records 8,297 accepted K054539 write spans:
every span lasts exactly six raw 48 MHz clocks with stable address/data, and
one span overlaps `S_LOAD`.  This proves both that the multiplicity risk occurs
on the real parent bus and that a held write can overlap live sequencer work,
the condition exercised more specifically by the focused release test.

## Rejected hypothesis: dropped sample-ROM request

Source inspection initially made the one-cycle `sample_rom_cs` pulse look
unsafe for SDRAM latency.  The real generated wrapper gates `cen_pcm` whenever
`pcm_cs && !pcm_ok`; while the request is outstanding the K054539 FSM cannot
execute the branch that clears chip select, so chip select and address remain
stable.  `tb_bucky_k054539_gated_rom` holds a 20-master-clock response and
passes (`task-audio_component_regression-20260812T050304111570Z`).  No held-CS
functional change was made.

## Earlier K054539 RTL fixes

All functional corrections are confined to `cores/bucky/hdl/k054539.v`:

- select `widx` for the complete synchronous reverb read and `rr_addr` only
  for an enabled write;
- protect live-position mirroring and all three EOF formats while a restart is
  pending or commits on the same edge;
- model the K054539's hybrid transparent/level/release CPU-write phases and
  commit release-triggered operations exactly once.

Those earlier functional RTL corrections did not change YM NMI, mixer, clock,
reset, MiSTer framework, PLL, constraint or top-level I/O paths.  The separate
release correction above changes MRA stream ordering, not RTL ROM addressing.

## Regression

Focused pre-fix failures and post-fix closures are immutable in these receipts:

| Contract | Pre-fix evidence | Post-fix evidence |
|---|---|---|
| Reverb RMW | `task-audio_component_regression-20260812T050745372182Z`: stale `1111`, expected `2222` | `task-audio_component_regression-20260812T051132865429Z`: target 5 becomes `2a22`; deadline test also passes |
| Key-on versus `S_MIX` | `task-audio_component_regression-20260812T051607589018Z`: old `012345` overwrites new `789abc` | `task-audio_component_regression-20260812T051739556080Z`: same-edge, queued and ordinary mirror cases pass |
| Key-on versus EOF | `task-audio_component_regression-20260812T052238441604Z`: queued restart left `active=0` | `task-audio_component_regression-20260812T052410545297Z`: 8-bit, 16-bit and DPCM EOF cases pass and next `S_LOAD` consumes the new start |
| CPU write release/multiplicity | `task-audio_component_regression-20260812T053045963224Z`: six phase/multiplicity failures | `task-audio_component_regression-20260812T054201791826Z` and `...054350726160Z`: duplicate strict passes, pointer 1 and position `789abc` |

The two latest focused runs also pass the base K054539 test, gated-ROM request,
reverb RMW, key-on collision tests and exact 384-enable sample deadline with a
20-clock ROM response.  The final AudioOnly receipt
`task-audio_component_regression-20260812T054350726160Z` passes with fingerprint
`969bb350...`.  The complete component receipt
`task-audio_component_regression-20260812T054431118208Z` passes with fingerprint
`63b39eab...`.

The fresh strict parent build passes, then
`task-audio_boot_capture-20260812T054514934181Z` reaches its declared 35-frame
stop after 27,574,289 cycles with zero PCM deadline misses (fingerprint
`342c2c85...`).  Its 8,297-event K054539 write log retains SHA-256
`8dc9d626...fe36`; context SHA-256 is `524379...a3a7f` and write-span SHA-256 is
`b0fa7...1b452`.

Independent receipt `task-audio_boot_capture-20260812T054826223124Z`
(fingerprint `abd4fb39...`) reaches the same 35-frame / 27,574,289-cycle stop
with zero PCM misses.  Its K054539 write, context and span artifacts are
byte-identical to the first run; its common latch SHA-256 is `32f7...2e91`.
The strict prefix checker passes with `matched_prefix=34`, `last_match=33`
against pinned MAME log SHA-256 `a6d39d1...b468`, followed only by the reviewed
PCB-supported YM-NMI expected-reference insertion.  Same-side determinism and
the declared parent cold gate are closed.

## How to recognize this pattern again

- A periodic or intermittent tonal artifact after converting a delay line to
  synchronous BRAM should trigger an audit of read-address residency across
  every wait/RMW state, not only the state that launches the read.
- If some effects survive but rapid channel reuse loses most events, observe
  key-on, `restart`, `active`, `S_LOAD`, EOF and live-position mirror priority
  on the same raw master-clock timeline.
- Never infer one CPU transaction per FPGA clock from a level bus strobe.  Map
  each decapped field to its transparent, assertion or release phase and test a
  held bus cycle across an in-flight audio state.

## Remaining uncertainty

- The corrected MRA has not yet been replayed on MiSTer.  The existing fresh
  RBF can be reused; only a relaunch through the corrected MRA is required to
  confirm all effects are audible and the high tone is absent.
- Exact digital-audio equivalence through a complete gameplay interval is not
  yet captured; focused device contracts close the proven causes but do not
  substitute for that longer waveform comparison.
- No Quartus compilation or RBF build was run during this correction.
