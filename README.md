# Bucky O'Hare — MiSTer FPGA Core

An independent MiSTer FPGA recreation of Konami's **Bucky O'Hare** arcade hardware.

## Core title and board

- **Core title:** Bucky O'Hare
- **Arcade hardware:** Konami **GX173 / PWB353126** PCB
- **Game:** Bucky O'Hare, Konami, 1992
- **Display:** horizontal, 384×224 active pixels, 4:3 aspect ratio, 15 kHz-class arcade timing
- **Players:** up to four
- **Framework:** JTFRAME / jtcores

This is a work-in-progress accuracy core. Focused device tests, ROM/MRA validation and parent boot
tests are in place. Full gameplay-length regression and real MiSTer hardware deployment remain open
validation gates.

## Features in the OSD

The Bucky O'Hare MRA exposes the following board configuration and control options:

| OSD feature | Options / function |
|---|---|
| Sound Output | Stereo or Mono |
| Coin Mechanism | Independent or Common |
| Number of Players | 2, 3 or 4 |
| Scale | Normal, V-Integer, Narrower HV-Integer, Wider HV-Integer (JTFRAME) |
| Controls | Four 8-way joysticks with Shoot, Jump and Special buttons |
| NVRAM | Save and restore the emulated 128-byte EEPROM through MiSTer settings |

## PCB Accuracy

The table below lists the parts of the GX173 implementation that follow the PCB documentation,
silicon reconstruction, MAME's documented device contract, or focused component tests. “Implemented”
does not mean that the complete game has already passed a hardware comparison.

| Area | PCB-aligned implementation | Evidence / status |
|---|---|---|
| Board map and ROM layout | GX173 address map, RAM windows, custom-chip windows, palette, data ROM and EEPROM | Implemented; six MAME 0.289 MRAs generated and checked |
| Main CPU | MC68000-compatible CPU path with GX173 bus decoding, wait states, IRQ4 and IRQ5 | Implemented; parent POST and directed gameplay milestones reached; long regression pending |
| Sound subsystem | Z80 sound CPU, banked sound ROM, main/sound latch and YM2151 interface | Implemented and exercised by parent boot tests |
| K054539 PCM | 8-bit PCM, 16-bit PCM, 4-bit DPCM, pan/volume, key-on/off, reverb, reverse playback and register readback | Focused component test passes; game-level audio regression remains pending |
| K056832 tile video | Tilemap VRAM, scrolling, tile ROM readback and GX173 timing geometry | Focused ROM-readback/component tests pass |
| K053246 / K053247 sprites | Sprite DMA, source RAM, scanning, zoom, shadow attributes and line-buffered drawing | PCB sprite-source behavior corrected; gameplay-length scene regression remains pending |
| K053251 priority | Layer and sprite priority selection with shadow-priority behavior | Implemented from the GX173 video path and silicon evidence; full-scene closure pending |
| K054338 color math | Mix selection, interpolation/addition, shadow/highlight paths, clamp control and brightness output | Derived from the reconstructed schematic; focused component test passes |
| K054000 device | Register/status behavior and GX173 byte-lane integration | Independent implementation; published 20-step register/status probe passes |
| Protection blitter | GX173 boot-time ROM/RAM blitter contract, including bus-master stalling | Implemented as a synthesizable HLE of the documented behavior; not a gate-level recreation |
| Timing and I/O | 8 MHz pixel timing, 384×224 raster, four-player inputs, DIP switches and active-low cabinet signals | Implemented from board/MAME evidence; hardware gate remains outstanding |

## Full list of games supported by the hardware

The core currently supports all six Bucky O'Hare revisions selected by the `bucky` MAME machine
configuration:

| Game / revision | MAME set name |
|---|---|
| Bucky O'Hare (ver EAB) | `bucky` |
| Bucky O'Hare (ver EA) | `buckyea` |
| Bucky O'Hare (ver JAA) | `buckyjaa` |
| Bucky O'Hare (ver UAB) | `buckyuab` |
| Bucky O'Hare (ver AAB) | `buckyaab` |
| Bucky O'Hare (ver AA) | `buckyaa` |

