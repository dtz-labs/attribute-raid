# Renderer V3

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
blocks, maintains its width for a randomized stretch of up to a few screens
(both lanes keep meandering with the river centre), and then narrows, creating
a real fork without a second renderer or screen buffer. The bridge remains a separate object. It
matches the current river width and is 16 scanlines high. A road extends
across the land on both sides, and the course generator keeps both banks
straight in the span's immediate vicinity - a few blocks below and above it -
while the rest of the river bends normally. The two builds style the road
differently: Timex 8x1 paints it as a solid white band, while the standard
build avoids 8x8 attribute clash entirely - its road cells keep terrain-green
ink over black paper and the road is outlined by two solid black bitmap edge
lines drawn only over the land approaches, never across the span.

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

In the standard build the road approaches keep the terrain look: their cells
use `0x44` (terrain-green INK over black PAPER) and the road is drawn as two
solid black bitmap edge lines across the land only, never over the span. The
river banks of the whole bridge board are latched to byte boundaries when the
bridge is scheduled, and the span colour covers exactly the water columns, so
no attribute cell ever mixes road colour with meandering terrain — the source
of the former attribute clash at the banks. The Timex build keeps its white
road, following the bitmap per scanline. The effect does not use the physical
screen border: the experimental border raster reduced animation to roughly
25 Hz and has been removed.

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
  cache whenever it travels left, so its bow always faces its movement; the
  Timex build colours each hull scanline like the Atari `ShipCol` table —
  black mast and superstructure, red upper hull, cyan waterline — while the
  standard build keeps the single river ink to avoid an attribute rectangle,
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
bank edge or the road. A scrolling actor restores only departing top rows
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

Bridge boards are kept as a calm corridor: the heavy movers — the patrolling
ship, the crossing aircraft, helicopters, and shore tanks — hold while a
bridge is scheduled within one screenful of arriving, queued, on screen, or
while its destroyed road is still scrolling through. The static ship, the
balloon, and FUEL still appear there, and the tank crossing the bridge stays
the corridor's only heavy actor.

The bridge is not erased in full while scrolling. Each frame restores only the
1–2 scanlines leaving its top, adds new scanlines at the bottom, and refreshes
four edge bytes after the river renderer. Its 16-pixel thickness therefore
does not require two complete passes over the rectangle.

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

The interactive fast mode scrolls a flat 2 px per frame in every scene; there
is no heavy-scene cap. The profiling border covers input and AY work as well
as rendering, so Q-specific regressions remain visible.

Every active frame begins with `HALT`, synchronized to the display interrupt.
Both builds keep ordinary bitmaps resident; Timex then advances its 8×1
attribute pointers linearly and cleans only attribute rows/columns no longer
covered by the current object. A busy frame may slow the world without leaving
silhouettes erased for an entire displayed frame. This is an incremental,
raster-synchronized renderer, not page flipping or a second screen buffer.
