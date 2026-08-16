# Bucky O'Hare source and evidence ledger

Evidence is ranked in this order: physical PCB/captures, PCB schematics and silicon reconstruction,
MAME 0.289 source/observations, existing FPGA implementations, then inference. MAME is not treated as
hardware truth where its driver is marked imperfect.

| Source | Pinned identity | License / distribution | Use |
|---|---|---|---|
| Konami Bucky O'Hare manual, GX173 / PWB353126 | SHA-256 `8EA950CF65103497ED28ACD8838281303A3E0C1E10844A451EDCA0724F7AFDF5` | Original documentation; not redistributed | Board wiring, clocks, reset, buses, video, audio and I/O |
| Furrtek SiliconRE `Konami/054000` and `Konami/054338` | `bf17e0275f06df1c78f3cdcba770f0cc6cce6397` | GPL-2.0; exact mirror kept only in `.workbench/upstream` | Silicon schematics, traces, pinouts and standalone behavioral oracle |
| MAME source | local `D:\Arcade\AI\mame289`, MAME 0.289 | BSD-3-Clause | Address maps, ROM definitions and observable device contracts |
| MAME executable | SHA-256 `AF6966108D9B52C22465C6D50F4E5D50CC371B50F2D27DC443935F287AAD37A3` | Local reference executable | Deterministic reference runs through MAME MCP |
| jtcores | `1cc4df025554f449b954ecd11c3e3442bb22f8f3` | Per-source GPL-compatible notices retained | JTFRAME, fx68k, Z80, JT51 and MiSTer build framework |
| Template_MiSTer | `b4726d2dd8cfad67db3f8ba060aa4e8c13047662` | Upstream notices retained | Official standalone MiSTer packaging reference |
| Existing Moo Mesa core | [`jlrh/konami-fpga`](https://github.com/jlrh/konami-fpga), pinned [`cores/moomesa`](https://github.com/jlrh/konami-fpga/tree/5e890383/cores/moomesa), commit `5e890383` | GPLv3 | GX151/GX173-family CPU, video, sound, SDRAM and I/O donor; the required common RTL was adapted into the independent Bucky source tree with GX173-specific map and color/timing changes |
| Bucky ROM archive | SHA-256 `D9EAB6109959A7A77E83871EA775954D10F0A607FA320B81D75713DC12F38987` | Private; never committed or redistributed | Local validation of the six MAME sets |

The complete pinned evidence is kept under ignored `.workbench/upstream/`. No SiliconRE HDL is linked
into the GPLv3 production core unless its licensing is confirmed compatible. K054000 production RTL is
an independent behavioral implementation. K054338 has no upstream HDL; its RTL is derived from the
published reconstructed schematic, pinout and behavioral description.

## K054338 schematic mapping

The complete eight-page SiliconRE schematic was rendered; its layout-preserved labels and vector annotations were inspected by functional page: sequencing (1),
data bus/arbitration (2), register latches (3), control/input-delay selection (4), red/green/blue
multiply-add and signed shadow paths (5-7), and independent brightness output (8). Production RTL
keeps brightness as a distinct chip output and performs its analog DAC gain digitally only in the
MiSTer-facing color wrapper.
