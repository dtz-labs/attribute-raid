# Attribute Raid — renderer V3

Attribute Raid is a River Raid-style prototype with a ZX Spectrum 48K-compatible
renderer and optional AY-3-8912 sound for the Spectrum 128K or a 48K machine
with an AY interface. All code executed on the Spectrum is well-commented Z80
assembly; there is no C runtime.

**Status:** `0.1.3` is a beta release. The core gameplay is playable, but level
progression and final balancing are not complete yet.

V3 keeps the Atari-style eight-scanline course cadence, while each bank edge
may now begin on any pixel rather than only on a coarse four-pixel grid. The
banks still scroll smoothly by one pixel. The renderer never copies or scrolls
the complete screen bitmap. It updates
only the scanlines that have just crossed a world-block boundary. The standard
Spectrum and Timex builds share one resident bitmap-sprite engine: ordinary
sprites are never blanked wholesale or erased with XOR. Exposed top/side bytes
are restored and the final zero/one rows are stored directly. Only short impact
and crash explosions intentionally use XOR. Timex adds its separate 8x1 colour
pass after the common bitmap work. The wide bridge is incremental in both.

This is still a prototype rather than a complete game, but it has the basic
gameplay loop: aircraft controls, two speed modifiers, firing, collisions, two
lives, fuel and refuelling, a crash animation, scoring, AY sound, and a `GAME
OVER` screen. Complete level progression is not implemented yet.

## Building and running

```sh
make
make run
make run-48       # graphics/gameplay only on a stock 48K machine
make run-timex    # alias for TC2068: hi-colour plus native AY
make run-tc2048   # hi-colour, no native AY chip
make run-tc2068   # hi-colour plus AY at ports 00F5/00F6
make run-ts2068   # US TS2068 variant
```

The default build produces two files:

- `build/attribute-raid.tap` for the ZX Spectrum 48K/128K,
- `build/attribute-raid-timex.tap` for the Timex TC2048/TC2068/TS2068
  hi-colour mode.

Other targets are:

```sh
make standard     # build only the 48K/128K TAP
make timex        # build only the Timex 8x1 TAP
make profile      # the border shows the duration of a complete game update
make run-profile
make profile-timex      # the same timing build for Timex 8x1
make run-profile-timex
make zesarux-config  # re-copy the host joystick mapping from ~/.zesaruxrc
make clean
```

### Emulator configuration

The `run*` targets start ZEsarUX with `--configfile tools/zesarux.rc` instead
of the global `~/.zesaruxrc`, so runs are reproducible and never overwrite
your own settings. That file holds the emulated Kempston joystick plus the
host joystick/pad mapping, and the emulator is told not to save it on exit.

Remap the pad in a normal ZEsarUX session (which writes `~/.zesaruxrc`), then
run `make zesarux-config` to copy the mapping back into `tools/zesarux.rc`.
Extra one-off flags can still be passed via `ZESARUX_FLAGS`, for example
`make run ZESARUX_FLAGS="--zoom 3"`.

`make run` selects a Spectrum 128K in ZEsarUX so the AY soundtrack is audible.
The program remains safe on a stock 48K machine, but its AY port writes have no
chip to answer them and are therefore silent.

The standard ZX Spectrum 128K still has 8×8 colour attributes; its shadow
screen does not add an 8×1 mode. Use the standard TAP on that machine. The
separate Timex TAP selects Extended Color mode through port `0xff`, where the
second display file becomes 6144 scanline attributes. It therefore provides
real 8×1 colour on the TC2048, TC2068, and TS2068, but its colours will not
display correctly on an ordinary Spectrum 128K. The Timex build keeps the same
bitmap, incremental renderer, controls, and 48K-sized game code.

The TC2048 has no native AY chip, so the Timex TAP deliberately remains silent
there instead of writing to an absent device. A TC2068 or TS2068 is recognized
from its HOME ROM signature and uses the native AY register/data ports
`$00F5`/`$00F6`. The standard TAP continues to use the Spectrum 128K ports
`$FFFD`/`$BFFD`. `make run-timex` therefore defaults to TC2068, while the
model-specific targets make the selected hardware explicit.

After loading, the game waits at a small start screen until SPACE or Kempston
FIRE is pressed. Its copyright row scrolls on this screen and on the restart
screen after `GAME OVER`, but becomes static for the whole active run.

