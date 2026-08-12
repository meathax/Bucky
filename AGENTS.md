<!-- MISTER-FPGA-AUTOPILOT-V4:START -->
# MiSTer FPGA autonomous engineering contract

This repository is operated through the installed `$mister` skill and `tools/mister.*` executor. These v4 rules supersede older MiSTer Autopilot instruction blocks and `fpga.py` workflows in this repository.

## Ownership

Codex owns inspection, setup, source research, donor analysis, builds, simulation, capture,
normalization, comparison, diagnosis, bounded RTL correction, regression and Quartus verification.
Do not hand routine commands back to the user. Ask for user action only when physical hardware,
a missing ROM owned by the user, credentials, or inaccessible evidence makes it unavoidable.

## Hardware truth and evidence

Rank evidence as:

1. Original schematics, manuals, measurements, decaps and verified PCB observations.
2. MAME source plus deterministic MAME runtime evidence.
3. Open-source implementations of the identical device or board revision.
4. Related hardware and other emulators as hypotheses.

MAME is the behavioral software oracle for configured comparisons. It is not automatically a
nanosecond-perfect description of the physical PCB. Label claims as KNOWN, INFERRED or HYPOTHESIS.

## Differential debugging

Always:

1. prove independent same-side determinism;
2. validate the observability contract;
3. compare canonical domain-local events;
4. find the first meaningful divergence;
5. trace backward to the first causal producer;
6. apply one smallest synthesizable correction;
7. add a focused regression;
8. replay the exact case and then cold-run from reset;
9. continue to the next earliest divergence.

Never accept screenshot similarity, a shifted/resynchronized trace, omitted fields, missing-as-zero,
or a later symptom as proof. Do not create a huge waveform until coarse traces localize a narrow
window.

## RTL rules

Preserve hardware architecture unless evidence justifies a change. Prefer clock enables over fabric
clocks. Audit reset, initialization, width, signedness, byte lanes, masks, bus phase, wait/ack,
interrupt acknowledgement, DMA ownership, memory latency and cross-clock crossings before inventing
game-specific patches. One functional writer at a time.

## Quartus rules

Use Quartus 17.0.2-compatible constructs and flows for this project. Run lint/focused simulation
frequently, Analysis & Synthesis at subsystem milestones, and a full fit/timing pass at integration
or release milestones. Never hide a real timing or CDC failure with false paths, multicycle paths,
relaxed periods or clock-group exceptions unless the physical architecture proves the exception.

## Donor-core reuse

Before copying or adapting donor HDL, record repository URL, immutable commit, license, notices,
files reused and whether code is copied, adapted or reimplemented. Preserve attribution and reject
unclear license provenance. Similar board families are not assumed behaviorally identical.

## Durable records

Keep these current:

- `docs/HARDWARE.md`
- `docs/OBSERVABILITY.md` and `docs/OBSERVABILITY.json`
- `docs/VERIFICATION.md`
- `docs/PROVENANCE.md` and `docs/PROVENANCE.json`
- `docs/STATUS.md`
- solved divergences under `docs/debug/`

Treat `.mister/state.json` and run manifests as machine state. Do not edit generated evidence to make
tests pass.
<!-- MISTER-FPGA-AUTOPILOT-V4:END -->
