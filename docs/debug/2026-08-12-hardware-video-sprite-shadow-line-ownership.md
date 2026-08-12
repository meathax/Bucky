# Hardware video: sprite shadows and line ownership

## Evidence contract

- Source: `D:\Downloads\2026-08-12 09-23-07.mp4`
- SHA-256: `4218B378611591CBD28E8ACCCB14F2010717A4915597D43AC9F36BAEE646D421`
- Video: H.264, 1920x1080, 60 fps, 4.82 seconds
- Inspection: video-analyzer MCP uniform analysis plus 30 consecutive native
  frames from 0:00.70 through 0:01.40
- RTL base: Git `cf9a922e7ff2aaa20466010f2b8a05e509acdd14`

The footage is a camera capture of a display, not a direct native-frame dump.
The horizontal boundary that walks vertically between consecutive frames is
therefore diagnostic capture tearing.  Its motion is consistent with the beat
between a 60 fps camera and the core's configured approximately 59.1856 Hz
native cadence.  Video timing was not changed.

Two persistent sprite defects remain visible independently of that boundary:

1. Ship and character shadow sprites affect only a faint edge instead of the
   circular area beneath the object.
2. During the Stage 1 title sequence, opaque sprite data forms large central
   blocks and survives across line boundaries.

## First causal defects

### Shadow priority

Bucky programs K053251 shadow code 1 to priority 5 while ordinary background
content wins at priority 16.  K053251 priorities are numerically lower when in
front, so the shadow must pass when `PRSHA < winning_pri`.  The fork used the
opposite comparison.  The pre-fix focused test rejected the 5-over-16 shadow
and incorrectly admitted a 5-under-4 shadow; both cases now pass.

### Line-buffer ownership

The K053247 scanner restarts on HS even when the draw stage is finishing the
prior line.  The ping-pong buffer also flips at that boundary.  Without an
ownership guard, remaining opaque writes from the old tile target the next
producer bank.  Separately, shadow write controls are delayed one clock, but
their bank selector was not delayed, so an exact-boundary shadow write followed
the new selector and leaked into the following line.

The correction quarantines the old-line draw tail after HS and carries the
producer-bank epoch through the shadow RMW register.  It discards stale writes
instead of allowing them to alter the displayed or next-line bank.

## Verification

- `tb_bucky_k053251_shadow`: failed twice before the priority fix; PASS after.
- `tb_k053247_buffer_shadow_epoch`: reproduced one-line shadow leakage before;
  PASS after.
- `tb_k053247_late_line_guard`: PASS, including next-line recovery.
- Complete component suite: PASS.
- Fresh strict headless parent model:
  `6B52E420002415745D71D154A2BB5A78848E3F33FD13001FA5692F394857183D`.
- Cold parent replay: 60 frames, 47,849,489 clocks, zero PCM deadline misses,
  zero sprite-line overruns, no exception/assertion.

No Quartus compilation or RBF build was run.  Visual closure requires an
explicitly requested new RBF and a repeat capture of the same MiSTer sequence.
