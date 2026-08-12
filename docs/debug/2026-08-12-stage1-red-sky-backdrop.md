# Stage 1 red-sky backdrop investigation

## Reported symptom

- Source video: `D:\Downloads\2026-08-12 11-33-27.mp4`
- SHA-256: `81556bdf1846898ec3d78f103ed972e9b48ce23474ceda159a1548a9f80d9619`
- The sky becomes a flat dark red for several frames near the middle of the
  3.87-second recording.
- Opaque mountains, ground, sprites, and HUD glyphs remain intact. The red is
  visible only where the composited layers are transparent, including behind
  the HUD. This fingerprints the K054338 solid backdrop rather than tile ROM,
  tile RAM, sprite RAM, palette corruption, or an SDRAM fetch miss.

## Resolution

This is expected game behaviour for the EAB revision, not an RTL fault.

The shipped MRA selects `Bucky O'Hare (ver EAB)`. Regional comparison material
at <https://gaminghell.co.uk/BuckyOHare.html> explicitly identifies an occasional red
sky flash as one of the Stage 1 background details added to the non-US
revisions. The same comparison identifies EAB as the World revision used for
the comparison.

MAME 0.289 independently models the effect through the normal K054338 path:

- `moo.cpp` maps `0x0ca000..0x0ca01f` to K054338 register writes and calls
  `fill_solid_bg()` before drawing the opaque layers.
- `k054338.cpp` constructs the solid RGB backdrop from register 0's low byte
  and register 1's two bytes.
- `bucky_colmix.v` decodes the same CPU writes and constructs `bg_bgr` from
  the same three bytes. The final compositor selects that value only for
  transparent/background pixels.

Removing or filtering the red writes would be a revision-specific visual hack
and would regress the EAB game's intended presentation. No functional RTL
change is justified.

## Reproduction probe

`cores/bucky/tools/diff/mame_backdrop_probe.lua` installs a read-only tap over
the K054338 backdrop registers, replays the pinned gameplay input journal, and
records every RGB transition with frame, PC, address, data, and byte mask. It
also captures a bounded set of frames following each in-game transition.

`cores/bucky/tools/capture_mame_backdrop.ps1` pins the MAME and ROM hashes,
uses clean CFG/NVRAM/state directories, verifies the exact applied input
journal and stop barrier, and writes an evidence manifest.

## Release impact

- Functional RTL changes: none
- Quartus/RBF build: not run for this investigation
- Remaining risk: the recording is camera footage, so its exact displayed
  frame count is affected by capture cadence; that does not alter the source
  classification because the red state persists across several captured
  frames and follows the solid-backdrop compositing boundary.
