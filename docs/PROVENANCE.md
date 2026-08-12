# Source and donor provenance

The machine record is `PROVENANCE.json`.

## Sources

| ID | Name | URL/local path | Revision/hash | Licence | Role |
|---|---|---|---|---|---|
| D001 | Existing Moo Mesa core | [jlrh/konami-fpga](https://github.com/jlrh/konami-fpga), [`cores/moomesa`](https://github.com/jlrh/konami-fpga/tree/5e890383/cores/moomesa) | `5e890383` | GPLv3 | GX151/GX173-family CPU, video, sound, SDRAM and I/O donor adapted into the independent Bucky source tree |

## Hardware compatibility matrix

| Function/chip | Target evidence | Donor implementation | Classification | Required work/test |
|---|---|---|---|---|
|  |  |  | UNKNOWN_EXPERIMENT_REQUIRED |  |

Classifications:

- `IDENTICAL_PROVEN`
- `STRUCTURALLY_SHARED_REVERIFY`
- `TARGET_ONLY`
- `DONOR_ONLY_REMOVE`
- `UNKNOWN_EXPERIMENT_REQUIRED`

## Imported files

| Donor ID | Upstream path | Local path | Upstream revision | Local changes | Attribution |
|---|---|---|---|---|---|
| D001 | `cores/moomesa` | `cores/bucky/hdl/` | `5e890383` | GX173-specific address map, color/timing behavior, device integration and verification changes | [jlrh/konami-fpga](https://github.com/jlrh/konami-fpga); GPLv3 notice retained in adapted source headers |

## Licence obligations

The Moo Mesa donor is credited in [README.md](../README.md) and [SOURCES.md](../SOURCES.md). Retain GPLv3 notices in adapted files and preserve source-availability and attribution obligations. The donor core directory itself is not redistributed; only the independently adapted Bucky source remains in this repository.

## Rejected donors

| Candidate | Reason rejected | Evidence |
|---|---|---|
|  |  |  |
