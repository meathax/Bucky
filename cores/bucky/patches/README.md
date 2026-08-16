# JTFRAME framework patches

Local modifications this core requires from the vendored JTFRAME tree. The
JTFRAME checkout lives under the ignored `.workbench/upstream/jtcores/`, so
these edits are not covered by this repository's history and are lost whenever
that tree is re-cloned or reset. Keep them here so a rebuild is reproducible.

Pinned base: jtcores `1cc4df025554f449b954ecd11c3e3442bb22f8f3` (see `SOURCES.md`).

## `jtframe-service-test-buttons.diff`

Applies to `.workbench/upstream/jtcores/`:

    git -C .workbench/upstream/jtcores apply --check \
        ../../../cores/bucky/patches/jtframe-service-test-buttons.diff
    git -C .workbench/upstream/jtcores apply \
        ../../../cores/bucky/patches/jtframe-service-test-buttons.diff

Contents:

- `modules/jtframe/hdl/keyboard/jtframe_inputs.v` — adds `SERVICE_BIT` and
  `TEST_BIT` (the two free slots after `PAUSE_BIT` on the 16-bit `board_joy*`
  word) and the `joy_service` register, so the MRA `<buttons>` list can map
  physical Service and Test buttons. GX173 hardware has both as real cabinet
  buttons (`moo.cpp`).
- `modules/jtframe/hdl/keyboard/jtframe_joysticks.v` — threads `joy_service`
  through `jtframe_joysticks` into `jtframe_merge_keyjoy`, where
  `game_service <= ~(key_service | joy_service)`. Without the port additions the
  design does not synthesise: Quartus reports
  `Error (10052): ... can't find port "joy_service"`.
- `modules/jtframe/target/mister/cfgstr` — guards the Vertical Crop / Crop
  Offset OSD entries behind `JTFRAME_NOCROP`. Bucky no longer defines that macro
  (see `cores/bucky/cfg/macros.def`), so this renders identically to upstream
  here; it is retained only to keep the option available to other cores.

Note that the OSD "Service mode" toggle also needs `JTFRAME_OSD_TEST`, which is
set in `cores/bucky/cfg/macros.def` and reaches Quartus through the generated
`cores/bucky/mister/bucky.qsf` macro block. That block is generated separately
from `files.qip`/`cfgstr.hex` and has gone stale before — see
`cores/bucky/tools/check_qsf_macros.ps1`.

The release MRA maps the two positional entries to virtual `L` (Service) and
`R` (Test). JTframe's MRA generator intentionally emits `-` for these slots and
Main_MiSTer's mapper does not assign a signal for an unmapped default, so this
MRA default mapping is required for physical gamepad buttons; keyboard `9` and
`F2` continue to use JTframe's dedicated Service/Test decoder path.
