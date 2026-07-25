# Attribute Raid — renderer V3

Attribute Raid is a River Raid-style prototype with a ZX Spectrum 48K-compatible
renderer and optional AY-3-8912 sound for the Spectrum 128K or a 48K machine
with an AY interface. All code executed on the Spectrum is well-commented Z80
assembly; there is no C runtime.

**Status:** `0.1.2` is a beta release. The core gameplay is playable, but level
progression and final balancing are not complete yet.

V3 deliberately follows the coarse geometry of the Atari 2600 game. The banks
are built from large stepped segments but still scroll smoothly by one pixel.
The renderer never copies or scrolls the complete screen bitmap. It updates
only the scanlines that have just crossed a world-block boundary. Moving
sprites are erased and redrawn with XOR, while the wide bridge is maintained
incrementally.

This is still a prototype rather than a complete game, but it has the basic
gameplay loop: aircraft controls, two speed modifiers, firing, collisions, two
lives, fuel and refuelling, a crash animation, scoring, AY sound, and a `GAME
OVER` screen. Complete level progression is not implemented yet.

## Building and running

```sh
make
make run
make run-48       # graphics/gameplay only on a stock 48K machine
```

The build produces `build/attribute-raid.tap`. Other targets are:

```sh
make profile      # the border shows the duration of a complete game update
make run-profile
make clean
```

`make run` selects a Spectrum 128K in ZEsarUX so the AY soundtrack is audible.
The program remains safe on a stock 48K machine, but its AY port writes have no
chip to answer them and are therefore silent.

The program starts at address `32768` (`0x8000`). `tools/build.py` implements
the small subset of Z80 instructions used by the game and generates both the
BASIC loader and TAP file, so no external Z80 toolchain is required.

## Controls

- `O` / `P` — move the player aircraft left / right at 2 px per frame,
- no speed key — base scrolling speed of 1 px per frame,
- hold `Q` — temporarily increase scrolling to 2 px per frame,
- hold `A` — temporarily reduce scrolling to an average of 0.5 px per frame,
- `SPACE` — fire,
- `R` — start a new game with two lives, a zero score, and a new course.

The Kempston joystick supports left/right, FIRE, and temporary speed changes.
Up is equivalent to `Q`, and down is equivalent to `A`. `make run` starts
ZEsarUX with Kempston emulation enabled. After the second life is lost, release
FIRE before pressing it again to start a new game; this prevents the `GAME
OVER` screen from being skipped accidentally.

## V3 course model

One course block represents eight world scanlines. Both bank positions use
four-pixel units, producing the large characteristic steps. The generator
keeps the same bank movement for 5–12 blocks, or 40–96 scanlines. Long straight
and constant-slope sections are therefore more common than small random
zigzags. A run may move both banks together, narrow or widen the river, or hold
one bank while the other turns. The width varies from brief 120-pixel narrows
to 168-pixel open water, and either edge moves by at most one bitmap byte
between adjacent blocks. Such a section could later be compressed into a
`length + step` pair.

Thirty-two blocks form a ring. Six page-aligned arrays store:

- the left-bank column and mask,
- the right-bank column and mask,
- the optional left and right edges of an island.

An island is a third land interval inside the river. It grows over consecutive
blocks, maintains its width, and then narrows, creating a real fork without a
second renderer or screen buffer. The bridge remains a separate object. It
matches the current river width and is 16 scanlines high. A white road with a
two-scanline dashed centre marking extends across the land on both sides.

The top character row is a static HUD, the bottom character row remains black,
and the river occupies 176 scanlines (`Y=8..183`). Each scroll sample changes
only one eighth of the playfield scanlines, so the renderer updates:

- 22 scanlines at 1 px per frame,
- 44 scanlines at 2 px per frame.

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
whole rectangle. Timex hi-colour mode is not required.

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
eight-bit-source and 2× horizontal expansion constraints.

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
- a destructible vertical 8×32 `F`/`U`/`E`/`L` depot with a white `F`, magenta
  `U`, white `E`, and magenta `L` background, which safely refuels the player
  on contact,
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
without frame skipping. Fuel, tanks, projectiles, and short explosion effects
are not counted because they have separate gameplay roles and appear only
periodically.

