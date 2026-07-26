# TODO

Distilled from the nine performance/correctness reviews written on 2026-07-25
(`*review*.md`, removed after verification), re-verified against the sources on
2026-07-26. Items the reviews recommended that had already landed were dropped.
The single correctness item and the three cleanups were completed on 2026-07-26
and are recorded under "Settled" below.

Context for priorities: the autopilot bench does NOT hold a steady 50 Hz, and
the earlier figure of "~0-0.5 % frame overruns" does not reproduce. Measured
with `tools/zrcp_tail_profiler.py` over five windows per build at different
course positions, unmodified code ranges from 0.0 % to 15.4 % overrun frames
depending on what is happening in the sampled window. Read the metric
correctly: a window reporting a high overrun share together with a high idle
share (one measured 43 % overrun with 56 % idle) is the game running at half
rate - once work exceeds a frame, the `halt` is reached after the interrupt has
already fired and waits for the next one, so heavy frames alternate with long
halts. That is a real overrun, not an artifact.

Measurement caveats, learned the hard way:

- **A scene-matched comparison between two builds is not achievable with this
  harness.** Enemy spawns come from the LFSR, a shift register whose value is
  scrambled by a single extra draw, so once two runs differ by one frame their
  actor populations diverge chaotically and never reconverge.
- **Do not anchor on emulated time.** An overrunning frame delays the next
  `halt`, so a busier build advances fewer logical frames per emulated second:
  a t-state anchor is correlated with the effect being measured. Anchoring on
  the game's own progress (counting wraps of `course_block_head`, four logical
  frames per block under the fixed-speed autopilot) aligns the course position
  to within a frame or two, which is the best available.
- Always run a control build through the identical protocol, pool several
  windows, and report the actor population per window so like-for-like pairs
  can be identified afterwards.
- `enter-cpu-step` fails under `--vo null`, so the history ring stays at its
  default 1M entries (~1.8 s), cannot be enlarged on a headless host, and
  breakpoint-based timing is unavailable. A longer `PLAY_SECONDS` only
  overwrites the ring; 5 s per cycle is enough.
- The ROM tape loader needs about three real minutes. Use the ZRCP `smartload`
  command instead: the game reaches user code in roughly 30 s.

## Correctness

1. **Resident sprites eat terrain along island and bank edges. Confirmed,
   partly fixed, and the remaining half is the largest known correctness bug.**
   All five resident actors damage the world, on both the draw path (the opaque
   `write_water_sprite_2xn` / `_1xn` / `_shifted_2xn` / `_shifted_4xn`) and the
   cleanup path (`fill_uniform_sprite_rect` with `E=0`, and
   `transition_background = 0` in the exception branches). Measured over 200 s of
   autopilot: 18 513 damaging writes, half of them full `0xFF` bytes. FUEL is the
   worst offender, then ship1, ship0, the helicopter, the balloon. Present on
   `main`, not introduced by the projectile work.

   **Discard the obvious theory first.** The damage is NOT the river meandering
   into a latched X. A world-anchored sprite advances `y += speed_pixels` on
   exactly the frames the course advances by the same amount, and
   `get_block_index_for_y` is `head - ((y+7-phase)>>3)`, so both terms move
   together and the index cancels: a resident sprite sits over the same course
   blocks for its whole life and the terrain under it never changes (128 120
   samples, no violation). The bend budget of four pixels per block is irrelevant.

   **The actual cause is vertical extent.** The safe X comes from ONE scanline
   sample, but these sprites are 8 to 32 scanlines tall and therefore span two to
   five course blocks, whose banks differ by up to four pixels and whose island
   edge jumps a whole byte column between adjacent blocks
   (`fork_left_offsets`/`fork_widths`). The rows below the sampled one land on
   terrain nobody checked. The patrol clamps have the same defect:
   `patrol_helicopter` (`src/entities.asm:584`) and `patrol_ship1` (`:197`) call
   `get_pixel_lane_bounds` with the actor's top row only.

   A second cause, the three spawns that clobbered A and so sampled row 1, is
   fixed. It was amplifying this one: ten percent of ship spawns landed partly
   on land.

   Two fix families. Composing the resident writers against
   `load_world_background_triplet` and restoring real world bytes mirrors the
   projectile fix but costs time on the most-drawn sprites. Making the placement
   correct instead - intersect `get_pixel_lane_bounds` over every block the
   sprite's height covers, at spawn and in the patrol clamps, and defer the spawn
   when the intersection is too narrow - costs nothing at runtime and should be
   sufficient, because a sprite that provably fits the water for its full height
   can keep its opaque writer. Prefer the second; it is also the smaller change.

   Two things to know before working on it. `render_dirty_rows` replays only the
   per-block delta columns, so damage to a column that two adjacent blocks share
   is never repaired - confirmed by watching one damaged column travel the whole
   playfield untouched. And the damage is not cosmetic:
   `check_player_background_pixels` (`src/entities.asm:2308`) tests the player
   against the model, not the framebuffer, so eroded land stays lethal while
   looking like water. Timex is unverified but shares the call-site logic.

   The FUEL depot is NOT the immune contrast case, as previously recorded here:
   `load_world_background_triplet` only makes OTHER sprites compose correctly
   over the depot; the depot's own writer and its own water fill still assume
   water.

