# Bucky O'Hare — MiSTer FPGA Core

An FPGA recreation of Konami's 1992 **Bucky O'Hare** arcade hardware for the
MiSTer FPGA platform.

- **Target:** MiSTer / DE10-Nano with an SDRAM expansion
- **Original board:** Konami GX173, PWB353126
- **Display:** horizontal 384×224, 4:3, 15 kHz-class timing
- **Players:** one to four
- **Framework:** JTFRAME / jtcores
- **Repository policy:** source, configuration, tests and documentation only;
  no ROMs, generated Quartus databases or RBF files

The core boots and runs on real MiSTer hardware. The source includes the
hardware-verified sprite/shadow corrections and the K054539 active-voice
retrigger correction for event sound effects. Reproducible source-validation
and build details are in [BUILD.md](BUILD.md).

## Features in the OSD

| OSD feature | Options / function |
|---|---|
| Sound Output | Stereo or Mono |
| Coin Mechanism | Independent or Common |
| Number of Players | 2, 3 or 4 |
| Scale | Normal, V-Integer, narrower HV-Integer or wider HV-Integer |
| Controls | Four 8-way joysticks with Shoot, Jump and Special |
| Service / Test | MiSTer service input and the board's test-mode control |
| NVRAM | Save and restore the 128-byte serial EEPROM |

The OSD uses the standard MiSTer red-tinted palette rather than JTFRAME's grey
background override.

## PCB Accuracy

Only areas tied to original-board documentation or reconstructed chip evidence
are listed here. Simulation success alone is not treated as PCB evidence.

| Area | Implemented behavior | Qualifying evidence |
|---|---|---|
| GX173 board architecture | Main/sound CPU arrangement, clocks, ROM/RAM organization, custom-chip buses and cabinet I/O | Konami Bucky O'Hare GX173/PWB353126 operation and service documentation, pinned in [SOURCES.md](SOURCES.md) |
| K054000 | CPU-visible register/status device and GX173 byte-lane integration | SiliconRE K054000 reconstructed schematic, pinout and traces at the pinned revision in [SOURCES.md](SOURCES.md) |
| K054338 | Mix selection, background selection, signed shadow/highlight tables, clamp behavior and independent brightness output | Eight-page SiliconRE K054338 reconstructed schematic and pin documentation, mapped in [SOURCES.md](SOURCES.md) |

## Supported games

The source configuration supports all six Bucky O'Hare revisions in MAME's
`bucky` machine family:

| Game / revision | MAME set |
|---|---|
| Bucky O'Hare (ver EAB) | `bucky` |
| Bucky O'Hare (ver EA) | `buckyea` |
| Bucky O'Hare (ver JAA) | `buckyjaa` |
| Bucky O'Hare (ver UAB) | `buckyuab` |
| Bucky O'Hare (ver AAB) | `buckyaab` |
| Bucky O'Hare (ver AA) | `buckyaa` |

These are regional or program revisions of the same GX173 game.

## **Hardware emulated**

| Chip / subsystem | Clock or interface | Implementation / reference |
|---|---|---|
| Motorola 68000-compatible CPU | 16 MHz, 16-bit main bus | JTFRAME CPU integration with the GX173 address map, waits, IRQ4/IRQ5 and protection ownership |
| Z80-compatible sound CPU | 8 MHz, banked 8-bit ROM/RAM bus | T80/JTFRAME integration with the Bucky sound map |
| Yamaha YM2151 | 4 MHz FM interface | JT51 |
| Konami K054539 | 18.432 MHz input, fixed 48 kHz mix cadence | Bucky RTL supporting 8-bit PCM, 16-bit PCM, DPCM, pan, volume, reverse addressing, reverb, key-on/off and active-voice retrigger |
| Konami K054321-style interface | Main CPU ↔ sound CPU registers and interrupt signaling | Synthesizable Bucky sound-command path |
| Konami K056832 | 8 MHz pixel/tile timing and 32-bit tile-ROM path | GX173 tilemap, scrolling and ROM-readback RTL |
| Konami K053246 / K053247 | Object RAM, DMA, sprite-ROM fetch and line-buffered drawing | Bucky sprite engine with bounded line ownership, zoom and shadow attributes |
| Konami K053251 | Layer/sprite priority registers | Bucky priority and shadow-priority RTL |
| Konami K054338 | 24-bit color-math pipeline | Schematic-derived RTL with separate brightness output |
| Konami K054000 | 68000 register interface | Independent behavioral RTL based on reconstructed device evidence |
| Konami K053252 / CCU timing | 8 MHz raster timing | 512×264 total timing with 384×224 active output |
| GX173 protection blitter | Main-bus master, ROM-to-RAM transforms | Synthesizable behavioral implementation of the software-visible contract |
| ER5911-compatible EEPROM | Serial 128-byte nonvolatile store | JTFRAME serial EEPROM path with MiSTer save/restore support |
| Shared memory system | MiSTer SDRAM, banked/cached ROM traffic | JTFRAME memory generator with Bucky-specific main, sound, tile, sprite and PCM mappings |