These are regional or revision variants of the same game, not separate games.

## **Hardware emulated**

| Hardware | Role |
|---|---|
| MC68000 | Main game CPU |
| Z80 | Sound CPU |
| YM2151 | FM sound generation |
| Konami K054539 | PCM sample playback and effects |
| Konami K054321-style sound interface | Main CPU ↔ sound CPU communication and sound control |
| Konami K056832 | Tilemap generation, scrolling and tile ROM access |
| Konami K053246 / K053247 | Sprite object RAM, DMA, scanning and drawing |
| Konami K053251 | Video layer/sprite priority and shadow-priority selection |
| Konami K054338 | Color mixing, alpha-style effects, shadow/highlight math and brightness |
| Konami K054000 | Collision/security register device |
| Konami K053252 / CCU timing | Pixel, raster and interrupt timing |
| GX173 protection blitter | Boot-time and runtime data transformation, modeled as HLE |
| Palette RAM, work RAM, tile RAM, sprite RAM and EEPROM | Board memory and persistent settings |

## Credits

| Credit | Contribution |
|---|---|
| Meathax / Bucky MiSTer contributors | Bucky-specific GX173 integration, address map, protection, device models, MRA packaging and validation work |
| Jose Tejada Gómez / Jotego | JTFRAME and jtcores framework, fx68k, Z80, JT51 and shared MiSTer build infrastructure |
| Rafael Eduardo Paiva Feener and Miki Saito | Credits retained from the inherited JTCORES video and sprite modules |
| [jlrh/konami-fpga Moo Mesa core](https://github.com/jlrh/konami-fpga/tree/5e890383/cores/moomesa) and its contributors | GX151/GX173-family CPU, video, sound, SDRAM and I/O baseline; common RTL adapted under its original GPLv3 notices |
| MAME project contributors | Hardware reference and software-visible contracts, especially `moo.cpp` and `k054539.cpp` |
| Furrtek / SiliconRE contributors | Reconstructed Konami silicon documentation, schematics, pinouts and behavioral evidence for the K054000, K054338 and K054539 |
| MiSTer Template contributors | Official standalone MiSTer packaging reference used by the project |
| MiSTer FPGA project, Sorgelig and the MiSTer community | FPGA platform, core framework, documentation and preservation ecosystem |
| Konami | Original GX173 hardware and Bucky O'Hare design |

The complete pinned source and evidence ledger is in [`SOURCES.md`](SOURCES.md). Upstream copyright
and license notices are retained in the relevant source files.

## License

The core source in this repository is released under the **GNU General Public License v3**; see
[`LICENSE`](LICENSE).

The repository also contains or references components with their own notices, including JTFRAME/jtcores
GPL notices, MAME's BSD-3-Clause reference source, and SiliconRE's GPL-2.0 documentation. SiliconRE
material is retained as evidence and is not linked into the production RTL. Check each source header
for its applicable terms.

Copyrighted game ROMs are not included. Use only ROMs that you are legally entitled to use.

## How to install

1. Obtain the matching `Bucky.rbf` and one or more Bucky O'Hare `.mra` files.
2. Copy the `.mra` files to `/_Arcade/` on the MiSTer SD card.
3. Copy `Bucky.rbf` to `/_Arcade/cores/`.
4. Place the legally obtained MAME ROM ZIPs in `/games/mame/`.
5. Launch the desired Bucky O'Hare revision from the MiSTer Arcade menu.

Alternatively, add this entry to `downloader.ini` and run **Update All** to get all of the Meathax
cores automatically:

```ini
[meathax/meatcores]
db_url = https://raw.githubusercontent.com/meathax/meatcores/db/downloader_meathax_meatcores.zip
```

The MRA files select the RBF and assemble the ROM stream at launch; the game ROMs are not baked into
the bitstream.