## Performance

2. **Stage bridge destruction across two frames.** `destroy_bridge_restore`
   (`src/entities.asm:1959-1979`) rebuilds all 16 world rows in the same frame as
   the explosion, score and attribute repaint, called mid-`update_bullet`
   (:1571) - the most expensive single frame left. Add a `bridge_destroying`
   counter next to `bridge_restore_y`/`bridge_restore_rows`
   (`src/state.asm:127-128`) and let `update_bridge` finish 8 rows per frame.
   Optional follow-up if the destroy frame is still near budget: a
   "zero-interior-first" variant of `render_v3_row_indexed`
   (`src/course_renderer.asm:935`) so the destroy path can drop
   `render_full_world_row` (`src/entities.asm:1966-1972`).

   Note before starting: measuring this is what exposed the destroyed-road slow
   path (now fixed), and that was the dominant cost, not this frame. Staging
   addresses one or two frames out of the ~76 the band lives for. It also needs
   care that the earlier plan missed: while the rebuild is half finished the
   band is half destroyed, but the world model carries a single `bridge_active`
   bit for all sixteen rows, so the model has to be split by row against the
   restore cursor or sprites compositing over the finished rows will stamp road
   back onto them.

3. **Hoist DI/EI + SP save out of the blitters to frame level.** Nine SP-driven
   blitters each pay their own `di` / `ld (sprite_saved_sp),sp` ... restore / `ei`
   bracket. Do `di` once after the `halt` in `main_loop` (`src/main.asm:64`) and
   `ei` before every path's next `halt` (including pause/crash/game-over paths),
   save SP once, delete the per-blit brackets. Every remaining call site of these
   blitters (board setup/init paths included) must be audited to run inside the
   DI window - while SP points into `screen_line_table` a stray interrupt
   corrupts it, so land as its own commit and verify with the profiler. A few
   hundred T/frame, and the highest-risk item on this list for the smallest
   measured gain: deprioritized accordingly.

4. **Specialize `transition_bullet_direct` like the flying shell.** The player
   bullet (4 rows x <=2 bytes, moves 6 px/frame so DeltaY > height) always falls
   through generic `cleanup_resident_sprite_delta` -> the transition fill. Mirror
   the shell's direct-restore fast path (`restore_flying_shell_row` model). Note
   the restore now writes composed world bytes, so the fast path must too.