## Credits

| Project / contributor | Contribution |
|---|---|
| Meathax and Bucky MiSTer contributors | GX173 integration, device RTL, debugging, hardware testing, packaging and maintenance |
| [Jose Tejada Gómez / Jotego](https://github.com/jotego/jtcores) and jtcores contributors | JTFRAME, CPU/audio building blocks and MiSTer infrastructure; upstream notices retained |
| Rafael Eduardo Paiva Feener and Miki Saito | Contributions credited by the inherited Konami video/sprite sources |
| [jlrh/konami-fpga](https://github.com/jlrh/konami-fpga) Moo Mesa core contributors | GPLv3 GX151/GX173-family donor architecture, specifically the pinned [`cores/moomesa`](https://github.com/jlrh/konami-fpga/tree/5e890383/cores/moomesa) tree, adapted into the independent Bucky source tree |
| [MAME](https://github.com/mamedev/mame) contributors | `moo.cpp`, K054539 behavior and observable software contracts used as a reference model |
| Furrtek and SiliconRE contributors | Reconstructed Konami K054000/K054338 schematics, traces and pin documentation |
| [MiSTer-devel Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer) contributors | Official MiSTer project, framework and packaging conventions |
| Sorgelig and the MiSTer community | MiSTer platform, Main, documentation and preservation ecosystem |
| OpenAI Codex | Tool-assisted RTL analysis, regression development and documentation under maintainer review |
| Konami | Original Bucky O'Hare game and GX173 hardware |

Pinned provenance and licensing details are recorded in
[SOURCES.md](SOURCES.md). Copyright and license notices from adapted sources
are retained in their source files.

## License

The Bucky core source is distributed under the **GNU General Public License
v3.0**; see [LICENSE](LICENSE).

Adapted JTFRAME/jtcores and donor modules retain their original GPL-compatible
notices. MAME and SiliconRE are reference/evidence sources with their own
licenses and are not copied wholesale into the production RTL. Review the
header of each adapted file and [SOURCES.md](SOURCES.md) for details.

Copyrighted game ROMs, EEPROM dumps and other proprietary game assets are not
included. Supply only ROMs you are legally entitled to use.

## How to install

This source repository intentionally does not contain an RBF.

For manual installation:

1. Obtain or build the current `Arcade-Bucky_YYYYMMDD.rbf`.
2. Place the RBF in `/media/fat/_Arcade/` and place the Bucky `.mra` files in
   the same `_Arcade` folder. An equivalent organized layout, such as an RBF
   under `/media/fat/_Arcade/cores/`, is also supported when the MRA resolves it.
3. Put legally obtained matching MAME ROM ZIPs in `/media/fat/games/mame/`.
4. Launch the desired Bucky O'Hare revision from MiSTer's Arcade menu.

For automatic installation, add this entry to `downloader.ini`:

```ini
[meathax/meatcores]
db_url = https://raw.githubusercontent.com/meathax/meatcores/db/downloader_meathax_meatcores.zip
```

Then run **Update All** on MiSTer. The downloader installs the published core
and MRA files; game ROMs remain user-supplied.
