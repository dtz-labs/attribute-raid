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
Spectrum build erases and redraws moving sprites with XOR. The Timex build
keeps ordinary water/shore actors visible during the bank pass and redraws
that safe group by overwriting complete zero/one rows. The wide bridge is
maintained incrementally in both builds.

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

## Controls

- `O` / `P` — move the player aircraft left / right at 2 px per frame,
- no speed key — base scrolling speed of 1 px per frame,
- hold `Q` — adaptive fast scrolling: 1/2 px alternating (1.5 px average) in
  light scenes, capped at 1 px while a tank, bridge, road, or projectile is
  active,
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

Thirty-two blocks form a ring. Six page-aligned arrays store:

- the left-bank column and mask,
- the right-bank column and mask,
- the optional left and right edges of an island.

An island is a third land interval inside the river. It grows over consecutive
blocks, maintains its width, and then narrows, creating a real fork without a
second renderer or screen buffer. The bridge remains a separate object. It
matches the current river width and is 16 scanlines high. A white road with a
two-scanline dashed centre marking extends across the land on both sides.

The first two character rows are a blank black upper margin. The river occupies
152 scanlines (`Y=16..167`). The final three character rows form a fixed status
panel: the compact lives/fuel/score line, a 24-segment fuel bar, and the
copyright footer. Each scroll sample changes only one eighth of the
playfield scanlines, so the renderer updates:

- 19 scanlines at 1 px per frame,
- 38 scanlines at 2 px per frame.

On every affected scanline it writes three bytes around the left bank, three
around the right bank, and—only during a fork—a short island interval. The full
6144-byte bitmap is rendered only during startup and after `R`.

## Colour, bridge, and sprites

Normal attribute cells use `0x4c`: BRIGHT 1, green INK, and blue PAPER. A set
bitmap bit represents land or a visible object; a clear bit represents water.
The bridge temporarily changes its cells to `0x0a`, producing dark red/brown
INK over blue PAPER. The original Spectrum has no dedicated brown colour, so
dark red is the closest solid colour without dithering.

The bridge is also a bitmap object, so it may begin at any Y position and move
smoothly by one pixel. Standard Spectrum attributes are tied to an 8×8 grid;
the bridge colour therefore covers two or three complete cells and advances in
eight-scanline steps even though the bitmap moves every pixel. The renderer
updates only an entering or departing attribute row instead of repainting the
whole rectangle in the standard build. The Timex build uses one attribute row
per bitmap scanline, so its bridge colour follows the moving bitmap exactly.

Road cells on the banks use white INK over black PAPER, while the part above
the river retains the red/brown bridge colour. Two central scanlines contain
alternating eight-pixel gaps. Only the 1–2 centre lines entering or leaving the
road are changed during scrolling. The effect does not use the physical screen
border: the experimental border raster reduced animation to roughly 25 Hz and
has been removed.

