# Building Bucky O'Hare for MiSTer

This repository contains the Bucky core source only. Game ROMs, generated
Quartus projects, simulator outputs and RBF files are deliberately excluded.

## Requirements

- A checkout of [jotego/jtcores](https://github.com/jotego/jtcores), including
  JTFRAME and its configured toolchain.
- Quartus Prime 17.0.2 Build 602 for the DE10-Nano target.
- PowerShell and Python 3 for the checked-in validation tools.
- Legally obtained Bucky O'Hare ROMs for local testing. ROMs are never copied
  into this repository or embedded in the RBF.

## Source validation

From this repository, run the source-only gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File cores/bucky/tools/pre_hardware_audit.ps1
```

This checks the production RTL closure, MRA conventions, memory definitions,
component regressions and the available parent-core evidence. It does not run
Quartus.

## JTFRAME generation

Copy or link `cores/bucky` into `cores/bucky` inside a configured jtcores
checkout, then generate the MiSTer target:

```sh
source setprj.sh
cd cores/bucky/mister
jtframe mem bucky --target=mister --local
jtframe mmr bucky
jtframe files syn bucky --target=mister --local
```

Before a full compile, verify the generated source closure:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File cores/bucky/tools/audit_rtl_placement.ps1 -StagedCore <path-to-jtcores>/cores/bucky
```

The generated QIP must contain the Bucky RTL and must not contain disconnected
experiments or another game's top level.

## RBF build

The release build uses the repository's `mister-rbf-build` workflow and Quartus
17.0.2. A fresh build must pass map, fit, timing and assembler gates, retain
compressed bitstream generation, and produce one hash-identical published RBF.

For the native jtcores flow, the equivalent compile entry point is:

```sh
cd <path-to-jtcores>
source setprj.sh
jtcore bucky -mister
```

Generated databases, reports and RBFs remain local or are published through the
release channel; they are not committed to this source repository.

## Legal notice

The source is distributed under GPLv3. The mathematical K054539 lookup tables
under `cores/bucky/hdl/` are synthesis inputs generated from formulas and do
not contain game data. Every game ROM and EEPROM image must be supplied by the
user at runtime through the MRA.
