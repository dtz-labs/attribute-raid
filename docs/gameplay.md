# Collision and gameplay details

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

Destroying a bridge does not remove the span in one frame. The shot punches a
two-byte hole where the player aimed, wide enough to fly through, and the hole
then widens outward by `BRIDGE_CRUMBLE_CHUNK` byte columns on each side every
`BRIDGE_CRUMBLE_PAUSE` frames (defaults: two columns, eight frames - a 16x16
pixel chunk per side, the band being two character rows tall). Each stage
restarts the impact explosion and its AY burst, alternating ends, so the span
goes with a rhythm of separate blasts instead of a smooth dissolve. Both
constants live in `tools/build.py` and can be overridden with `DEFINES=` to
retune the rhythm without touching the source.

The span stays `bridge_active` for the whole crumble, and that is what keeps
the wreck scrolling with the world: the ordinary bridge machinery still moves
the band, fills the rows entering at its bottom, restores the rows leaving its
top, and repaints its colour cells. Only the hole columns are excluded, and
they are excluded consistently - the world model reports river for them, the
band writer steps over them, and the colour pass gives them water while the
surviving road keeps its own attribute. Colouring the whole span as water at
the moment of the hit is what used to make the abandoned road glare solid
green: an `0xff` road byte under water paper shows its green INK. A hole column
is rewritten from the world model rather than zero-filled, because the FUEL
depot belongs to that model and may share those columns.

Lethality is separate from existence. `bridge_lethal` is cleared by the hit, so
the wreck kills nothing and is no longer a target while it crumbles;
`check_player_background_pixels` tests that flag rather than `bridge_active`.
Once the hole reaches both ends of the span the bridge hands over to the plain
destroyed road, which needs no per-frame bitmap work: the brown centre is
already blue water, while the road approaches remain on both banks and keep
scrolling down with the world - as a white band on Timex, and with their two
black edge lines maintained per frame on the standard build.

