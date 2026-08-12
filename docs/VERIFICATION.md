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
| R002 | K054539 | Reverb BRAM readback lane/pointer corruption | `cores/bucky/tools/run_component_tests.ps1` | PASS |
| R003 | K054539 | 48 kHz update stretched by ROM latency/readback | Eight voices, 20-cycle ROM latency, exact 384-enable interval | PASS |
| R004 | sprite ROM | Two 32-bit row halves issue two SDRAM transactions | `tb_cowboys_lyro64`, byte-exact halves from one four-beat fill | PASS |
| R005 | parent integration | Cache geometry corrupts reset vector or misses audio/video deadlines | 60 cold frames, 47,849,489 clocks | PASS |
| R006 | K053251 shadow priority | Inverted comparator rejects ordinary ship/character shadows | `tb_bucky_k053251_shadow`, Bucky PRSHA 5 over priority 16 and blocked by priority 4 | PASS |
| R007 | sprite shadow buffer | One-cycle shadow RMW follows a bank flip and appears one line late | `tb_k053247_buffer_shadow_epoch`, settled write plus exact flip-edge write | PASS |
| R008 | sprite line ownership | Final tile from the prior line writes opaque pixels into the next producer bank | `tb_k053247_late_line_guard`, HS during active draw plus next-tile recovery | PASS |
| R009 | parent integration | Sprite fixes break full source closure, audio cadence or line deadlines | Fresh parent SHA-256 `6B52E420...7183D`, 60 cold frames / 47,849,489 clocks | PASS |

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

## Release scenarios

List scenarios explicitly in `.mister/project.json`. Absence of a configured release scenario is a block, not an implicit pass.
