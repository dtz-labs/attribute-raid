# TODO

Distilled from the nine performance/correctness reviews written on 2026-07-25
(`*review*.md`, removed after verification), re-verified against the sources on
2026-07-26. Items the reviews recommended that had already landed were dropped.
The single correctness item and the three cleanups were completed on 2026-07-26
and are recorded under "Settled" below.

Context for priorities: the autopilot bench is much noisier than the earlier
figure of "~0-0.5 % frame overruns" suggested. Measured with
`tools/zrcp_tail_profiler.py` over three 1M-instruction windows per build,
sampling different course positions, the overrun rate ranged from 0.0 % to
7.8 % **on unmodified code**, depending entirely on how many actors were live
in the sampled window. A single window is worth little: aggregate several, and
always measure a control build through the identical protocol. Note also that
`enter-cpu-step` fails under `--vo null`, so the history ring stays at its
default 1M entries (~1.8 s) and cannot be enlarged on a headless host; a longer
`PLAY_SECONDS` only overwrites the ring, so 5 s is enough per cycle.

## Correctness

1. **Do resident fixed-X sprites erode the banks the way projectiles did?**
   Unverified suspicion, same mechanism as the settled projectile bug. `balloon_x`
   (`src/entities.asm:666`) and `ship0_x` (`:125`) are latched once at spawn from
   `calc_safe_river_x` and never re-clamped, while the river keeps meandering
   around them, and they are drawn with the opaque `write_water_sprite_2xn` /
   `write_water_sprite_1xn` rather than a world-composing writer. A balloon
   spawns mid-lane (at least 28 px of clearance at the narrowest river) but lives
   for roughly nineteen course blocks, and a bank edge moves up to four pixels
   per block, so the clearance can in principle be consumed. The FUEL depot is
   already immune because `load_world_background_triplet`
   (`src/sprite_renderer.asm:2408-2444`) overlays it into the world query.
   Investigate before changing anything: the damage scanner used for the
   projectile bug excluded mismatches that a live sprite explained, so it would
   have hidden exactly this case - the scan must attribute per sprite instead.
   If it reproduces, the fix is to move these writers onto the world compositor,
   which costs time; measure first.

## Performance

2. **Hoist the per-row terrain fetch in the projectile writers.** All eight
   scanlines of a course block share one materialized 32-byte terrain row, so a
   four-row bullet spans at most two distinct terrain rows - but
   `write_water_projectile_row` (`src/sprite_renderer.asm:3129`) now calls
   `load_world_background_triplet` on every row, and `restore_flying_shell_row`
   (:2016) calls it per row too. Fetch once and refetch only when the block index
   changes. This is the direct follow-up to the correctness fix, whose cost was
   measured as inconclusive against scene variance (aggregate 4.9 % -> 7.2 %
   overruns over ~430 frames per build, dominated by which actors were live);
   removing the redundant fetches makes the question moot. Combine with the
   incremental row addressing below.

3. **Incremental row addressing in projectile writers.**
   `write_water_projectile_row` still calls `calc_screen_line_addr` every row
   (heights 2-4); step `L += 32`, on carry `H += 8` like `render_dirty_rows` does
   (`src/course_renderer.asm:876-885`). Same trick applies to the per-row call in
   `restore_flying_shell_row`.

4. **Stage bridge destruction across two frames.** `destroy_bridge_restore`
   (`src/entities.asm:1959-1979`) rebuilds all 16 world rows in the same frame as
   the explosion, score and attribute repaint, called mid-`update_bullet`
   (:1571) - the most expensive single frame left. Add a `bridge_destroying`
   counter next to `bridge_restore_y`/`bridge_restore_rows`
   (`src/state.asm:127-128`) and let `update_bridge` finish 8 rows per frame.
   Optional follow-up if the destroy frame is still near budget: a
   "zero-interior-first" variant of `render_v3_row_indexed`
   (`src/course_renderer.asm:935`) so the destroy path can drop
   `render_full_world_row` (`src/entities.asm:1966-1972`).