Moving sprites are applied with XOR. The blitter supports arbitrary bit
offsets, so 1–3 px movement is not implemented as a series of eight-pixel
jumps. Eight shifted variants of each shape are generated once in RAM during
startup, making drawing time independent of `X & 7`. Ships and helicopters use
the bounds of their current branch; during a fork, the island acts as a second
bank and forces them to turn around. While drawing a few sprite rows, `SP`
temporarily points at the scanline-address table, and consecutive `POP HL`
instructions avoid recalculating the Spectrum's interlaced bitmap addresses.
Respawning water objects select distinct vertical lanes at least twelve pixels
apart. Bridge-driven relocation uses the same check, preventing two ships or a
ship and helicopter from being XORed into a composite silhouette. FUEL uses
its complete 32-pixel height in both directions of this test: it avoids active
ships and aircraft when it appears, and later respawns avoid the whole depot.
If the entrance is occupied, the depot waits and retries instead of suddenly
materialising farther down the river.

The bridge is not erased in full while scrolling. Each frame restores only the
1–2 scanlines leaving its top, adds new scanlines at the bottom, and refreshes
four edge bytes after the river renderer. Its 16-pixel thickness therefore
does not require two complete passes over the rectangle.

## Collision and gameplay details

Bank collision no longer relies on rectangular branch bounds. Every opaque
pixel of the 16×13 player mask is compared with the actual bitmap. A set bit
means bank, island, or intact bridge. Transparent sprite corners cannot cause
an early crash, and both sides of an island behave identically.

A separate forgiving 6×6 player core checks collisions with the 32-pixel
ships, helicopter, crossing aircraft, the bridge tank, and the shared 2×2 tank
shell. The ordinary shore tank is not a direct collision target: it remains on
lethal land, while only its projectile enters navigable water. The shell moves
horizontally at 4 px per frame while retaining its world line as the river
scrolls. When fired, it aims toward the player's current centre but clamps its
destination to a safe water branch. At the destination it becomes a two-frame
animation of a ball and expanding splash. The flying shell is lethal; the
splash itself is harmless. The shore tank waits 72 frames before its first shot
and 96 frames between later shots, making its fire less frequent but more
dangerous once a shell is in flight.

The 32-column HUD displays `LIVES:n FUEL:###### SCORE:nnnnnn`. The six fuel
cells represent eight units each. One unit is consumed every 32 frames; while
the player overlaps `FUEL`, consumption pauses and one unit is restored every
five frames. Reaching zero causes a crash. Labels are copied only when the
screen is created. Later updates touch only the changed life digit, fuel cells,
or the shortest score suffix affected by decimal carry.

`FUEL` is deliberately non-lethal: the player may overlap it to refuel. A
projectile destroys it, awards 100 points, and starts the normal impact
explosion; another depot enters later. Its four letters occupy separate 8×8
cells in one vertical column. As in the Atari `FuelA/FuelB` shape, the bitmap
contains the solid depot body and cuts the letters out of it. Four stable colour
bands make the `F` and `E` backgrounds bright white and the `U` and `L`
backgrounds bright magenta; there is no temporal flashing. Standard Spectrum
colour is tied to the 8-line attribute grid, so while the bitmap moves every
pixel, a split colour boundary selects the letter occupying most of that cell.
A dedicated one-byte blitter draws 32 narrow rows with fewer bitmap writes than
the former 32×8 horizontal word.

Destroying either ship, the helicopter, or the crossing aircraft awards 100
points, consumes the projectile, and starts a short three-frame impact
explosion with an AY burst. Ships and the helicopter return after their
160-frame delay and only when a combat-sprite slot is free; the crossing
aircraft remains destroyed for the rest of the current scene. Projectile
collision tests the complete ten-scanline swept interval, so a six-pixel
movement cannot tunnel through an eight-line hull. The crossing aircraft is
tested explicitly because it may fly above land and its XOR image has already
been erased during collision processing.

After moving-target tests, the projectile's two solid pixels are checked over
all ten scanlines of the swept path. They must remain over clear bitmap bits,
which normally represent blue water. Contact with a bank, island, or road
consumes the projectile. Contact with the bridge geometry destroys the bridge
and awards points.

The player starts with two lives. After a collision, a three-frame explosion
replaces the aircraft while the river and all other objects remain frozen for
75 frames, or approximately 1.5 seconds at 50 Hz. After the first crash the
course restarts with one life and the score preserved. The second crash opens a
separate `GAME OVER` screen.

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