The program starts at address `32768` (`0x8000`). `tools/build.py` implements
the small subset of Z80 instructions used by the game and generates both the
BASIC loader and TAP file, so no external Z80 toolchain is required.

The assembly is split by responsibility: `main.asm` owns startup, the main
loop, Spectrum attributes and screen states; course, entities, resident sprite
rendering, Timex attributes, AY sound, input, sprite data and writable state
live in separate `src/*.asm` includes. The built-in preprocessor supports
`#include`, conditional builds, `equ`, `assert`, and small parameter macros:
`#macro NAME arg`, `{arg}` substitution, `@NAME value`, and expansion-local
labels beginning with `%%`. `make` tracks every included assembly file.

## Controls

- `O` / `P` — move the player aircraft left / right at 2 px per frame,
- no speed key — base scrolling speed of 1 px per frame,
- hold `Q` — adaptive fast scrolling: 1/2 px alternating (1.5 px average) in
  light scenes, capped at 1 px while a tank, crossing aircraft, bridge, road,
  or projectile is active,
- hold `A` — temporarily reduce scrolling to an average of 0.5 px per frame,
- `SPACE` — fire,
- `R` — start a new game with two lives, a zero score, and a new course.

The Kempston joystick supports left/right, FIRE, and temporary speed changes.
Up is equivalent to `Q`, and down is equivalent to `A`. `make run` starts
ZEsarUX with Kempston emulation enabled. After the second life is lost, release
FIRE before pressing it again to start a new game; this prevents the `GAME
OVER` screen from being skipped accidentally.

## V3 course model

One course block represents eight world scanlines. Bank positions have
one-pixel precision, but a bend keeps its direction for 4–7 blocks, or 32–56
scanlines, so the outline remains a coherent shoreline rather than random
single-block noise. The centre and half-width evolve independently: one bank
may hold while the other turns, and the river can bend, narrow, or widen. Its
water width ranges from a brief 72-pixel narrow to 224 pixels, leaving at least
16 pixels of land at each side. An edge moves by at most four pixels between
adjacent blocks.

Thirty-two blocks form a ring. Page-aligned tables store:

- exact pixel bounds plus the left/right bank columns and masks,
- the optional left and right edges of an island.

Each generated block also materializes its complete 32-byte terrain template
and a short list of bytes that differ from its predecessor. A dirty scanline
normally replays only that list instead of repeating bank/island comparisons.

An island is a third land interval inside the river. It grows over consecutive
blocks, maintains its width, and then narrows, creating a real fork without a
second renderer or screen buffer. The bridge remains a separate object. It
matches the current river width and is 16 scanlines high. A white road with a
two-scanline dashed centre marking extends across the land on both sides.

The first two character rows are a blank black upper margin. The river occupies
152 scanlines (`Y=16..167`). The final three character rows form a fixed status
panel: one black separator row, the compact lives/fuel/score row, and the
copyright footer. Each scroll sample changes only one eighth of the playfield
scanlines, so the renderer updates:

- 19 scanlines at 1 px per frame,
- 38 scanlines at 2 px per frame.

On every affected scanline it normally replays only the precomputed bytes whose
terrain value changed; complex fork transitions fall back to the bounded edge
renderer. The full 6144-byte bitmap is rendered only during startup and after
`R`.

## Colour, bridge, and sprites

Normal attribute cells use `0x4c`: BRIGHT 1, green INK, and blue PAPER. A set
bitmap bit represents land or a visible object; a clear bit represents water.
The bridge temporarily changes its cells to `0x4a`, producing bright red
INK over bright blue PAPER. The original Spectrum has no dedicated brown
colour, so bright red is used to keep the water brightness unchanged.

The bridge is also a bitmap object, so it may begin at any Y position and move
smoothly by one pixel. Standard Spectrum attributes are tied to an 8×8 grid;
the bridge colour therefore covers two or three complete cells and advances in
eight-scanline steps even though the bitmap moves every pixel. The renderer
updates only an entering or departing attribute row instead of repainting the
whole rectangle in the standard build. The Timex build uses one attribute row
per bitmap scanline, so its bridge colour follows the moving bitmap exactly.

Road cells on the banks use bright white INK over green PAPER, while the part
above the river retains the red/brown bridge colour. Two central scanlines
contain alternating eight-pixel green gaps. This keeps both the road and bank
colours meaningful in a shared Spectrum attribute cell. Only the 1–2 centre
lines entering or leaving the road are changed during scrolling. The effect
does not use the physical screen border: the experimental border raster
reduced animation to roughly 25 Hz and has been removed.

