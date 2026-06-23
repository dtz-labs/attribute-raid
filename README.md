# Attribute Raid

Minimal ZX Spectrum 48K proof of concept for a River Raid style river
renderer.  It is still a renderer experiment: there is no shooting, score,
fuel, bridges, music, menu, or complete collision system.

## Build

```sh
make
```

The result is:

```text
build/attribute-raid.tap
```

`make clean` removes the build directory.

To launch the TAP in the local ZEsarUX app:

```sh
make run
```

To build and run the Timex Computer 2048 variant with Timex dual-screen page
flipping:

```sh
make run-timex
```

The local machine did not have `sjasmplus`, `z88dk-z80asm`, `z80asm`,
`pasmo`, `zcc`, `pyz80`, `zmac`, `rasm`, or `vasmz80_oldstyle` in `PATH`.
The project therefore includes `tools/build.py`, a small assembler for the
subset used by `src/main.asm`, plus a TAP writer.  No binary tools are
vendored.

## Running

Load `build/attribute-raid.tap` in a ZX Spectrum 48K emulator.  The BASIC
loader clears RAM below the code, loads the CODE block at 32768, and starts it
with `RANDOMIZE USR 32768`.

Keys:

- `1`: 2 pixels per frame
- `2`: 4 pixels per frame
- `UP`: faster, up to 8 pixels per frame
- `DOWN`: slower, down to 2 pixels per frame
- `SPACE`: pause
- `R`: rebuild the precomputed river course

## Graphics Model

The screen uses the standard Spectrum bitmap at `0x4000` and attributes at
`0x5800`.  All 768 attributes are initialized once to `0x4c`: bright green
ink on blue paper.  During animation the attribute area is not touched.

In the bitmap, bit `1` means land and bit `0` means water.  Full land and full
water cells are therefore `0xff` and `0x00`.  Edge cells are rebuilt from
`prefix_mask` and `suffix_mask` tables.  Each 2-pixel river sample is drawn as
two identical bitmap scanlines; this keeps normal-frame rendering cheap enough
for the 50 Hz budget.

## River Representation

The river geometry has 2-pixel vertical resolution.  One sample describes two
scanlines.  Two 1024-byte precomputed buffers store the banks:

- `left_bank[i]`: first water pixel after the left land
- `right_bank[i]`: first right-land pixel

Only 96 samples are visible on the 192-pixel screen, but 1024 entries make the
repeat much less obvious.  Bank motion is pseudo-random and deterministic: an
8-bit LFSR builds short 1-2 sample movement segments during initialization, so
the visible edges are jagged without random work during normal animation.
The first course segment is kept wide, around 70-80% of the screen, by using a
higher minimum river width at the beginning of the ring and at the wrapped
entry point used by the initial scroll.  Later samples allow the river to
narrow further.

Scrolling does not move the bitmap.  Each frame changes the logical start
index of the ring buffer by the current speed: one to four 2-pixel samples,
or 2-8 pixels per frame.  Normal frames do not generate river samples; the
precomputed course loops.

## Sprites

A prototype sprite layer draws one-cell 8 x 8 objects after the river
background:

- a white player plane near the bottom of the river
- three ships and three helicopters over the water, moving horizontally
- simple tree and tank glyphs that scroll down along both banks

Sprite cells are redrawn over the reconstructed river background each frame.
The plane switches to a crash glyph if the current river banks get too close
to its fixed bottom-screen position.  This is intentionally a coarse renderer
test, not a final gameplay or collision system.  Bank objects keep pixel `y`
positions and move down at the current river speed.  Ships and helicopters use
the same vertical motion while also moving sideways in pixel steps rather than
whole character columns.  Their horizontally shifted forms are precomputed, so
each frame only selects the needed phase and updates the cells touched by the
sprite.

The Timex build uses Timex video mode 1: screen 0 at `0x4000` and screen 1 at
`0x6000`.  Each screen remembers which river index and sprite positions it
contains, so the dirty renderer can update only the hidden page's old bank,
ship, and helicopter cells before flipping it with port `0xff`.

## Dirty Rendering

The full 32 x 24 cell screen is rendered only during startup and after `R`.
Normal frames never copy the 6144-byte bitmap and never redraw all 768 cells.

For each of the 24 tile rows, the renderer examines the four 2-pixel samples
covered by that row.  It computes the byte-column range crossed by the old
left bank, the new left bank, the old right bank, and the new right bank.  It
then redraws only the union of the old and new range for each bank.

There is no separate old-pixel map.  The two river buffers are the geometry
map, and the renderer tracks the previous 10-bit start index for the screen it
is updating.  Clearing is done by reconstructing complete cells from the new
geometry across the old-and-new dirty range.

Because each bank still moves by at most one pixel per sample, the usual dirty
width is one or two cells per bank per tile row, sometimes three cells around
strong turns or byte boundaries.

## Profiling

The border is kept black during normal animation.  Earlier development builds
used yellow/red border profiling, but that made the emulator visibly flash
while the renderer was being tuned.

In the current build environment the TAP structure and checksums were verified,
but a visual 50 Hz emulator run was not completed because the ZEsarUX control
server was not available on `localhost:10000`.

The algorithm differs from classic full-screen scrolling by never shifting
screen memory.  The visible river moves because screen rows read different
ring-buffer samples after the logical start index changes, and only the cells
where a bank changed are reconstructed.