5. **Vertical delta masks for scrolling resident sprites (FUEL first) - profile
   first.** Fixed-X sprites repair the exiting strip and then fully redraw every
   row each scroll frame (`transition_fuel_direct` -> 32-row
   `write_water_sprite_1xn`; same shape for balloon, ships, helicopter).
   Boot-generated `old[row+speed] XOR new[row]` tables (generation in
   `tools/build.py`, source rows in `src/sprite_data.asm:141`) would update only
   changed rows. Cheaper fallback: cut the ~55 T/row `pop/add/djnz` overhead in
   the `write_water_sprite_1xn` row loop. Coordinate with correctness item 1,
   which may move these writers to the world compositor anyway.

6. **`fill_water_rect_preserve_bridge`: test `bridge_active` once.** The per-row
   loop re-tests the bridge and calls `fill_uniform_sprite_rect` once per row
   with B=1, paying the DI/SP preamble each time. With no bridge (or a rect that
   provably misses the band), issue one call for the whole rect.

7. **`snapshot_resident_sprite_state`: LDIR or per-actor gating.** Still ~40
   discrete `ld a,(nn)` / `ld (nn),a` pairs every frame
   (`src/sprite_renderer.asm:144-223`). Either reorder the live fields in
   `src/state.asm:46-119` so the snapshotted bytes form contiguous blocks
   matching the existing destination blocks and copy with LDIR (~200 T/frame;
   verify field order against the Timex consumers in `src/render_timex.asm`
   first), or skip inactive actors' blocks. Low priority.

8. **Standard-build attribute repaints: delta restore + register loop.**
    (a) `restore_standard_saved_*` (`src/main.asm:234-334`) restores the whole
    old attribute rect on every trigger; for scroll-only movement (same X, Y
    moved <8 px) restore only the rows the new rect no longer covers, mirroring
    the Timex delta cleanup. (b) `paint_object_attribute_row` and the F/U/E/L
    painter loop still round-trip width/value/row counters through RAM every row;
    hold them in registers. Low priority - repaints are already dirty-gated by
    `@STANDARD_ATTR_CHANGED`.

9. **`generate_block` register cleanups (~200-250 T/block).** Keep
    `gen_center_x`/`gen_half_x` in a register pair from the motion step through
    clamp and edge conversion (`src/course_renderer.asm:100-282`), keep
    `course_block_head` in a register (seven reads in the conversion section),
    drop both `push af`/`pop af` pairs. The flat-banks override
    (`course_flat_banks`) must still win over the register-held values.

10. **`rebuild_block_delta` residual RAM traffic.** The compare loop keeps
    `block_delta_build_col`/`block_delta_build_count` in RAM
    (`src/course_renderer.asm:399-413`); move them to registers. Only if the
    profiler still shows `generate_block` hot afterwards: replace the
    byte-compare with a geometric delta derived from old/new edge cols + island
    intervals.

11. **IM2 minimal handler - measure first.** The game still runs the ROM IM1 ISR
    (with KEY-SCAN) every frame (`src/main.asm:33`). Profile the ISR share; if
    worth the ~1,000-2,000 T/frame, install IM2 with a bare `reti` handler - this
    requires adding `im`, `ld i,a` and `reti` encodings to `tools/build.py` in the
    same change (repo convention).

12. **Micro (bundle with other work only).**
    - Add `cpl` (0x2F) to `tools/build.py` and replace the five `xor 255` in the
      land/bridge-tank blitters.
    - Shift-0 two-byte row variant for `xor_sprite_shifted_2xn`; runs twice per
      frame while a hit explosion is live.
    - Per-row `sprite_write_spill` test still present in
      `write_intact_bridge_tank_shifted_2xn` and `write_world_sprite_shifted_2xn`
      - the other shifted writers already select spill/no-spill variants before
      the loop.
    - `inc de` -> `inc e` in blit row loops, only after adding alignment (or
      page-fit assertions) for the cached rows in `src/sprite_cache.asm`.

## Settled on 2026-07-26