5. **Hoist DI/EI + SP save out of the blitters to frame level.** Nine SP-driven
   blitters each pay their own `di` / `ld (sprite_saved_sp),sp` ... restore / `ei`
   bracket. Do `di` once after the `halt` in `main_loop` (`src/main.asm:64`) and
   `ei` before every path's next `halt` (including pause/crash/game-over paths),
   save SP once, delete the per-blit brackets. Every remaining call site of these
   blitters (board setup/init paths included) must be audited to run inside the
   DI window - while SP points into `screen_line_table` a stray interrupt
   corrupts it, so land as its own commit and verify with the profiler. A few
   hundred T/frame, and the highest-risk item on this list for the smallest
   measured gain: deprioritized accordingly.

6. **Specialize `transition_bullet_direct` like the flying shell.** The player
   bullet (4 rows x <=2 bytes, moves 6 px/frame so DeltaY > height) always falls
   through generic `cleanup_resident_sprite_delta` -> the transition fill. Mirror
   the shell's direct-restore fast path (`restore_flying_shell_row` model). Note
   the restore now writes composed world bytes, so the fast path must too.

7. **Vertical delta masks for scrolling resident sprites (FUEL first) - profile
   first.** Fixed-X sprites repair the exiting strip and then fully redraw every
   row each scroll frame (`transition_fuel_direct` -> 32-row
   `write_water_sprite_1xn`; same shape for balloon, ships, helicopter).
   Boot-generated `old[row+speed] XOR new[row]` tables (generation in
   `tools/build.py`, source rows in `src/sprite_data.asm:141`) would update only
   changed rows. Cheaper fallback: cut the ~55 T/row `pop/add/djnz` overhead in
   the `write_water_sprite_1xn` row loop. Coordinate with correctness item 1,
   which may move these writers to the world compositor anyway.

8. **`fill_water_rect_preserve_bridge`: test `bridge_active` once.** The per-row
   loop re-tests the bridge and calls `fill_uniform_sprite_rect` once per row
   with B=1, paying the DI/SP preamble each time. With no bridge (or a rect that
   provably misses the band), issue one call for the whole rect.

9. **`snapshot_resident_sprite_state`: LDIR or per-actor gating.** Still ~40
   discrete `ld a,(nn)` / `ld (nn),a` pairs every frame
   (`src/sprite_renderer.asm:144-223`). Either reorder the live fields in
   `src/state.asm:46-119` so the snapshotted bytes form contiguous blocks
   matching the existing destination blocks and copy with LDIR (~200 T/frame;
   verify field order against the Timex consumers in `src/render_timex.asm`
   first), or skip inactive actors' blocks. Low priority.

10. **Standard-build attribute repaints: delta restore + register loop.**
    (a) `restore_standard_saved_*` (`src/main.asm:234-334`) restores the whole
    old attribute rect on every trigger; for scroll-only movement (same X, Y
    moved <8 px) restore only the rows the new rect no longer covers, mirroring
    the Timex delta cleanup. (b) `paint_object_attribute_row` and the F/U/E/L
    painter loop still round-trip width/value/row counters through RAM every row;
    hold them in registers. Low priority - repaints are already dirty-gated by
    `@STANDARD_ATTR_CHANGED`.

11. **`generate_block` register cleanups (~200-250 T/block).** Keep
    `gen_center_x`/`gen_half_x` in a register pair from the motion step through
    clamp and edge conversion (`src/course_renderer.asm:100-282`), keep
    `course_block_head` in a register (seven reads in the conversion section),
    drop both `push af`/`pop af` pairs. The flat-banks override
    (`course_flat_banks`) must still win over the register-held values.

12. **`rebuild_block_delta` residual RAM traffic.** The compare loop keeps
    `block_delta_build_col`/`block_delta_build_count` in RAM
    (`src/course_renderer.asm:399-413`); move them to registers. Only if the
    profiler still shows `generate_block` hot afterwards: replace the
    byte-compare with a geometric delta derived from old/new edge cols + island
    intervals.

13. **IM2 minimal handler - measure first.** The game still runs the ROM IM1 ISR
    (with KEY-SCAN) every frame (`src/main.asm:33`). Profile the ISR share; if
    worth the ~1,000-2,000 T/frame, install IM2 with a bare `reti` handler - this
    requires adding `im`, `ld i,a` and `reti` encodings to `tools/build.py` in the
    same change (repo convention).

14. **Micro (bundle with other work only).**
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