The sprite shapes were suggested by screenshots of the Atari 2600 River Raid
and expanded horizontally by 2×. The public
[River Raid disassembly](https://gitlab.com/menelkir/atari-2600/-/blob/master/River%20Raid%20%28decomp%29.asm)
was used as a reference. The tank is a new silhouette drawn under the same
eight-bit-source and 2× horizontal expansion constraints. Steering selects
the original Atari `JetMove` swept-wing silhouette and reflects it exactly for
the opposite direction, as the 2600 did with `REFP0`; releasing the direction
returns to the level-wing sprite without leaving XOR trails.

The helicopter now uses the actual `Heli0A/B` and `Heli1A/B` data from the
Atari disassembly. Interleaving the A/B kernel rows produces the ten visible
scanlines; the two animation frames differ only in their first two rotor rows
and toggle every second display frame, matching the original logic. Atari used
the `REFP1` hardware bit to reflect the complete sprite when its patrol changed
direction. This version precomputes both animation frames in both directions,
so the helicopter's nose always points along its movement. It uses white INK
over blue PAPER. The Atari could change an object's colour on each scanline,
whereas the Spectrum has one colour pair per 8×8 cell; exact black-and-white
bands would create a visible attribute-clash rectangle.

The current scene contains:

- the player aircraft controlled with `O` / `P`,
- two 32-pixel-wide ships: one remains fixed on the X axis, while the other
  patrols by one real pixel every two frames and uses a horizontally reflected
  cache whenever it travels left, so its bow always faces its movement,
- an aircraft crossing all 256 screen pixels at 3 px per frame; its Y position
  scrolls with the course, so it remains on the world line where it appeared;
  once shot down it stays absent until the scene is restarted,
- a helicopter whose consecutive appearances alternate between stationary and
  one-pixel-per-frame patrol modes,
- a static 16×20 hot-air balloon: it does not patrol or animate, but remains
  anchored to the course and therefore scrolls down with the river,
- a destructible vertical 8×32 `F`/`U`/`E`/`L` depot with magenta `F` and `E`
  and white `U` and `L` backgrounds, which safely refuels the player on contact,
- a periodic black tank on the left or right bank, firing horizontally over
  water without resembling a blue hole in the bank,
- a bridge and full-width road with a tank that either drives from one screen
  edge, across the approach and bridge, to the opposite edge, or stops before
  the entrance and fires into the river,
- periodic river forks.

Houses and trees are deliberately disabled in this version.

At most two of the four water-combat actors (the two ships, helicopter, and
crossing aircraft) are active simultaneously. A ship or helicopter that leaves
the screen or is destroyed waits 160 frames before requesting a free slot;
when both slots are occupied, it keeps waiting instead of being generated and
silently overloading the renderer. This halves the main enemy-sprite density
without frame skipping. The static balloon, fuel, tanks, projectiles, and short
explosion effects are not counted because they have separate gameplay roles
and appear only periodically.

Both builds use the same bitmap compositor. Ships, helicopters, balloons and
FUEL occupy guaranteed water; the shore tank occupies full land. Their final
rows can therefore be stored directly, including transparent zeroes. The
player, crossing aircraft and bridge tank combine cached masks with a
materialized terrain row before storing the final bytes, so they do not cut a
bank edge or road marking. A scrolling actor restores only departing top rows
and any exposed side byte before writing its new shape; it is never blanked as
a whole between frames. The bridge likewise updates only entering/departing
rows and moving edge details. XOR is reserved for explosions.

The blitters support arbitrary bit offsets, so 1–3 px movement is not
implemented as a series of eight-pixel jumps. Eight shifted variants of each
shape are generated once in RAM during startup, making drawing time independent
of `X & 7`. Ships and helicopters use
the bounds of their current branch; during a fork, the island acts as a second
bank and forces them to turn around. While drawing a few sprite rows, `SP`
temporarily points at the scanline-address table, and consecutive `POP HL`
instructions avoid recalculating the Spectrum's interlaced bitmap addresses.
Recurring ships, the crossing aircraft, helicopters, balloons, FUEL, and shore
tanks may enter only at the first playfield scanline (`Y=16`). The entrance
check uses an eighteen-pixel gap for water actors and the full 32-pixel depot
height for FUEL. If that entrance is occupied, the actor waits off-screen and
retries later. A bridge conflict likewise removes a water actor and queues a
fresh top entry instead of teleporting it into a free lane halfway down the
screen.

The bridge is not erased in full while scrolling. Each frame restores only the
1–2 scanlines leaving its top, adds new scanlines at the bottom, and refreshes
four edge bytes after the river renderer. Its 16-pixel thickness therefore
does not require two complete passes over the rectangle.

## Collision and gameplay details

Bank collision does not sample the sprite-filled framebuffer. A forgiving 6×6
core of the player is checked against exact pixel bank bounds, island intervals
and the intact bridge for each covered world row. This avoids both framebuffer
ambiguity and deaths caused by transparent wing corners.

A separate forgiving 6×6 player core checks collisions with the 32-pixel
ships, balloon, helicopter, crossing aircraft, the bridge tank, and the shared
2×2 tank shell. The ordinary shore tank is not a direct collision target: it
remains on lethal land, while only its projectile enters navigable water. The
shell moves horizontally at 4 px per frame while retaining its world line as
the river scrolls. When fired, it aims toward the player's current centre but
clamps its destination to a safe water branch. At the destination it becomes a
two-frame animation of a ball and expanding splash. The flying shell is
lethal; the splash itself is harmless. The shore tank waits 72 frames before
its first shot and 96 frames between later shots, making its fire less frequent
but more dangerous once a shell is in flight.

The 32-column HUD displays `LIVES:n FUEL:###### SCORE:nnnnnn` in its only status
row. The copyright line remains static throughout active gameplay; it scrolls
only on the waiting screen between games, so it adds no gameplay copying. Each
fuel cell represents eight units and the HUD is dirtied only when one of those
thresholds is crossed. One unit is consumed every 32 frames; while the player overlaps
`FUEL`, consumption pauses and one unit is restored every five frames. Reaching
zero causes a crash. Labels are copied only when the screen is created. Later
updates touch only the changed life digit, fuel cells, or the shortest score
suffix affected by decimal carry.

`FUEL` is deliberately non-lethal: the player may overlap it to refuel. A
projectile destroys it, awards 100 points, and starts the normal impact
explosion; another depot enters later. Its four letters occupy separate 8×8
cells in one vertical column. As in the Atari `FuelA/FuelB` shape, the bitmap
contains the solid depot body and cuts the letters out of it. Four stable colour
bands make the `F` and `E` backgrounds bright magenta and the `U` and `L`
backgrounds bright white; there is no temporal flashing. Standard Spectrum
colour is tied to the 8-line attribute grid, so while the bitmap moves every
pixel, a split colour boundary selects the letter occupying most of that cell.
A dedicated one-byte blitter draws 32 narrow rows with fewer bitmap writes than
the former 32×8 horizontal word.

Destroying either ship, the balloon, helicopter, or crossing aircraft awards
100 points, consumes the projectile, and starts a short three-frame impact
explosion with an AY burst. Ships and the helicopter return after their
160-frame delay and only when a combat-sprite slot is free; the balloon uses
its own lightweight spawn delay, while the crossing aircraft remains destroyed
for the rest of the current scene. Projectile collision tests the complete
ten-scanline swept interval, so a six-pixel movement cannot tunnel through an
eight-line hull. The crossing aircraft is tested explicitly because it may fly
above land as well as water.

After moving-target tests, the projectile's two solid pixels are checked over
all ten scanlines of the swept path. They must remain over clear bitmap bits,
which normally represent blue water. Contact with a bank, island, or road
consumes the projectile. Contact with the bridge geometry destroys the bridge
and awards points.

The player starts with two lives. After a collision, a three-frame explosion
replaces the aircraft while the river and all other objects remain frozen for
75 frames, or approximately 1.5 seconds at 50 Hz. After the first crash the
course restarts with one life and the score preserved. The second crash opens a
separate `GAME OVER` screen. Frozen sprites remain resident during the pause;
only the old and new 13-row explosion phases are XORed every fifth frame.

The player projectile can destroy a bridge, now with both a visible impact and
an AY explosion. A bridge alone is worth 200 points. If a crossing tank is
already on the span, the same shot also removes the tank and awards 500 points
in total. A crossing tank which has not reached the span survives bridge
destruction, stops on the remaining road, and only then switches to firing
behaviour. Ships,
helicopters, and fuel are kept at
least eight pixels outside the bridge's vertical band and cannot pass through
it. The bridge tank is intentionally exempt. The shore and bridge tanks have
separate actor state and can appear simultaneously; only their projectile slot
is shared. Every tank on an intact bridge drives across it and never fires. A
crossing tank starts at pixel X=0 or X=240 and remains active until its hull
reaches the opposite screen edge; leaving the bridge span no longer removes
it. At base speed it alternates one- and two-pixel steps, averaging 1.5 px per
frame instead of the former 2 px. This sideways speed is independent of the
player's Q/A scroll modifier.

Bridge placement alternates between the naturally reached river width and a
deliberately narrow section (at most roughly 112 pixels of water), so not every
crossing is generated over a broad river.

Destroying a bridge clears all 16 affected bitmap scanlines before rebuilding
the complete banks, island, and river. The brown centre span becomes blue
water, while the white road approaches and their green dashed markings remain
on both banks and keep scrolling down with the world. A dedicated full-row repair
path is used when each dashed line leaves the road; the normal dirty renderer
updates only bank edges and therefore cannot reconstruct a row which has been
cleared completely.

## AY sound

The original Atari sound routine uses a white-noise jet channel whose frequency
depends on vertical speed and a separate short missile tone. The AY adaptation
keeps the same division of labour:

- channel A is noise-only engine sound,
- slow, base, and fast movement select progressively higher noise frequencies
  and volumes,
- channel B is a tone-only missile sweep,
- each shot starts a sixteen-frame software envelope: tone period increases
  from a deliberately lower initial pitch while volume falls from 8 to 0,
  producing a descending `bziu-uum`,
- tank fire restarts channel B with a sharper, louder sweep,
- channel C adds falling tone/noise bursts for impacts, the player's crash and
  the tank shell's water splash,
- refuelling temporarily turns channel C into a clean four-frame bell whose
  pitch remains constant while fuel is being added; reaching a full tank and
  remaining over the depot produces repeating pings exactly one octave higher.

Engine registers are rewritten only when the requested speed changes. A stock
48K Spectrum continues to run the same game code silently; use `make run` for a
128K ZEsarUX configuration or `make run-48` to test that fallback explicitly.

## Performance budget

A 48K 50 Hz frame contains 69,888 T-states. Current ZEsarUX profiling after the
resident-player and terrain-delta changes observed ordinary early-game frames
between roughly 32,000 and 54,000 T-states. A longer generated session with
several actors, bridge, bridge tank and shell sampled approximately
31,000–60,000 T-states; comparable heavy scenes before these changes reached
75,000–86,000.

Targeted TC2068 debugger measurements put a one-pixel dirty terrain pass at
10,564 T-states before its incremental-address rewrite and 8,404 afterwards
(about 20% less). A forced Timex pass containing FUEL, balloon, helicopter and
tank fell from 11,179 to 8,680 T-states (about 22% less). The terrain figure was
captured just before the final rare ring-wrap guard was added, so it documents
the size of the improvement rather than an exact current-cycle promise. These
are samples, not a claimed exhaustive worst case; `make profile` and
`make profile-timex` remain the source of truth for a particular scene.

The main savings are structural. Sprite shifts are generated once at startup;
water blitters consume a table of Spectrum scanline addresses with `POP HL`;
terrain rows are materialized once per generated course block; and dirty rows
replay precomputed `(column,value)` differences. The stationary player no
longer recomposes all fourteen rows every frame: without steering it repairs
only the two terrain residues touched at normal speed (four on a two-pixel
phase). Full player composition is reserved for X/pose changes and bridge-road
overlap.

The interactive fast mode does not combine a two-pixel bank pass with a tank,
crossing aircraft, bridge/road repair, or either projectile. Light frames
alternate one and two pixels; heavy frames are capped at one. The profiling
border covers input and AY work as well as rendering, so Q-specific regressions
remain visible.

Every active frame begins with `HALT`, synchronized to the display interrupt.
Both builds keep ordinary bitmaps resident; Timex then advances its 8×1
attribute pointers linearly and cleans only attribute rows/columns no longer
covered by the current object. A busy frame may slow the world without leaving
silhouettes erased for an entire displayed frame. This is an incremental,
raster-synchronized renderer, not page flipping or a second screen buffer.