- **Projectiles erasing bank pixels.** Reproduced on the autopilot bench by
  comparing the display file against the game's own `block_bitmap_rows` cache:
  71 damage events in 160 s, erased runs of 1-5 px at bank-edge bytes,
  persisting up to 4.08 s and permanently on a straight section. Fixed by
  composing draw bytes as terrain XOR mask and restoring real world bytes;
  re-measured at 0 events against a pre-fix control and a no-shots noise floor.
  The primary culprit was the player bullet, not the splash: the review had
  guessed the splash, and static reading wrongly cleared the bullet.
- **Splash centre/edge confusion**, a second defect none of the reviews saw.
- **Dead code**: `get_course_background_byte_indexed`, `calc_river_center_col`
  and `timex_next_attribute_row` deleted.
- **The block-delta overflow fallback** is documented as a safety net rather
  than removed. Worth knowing: `render_v3_row_indexed` has only one live caller
  (bridge repair), and its island half never executes at all, because bridge
  zones are generated without islands. The `dirty_` prefix on those labels
  invites the opposite conclusion.
- **`prepare_transition_old_projectile_x`** masked twice and branched on a case
  that could never differ; the branch was dead, not merely ugly.
- **A destroyed road kept the renderer on its slow path.** `destroyed_road_active`
  lives until the band scrolls off the playfield - up to 76 frames - and
  `fill_world_background_rect` sent all sixteen band rows through the per-byte
  query engine for that whole time, so every sprite cleanup touching the band
  paid it. Measured as a sustained half-rate stretch (43 % of frame boundaries
  with no idle halt, alongside 56 % idle overall). Only band rows 1 and 14 carry
  the black edge lines, so the other fourteen now take the fast block-bitmap
  copy. This, not the destroy frame itself, was the bridge cost.

## Considered and rejected (do not revisit without new evidence)

- **Trimming `PLAYFIELD_BOTTOM` 168->160.** Proposed by three reviews as a
  ~500 T/frame saving; after the dirty-row rewrite an unchanged row is nearly
  free, so the saving collapsed. Now purely a design tradeoff (8 fewer visible
  scanlines), not a performance fix.
- **Speed-cap refinements** (dropping individual actors from the heavy-scene
  list, 1-1-2 cadence). The whole limiter was deleted; fast scroll is a flat
  2 px/frame everywhere (`src/input.asm:109-116`).
- **Replacing `bridge_fill_full_bitmap_row` with `fill_uniform_sprite_rect`.**
  The former is now an unrolled ~11 T/byte fill; the proposed replacement would
  be slower.
- **Merging the delta count byte into the ops record.** The separate
  8x-mirrored count page is load-bearing (free circular predecessor step,
  `src/course_renderer.asm:420-435`).
- **Composing projectile bytes with OR** rather than XOR, as the review
  suggested. OR makes a shot invisible over land (a set pixel on a set
  background); XOR punches a water-coloured hole and matches how the player and
  the other crossing actors already render over mixed terrain.
- **Caching the terrain triplet across a projectile's rows**, to undo the cost
  the correctness fix added. The premise was that all eight scanlines of a
  course block share one terrain row, so a four-row bullet should need one fetch
  instead of four. But `resolve_course_block_index`
  (`src/sprite_renderer.asm:2370-2391`) already caches the block index and the
  rows left in it precisely for writers that walk Y sequentially, which the
  projectile writer does - measured, most calls take that cheap path
  (`resolve_block_recompute` 8190 instructions against 27294 for the resolver).
  What remains per row is the bridge test, `block_bitmap_address`, three byte
  reads and the FUEL-column check: a ceiling near 1 % of a frame, of which a
  cache would recover about half. Against that, the cache would have to be
  conditional on there being no bridge band (rows 1 and 14 of the band differ
  from the rest) and no FUEL column overlap (the depot sprite is indexed by
  `y - fuel_y`), in code whose correctness was established empirically. The
  measured like-for-like cost of the whole fix was about 2 percentage points of
  overrun frames, so this is not where the time is - item 2 is.
