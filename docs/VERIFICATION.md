# Verification plan

## Success definition

A scenario passes only when:

- reference and RTL identities are pinned;
- both sides are independently deterministic;
- every compared domain has a proven observability contract;
- strict normalized event streams match for the declared interval;
- configured output artifacts match under documented transforms;
- no earlier unresolved divergence is skipped;
- regressions pass;
- any required implementation/hardware gates pass.

## Scenarios

| Scenario | Start anchor | Stop anchor | Input file | Strict domains | Artifacts | Release gate |
|---|---|---|---|---|---|---|
| boot | reset_assert | first_fetch | scenarios/boot.input.jsonl |  |  | NO |
| attract | reset_assert | attract_checkpoint |  |  |  | NO |
| gameplay | named checkpoint | named checkpoint |  |  |  | NO |

## Milestone regressions

| ID | Subsystem | Failure protected against | Command/task | Status |
|---|---|---|---|---|
| R001 | reset/clock |  |  | NOT CONFIGURED |
| R002 | K054539 | Stale BRAM address corrupts reverb feedback/RMW and can produce a high tone | `tb_bucky_k054539_reverb_rmw`; pre `...050745372182Z`, post `...051132865429Z` | PASS |
| R003 | K054539 | 48 kHz update stretched by ROM latency/readback | Eight voices, 20-cycle ROM latency, exact 384-enable interval | PASS |
| R004 | sprite ROM | Two 32-bit row halves issue two SDRAM transactions | `tb_cowboys_lyro64`, byte-exact halves from one four-beat fill | PASS |
| R005 | parent integration | Cache geometry corrupts reset vector or misses audio/video deadlines | 60 cold frames, 47,849,489 clocks | PASS |
| R006 | K053251 shadow priority | Inverted comparator rejects ordinary ship/character shadows | `tb_bucky_k053251_shadow`, Bucky PRSHA 5 over priority 16 and blocked by priority 4 | PASS |
| R007 | sprite shadow buffer | One-cycle shadow RMW follows a bank flip and appears one line late | `tb_k053247_buffer_shadow_epoch`, settled write plus exact flip-edge write | PASS |
| R008 | sprite line ownership | Final tile from the prior line writes opaque pixels into the next producer bank | `tb_k053247_late_line_guard`, HS during active draw plus next-tile recovery | PASS |
| R009 | parent integration | Sprite fixes break full source closure, audio cadence or line deadlines | Fresh parent SHA-256 `6B52E420...7183D`, 60 cold frames / 47,849,489 clocks | PASS |
| R010 | K054539 voice replacement | Old `S_MIX` live position overwrites a same-edge or queued UPDATE_AT_KEYON start | `tb_bucky_k054539_keyon_mix_collision`; pre `...051607589018Z`, post `...051739556080Z` | PASS |
| R011 | K054539 voice replacement | Old 8-bit/16-bit/DPCM EOF clears `active` while a replacement restart is pending | `tb_bucky_k054539_keyon_eof_collision`; pre `...052238441604Z`, post `...052410545297Z` | PASS |
| R012 | K054539 CPU bus | Held Z80 write repeats release-triggered key-on, data-port and control side effects | `tb_bucky_k054539_write_release`; pre `...053045963224Z`, duplicate post `...054201791826Z` / `...054350726160Z` | PASS |
| R013 | K054539 ROM bus | SDRAM wait gating drops or changes a sample request before `rom_ok` | `tb_bucky_k054539_gated_rom`, 20 raw-clock response delay | PASS |
| R014 | complete component integration | Audio RTL changes regress another component contract | `task-audio_component_regression-20260812T054431118208Z`, fingerprint `63b39eab...` | PASS |
| R015 | fresh parent integration | Audio RTL changes break cold reset, determinism, source closure or aggregate deadlines | Strict binary SHA-256 `CE086B8D...30C22C`; cold receipts `...054514934181Z` / `...054826223124Z`, each 35 frames / 27,574,289 cycles with zero PCM misses and byte-identical audio evidence | PASS |

## Reset and initialization matrix

Test relevant combinations of:

- cold/power-on reset;
- warm/core reset;
- ROM download then reset;
- multiple seeds/initial values;
- short/long reset duration;
- independently phased clocks where appropriate.

A passing two-state simulation does not close reset/X-state risk by itself.

## Output artifacts

### Video

Define active crop, orientation, pixel format, frame/line range, border policy and hash method. Compare earliest differing frame, then line/region/pixel.

### Audio

Define sample rate, width, signedness, channel mapping, warm-up/latency alignment and comparison method. Prefer command/device-event checks before waveform correlation.

### State

Define exact memory/register regions, width/endian transform and capture phase.

## Quartus gates

| Gate | Requirement | Status |
|---|---|---|
| Analysis & Synthesis | configured and clean enough for policy | QUEUED FOR NEW INPUTS |
| Resource budget | within project limits | NOT RUN |
| Unconstrained paths | none unless justified | NOT RUN |
| Setup slack | meets configured threshold | NOT RUN |
| Hold slack | meets configured threshold | NOT RUN |
| Fresh RBF | full compile output verified | NOT RUN |

## Hardware gates

| Test | Build/revision | Procedure/input | Expected evidence | Status |
|---|---|---|---|---|
| cold boot | parent Verilator SHA-256 `8A54A575...F3A1B` | 60 cold frames, strict assertions | Final VBlank; zero PCM misses/zero post-reset sprite overruns | PASS |
| dense moving gameplay | fresh RBF pending | Known real-hardware stress scene with movement | Correct pitch; no cuts, ghosts or stale lines | PENDING |
| Stage 1 shadow/center artifact | source video SHA-256 `4218B378...6D421`; fixed RBF not built | Replay the same ship/character entrance and Stage 1 title | Full circular shadows; no opaque center block; camera tear assessed separately | PENDING |
| gameplay audio completeness | affected RBF SHA-256 `b4cc50b2...e14f`; fixed RBF not built | Replay rapid fire, enemy events, pickups/explosions and dense gameplay used in the report | BGM plus every expected effect; no intermittent high tone | PENDING |

The K054539 boot write-stream comparison carries one reviewed expected-reference
exception after matching ordinals 0-33: RTL executes the PCB-supported YM2151
IRQ/NMI key-off loop before `0x22f=0x90`, while MAME's `moo` driver omits the YM
IRQ callback.  This exception must not be hidden by disconnecting the RTL NMI.

## Release scenarios

List scenarios explicitly in `.mister/project.json`. Absence of a configured release scenario is a block, not an implicit pass.