The player, ship, crossing aircraft, and helicopter silhouettes were
reconstructed from the interlaced object data of the Atari 2600 River Raid and
expanded horizontally by 2×. The public
[River Raid disassembly](https://gitlab.com/menelkir/atari-2600/-/blob/master/River%20Raid%20%28decomp%29.asm)
was used as a reference. The tank is a new silhouette drawn under the same
eight-bit-source and 2× horizontal expansion constraints. Steering selects
the original Atari `JetMove` silhouette, reflected exactly for the opposite
direction as the 2600 did with `REFP0`; releasing the direction returns to the
level-wing sprite without leaving XOR trails.

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

The standard renderer and all sprites which can cross mixed terrain use XOR.
On Timex, ships, helicopters, balloons and FUEL are guaranteed to remain over
zero bitmap bytes (water), while the shore tank remains over full land bytes.
Their redraw therefore overwrites complete source rows, storing transparent
zeroes as well as opaque ones instead of performing an additive draw. Those
actors remain visible during the expensive dirty-bank pass. On ordinary Timex
frames, a scrolling ship is advanced in place: only the one or two departing
top rows and an exposed side byte are restored before the complete new shape
is written. It is never blanked as a whole between frames. Bridges remain
incremental too; only their departing/entering rows and moving edge details are
updated. The player, crossing aircraft, projectiles, explosions and bridge tank
retain the masked path because an opaque rectangle could otherwise cut a bank
edge or a road marking.

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

Bank collision no longer relies on rectangular branch bounds. Every opaque
pixel of the 16×14 player mask is compared with the actual bitmap. A set bit
means bank, island, or intact bridge. Transparent sprite corners cannot cause
an early crash, and both sides of an island behave identically.

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

The 32-column HUD displays `LIVES:n FUEL:###### SCORE:nnnnnn` in the first row
of the bottom panel. A second line shows `FUEL: [########################]`.
The copyright line remains static throughout active gameplay; it scrolls only
on the waiting screen between games, so it adds no copying to a gameplay frame.
The compact six fuel cells represent eight units each, while each segment of
the detailed bar represents two units. One unit is consumed every 32 frames;
while the player overlaps
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
above land and its XOR image has already been erased during collision
processing.

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
in total. A tank waiting and firing on a white road approach survives bridge
destruction. A crossing tank which has not reached the span also survives,
stops on the remaining road, and switches to the firing behaviour. Ships,
helicopters, and fuel are kept at
least eight pixels outside the bridge's vertical band and cannot pass through
it. The bridge tank is intentionally exempt. The shore and bridge tanks have
separate actor state and can appear simultaneously; only their projectile slot
is shared. Bridge behaviours alternate, with the first bridge guaranteed to
use the crossing behaviour and the next tank stopping to fire. A crossing tank
starts at pixel X=0 or X=240 and remains active until its hull reaches the
opposite screen edge; leaving the bridge span no longer removes it. At base
speed it alternates one- and two-pixel steps, averaging 1.5 px per frame instead
of the former 2 px. This sideways speed is independent of the player's Q/A
scroll modifier.

Destroying a bridge clears all 16 affected bitmap scanlines before rebuilding
the complete banks, island, and river. The brown centre span becomes blue
water, while the white road approaches and their dashed markings remain on
both banks and keep scrolling down with the world. A dedicated full-row repair
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

The latest ZEsarUX debugger measurements made before the white road and centre
markings were added, at the 2 px-per-frame speed, were:

- 57,807 T-states for an ordinary full update,
- 64,796 T-states with an active 22-byte-wide bridge,
- 69,089 T-states in an artificially forced maximum with the bridge and both
  projectiles active.

A 50 Hz frame contains 69,888 T-states. The road does not redraw the complete
bridge. At 1 px per frame it restores one centre line and adds one; at 2 px it
does the same for two lines. Restoration writes only the 16 bytes that actually
contained black dashes. The left road, bridge span, and right road attributes
are written in one 32-byte pass rather than painting the full row white and
then overwriting the wide centre.

The interactive fast mode no longer combines a two-pixel bank pass with a tank,
bridge/road repair, or either projectile. Light frames alternate one and two
pixels; heavy frames are capped at one, avoiding the former worst-case stack-up
while retaining a faster average course speed when headroom is available.
The profiling border covers input and AY updates as well as rendering, so a
Q-specific timing regression is visible in the measured frame budget.
Moving-object attributes now calculate their first cell once and advance by the
linear 32-byte attribute-row stride. `FUEL` uses one pass for all of its
alternating colour bands instead of restarting the generic painter per row.

Every active frame begins with `HALT`, synchronized to the 50 Hz display
interrupt. In the Timex build, each 8×1 object painter likewise calculates its
first interleaved attribute address once and advances directly between
scanlines. Ordinary water/shore actors and their old colours remain resident
through the dirty-bank pass and most movement logic; only the bridge/projectile
collision tail lies between direct background restoration and opaque redraw.
Old 8×1 footprints are restored only after the new bitmaps and colours are
present, and only on rows or byte columns which no longer overlap the object.
A busy frame may therefore slow the world update without leaving those
silhouettes erased or green for an entire displayed frame. This is
raster-synchronized incremental rendering, not page flipping.

The precise current worst case still needs to be remeasured in the debugger,
so the values above must not be treated as timings for the current build. A
special five-byte blitter draws each wide ship in one pass; composing it from
two ordinary sprites would require setting up the scanline table and `SP`
twice. The new two-actor water-combat cap also prevents the old four-enemy
maximum from occurring in normal play. The generator schedules bridges and
forks as separate course features, so their most expensive paths do not
overlap in normal generation.

A consistency test removed all moving sprites and compared all 6144 bitmap
bytes with a full reconstruction from the course ring. The number of differing
bytes was `0`.
