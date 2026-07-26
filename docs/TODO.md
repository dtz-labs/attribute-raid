# TODO

Distilled from the nine performance/correctness reviews written on 2026-07-25
(`*review*.md`, removed after verification). Every item below was re-verified
against the current sources on 2026-07-26; everything the reviews recommended
that had already landed (mostly via commits 767e27b, f8aef7d, d54a02e,
a9a1f39, 424f82c) was dropped.

Context for priorities: the autopilot bench currently holds 50 Hz with
~0–0.5 % frame overruns and the worst frames are full-HALT frames. All
performance items are therefore opportunistic — run
`tools/zrcp_tail_profiler.py` on a bench build before and after any of them.

## Correctness

1. **Projectile draw/cleanup assumes the whole byte is water — can nick
   bank/island edges permanently.** `write_water_projectile_2xn`
   (`src/sprite_renderer.asm:2996-3042`) stores the 2-px mask byte raw, the
   splash draws via opaque `write_water_sprite_2xn` (:2651, call sites
   :852-888), and cleanup restores plain water (`transition_background=0` in
   `transition_bullet_direct` :1246-1247 and `transition_shell_direct`
   :1931-1932, direct zero writes in `restore_flying_shell_row` :1993-2000).
   A shell clamped near a bank (`src/entities.asm:1121-1135`) can overlap
   terrain pixels outside the two collision-checked mask bits; the dirty pass
   replays only per-block deltas, so a damaged byte on a straight section is
   never repaired. Fix: compose draw bytes as `world_background OR mask`
   (`get_world_background_byte` / `load_world_background_triplet`,
   `src/sprite_renderer.asm:2194` / :2340) and switch cleanup to
   `transition_background=1` so `fill_world_background_rect` (:2490) restores
   true world bytes. Manual check: shoot along a straight bank edge and look
   for lasting nicks.

## Performance — larger items

2. **Stage bridge destruction across two frames.** `destroy_bridge_restore`
   (`src/entities.asm:1959-1979`) still rebuilds all 16 world rows in the
   same frame as the explosion, score and attribute repaint, called
   mid-`update_bullet` (:1571) — the most expensive single frame left. Add a
   `bridge_destroying` counter next to `bridge_restore_y`/`bridge_restore_rows`
   (`src/state.asm:127-128`) and let `update_bridge` finish 8 rows per frame.
   Optional follow-up if the destroy frame is still near budget: a
   "zero-interior-first" variant of `render_v3_row_indexed`
   (`src/course_renderer.asm:974`) so the destroy path can drop
   `render_full_world_row` (`src/entities.asm:1966-1972`).

3. **Hoist DI/EI + SP save out of the blitters to frame level.** Nine
   SP-driven blitters each pay their own `di` / `ld (sprite_saved_sp),sp` …
   restore / `ei` bracket (`src/sprite_renderer.asm` :2103/2129, :2168/2188,
   :2635/2648, :2672/2689, :2714/2733, :2776/2816, :2858/2914, :2960/2993,
   :3229/3248). Do `di` once after the `halt` in `main_loop`
   (`src/main.asm:64`) and `ei` before every path's next `halt` (including
   pause/crash/game-over paths), save SP once, delete the per-blit brackets.
   Every remaining call site of these blitters (board setup/init paths
   included) must be audited to run inside the DI window — while SP points
   into `screen_line_table` a stray interrupt corrupts it, so land as its own
   commit and verify with `make profile`. A few hundred T/frame.

4. **Specialize `transition_bullet_direct` like the flying shell.** The
   player bullet (4 rows × ≤2 bytes, moves 6 px/frame so ΔY > height) always
   falls through generic `cleanup_resident_sprite_delta` →
   `fill_water_rect_preserve_bridge` (`src/sprite_renderer.asm:1215-1249`).
   Mirror the shell's direct-restore fast path (`restore_flying_shell_row`
   model, :1967-2001), keeping the bridge-band skip — the bullet does fly
   over intact bridges. Coordinate with item 1, which changes what "restore"
   writes.

5. **Vertical delta masks for scrolling resident sprites (FUEL first) —
   profile first.** Fixed-X sprites still repair the exiting strip and then
   fully redraw every row each scroll frame (`transition_fuel_direct`
   `src/sprite_renderer.asm:1493-1517` → 32-row `write_water_sprite_1xn`;
   same shape for balloon :1442-1455, ships :1261-1280/:1324-1342,
   helicopter :1563-1581). Boot-generated `old[row+speed] XOR new[row]`
   tables (generation in `tools/build.py`, source rows in
   `src/sprite_data.asm:141`) would update only changed rows. Cheaper
   fallback if this is skipped: cut the ~55 T/row `pop/add/djnz` overhead in
   the `write_water_sprite_1xn` row loop (`src/sprite_renderer.asm:2638-2646`),
   ~400 T/frame while FUEL is active.

## Performance — smaller items

6. **Incremental row addressing in projectile writers.**
   `write_water_projectile_row` still calls `calc_screen_line_addr` every row
   (`src/sprite_renderer.asm:3019-3042`, heights 2-4); step `L += 32`, on
   carry `H += 8` like `render_dirty_rows` does
   (`src/course_renderer.asm:876-885`). Same trick applies to the two per-row
   calls in `restore_flying_shell_row` (:1989). May be subsumed by item 1's
   rewrite of these paths.

7. **`fill_water_rect_preserve_bridge`: test `bridge_active` once.** The
   per-row loop re-tests the bridge and calls `fill_uniform_sprite_rect` once
   per row with B=1, paying the DI/SP preamble each time
   (`src/sprite_renderer.asm:628-679`, preamble :2168-2188). With no bridge
   (or a rect that provably misses the band), issue one call for the whole
   rect. Item 3 removes part of the per-call cost; this removes the rest.

8. **`snapshot_resident_sprite_state`: LDIR or per-actor gating.** Still ~40
   discrete `ld a,(nn)` / `ld (nn),a` pairs every frame
   (`src/sprite_renderer.asm:144-223`). Either reorder the live fields in
   `src/state.asm:46-119` so the snapshotted bytes form contiguous blocks
   matching the existing destination blocks (`src/state.asm:146-165`,
   :217-234) and copy with LDIR (~200 T/frame; verify field order against the
   Timex consumers in `src/render_timex.asm` first), or skip inactive actors'
   blocks. Low priority.

9. **Standard-build attribute repaints: delta restore + register loop.**
   (a) `restore_standard_saved_*` (`src/main.asm:234-334`) restores the whole
   old attribute rect on every trigger; for scroll-only movement (same X,
   Y moved <8 px) restore only the rows the new rect no longer covers,
   mirroring the Timex delta cleanup (`src/sprite_renderer.asm:226-237`).
   (b) `paint_object_attribute_row` (`src/main.asm:1193-1212`) and the
   F/U/E/L painter loop (:815-847) still round-trip width/value/row counters
   through RAM every row; hold them in registers. Low priority — repaints are
   already dirty-gated by `@STANDARD_ATTR_CHANGED`.

10. **`generate_block` register cleanups (~200-250 T/block).** Keep
    `gen_center_x`/`gen_half_x` in a register pair from the motion step
    through clamp and edge conversion (`src/course_renderer.asm:100-282`;
    RAM reads at :151-175, :187-270), keep `course_block_head` in a register
    (seven reads in the conversion section), drop both `push af`/`pop af`
    pairs (:202/206, :244/248). The flat-banks override
    (`course_flat_banks`, :195-201, :237-243) must still win over the
    register-held values.

11. **`rebuild_block_delta` residual RAM traffic.** The compare loop keeps
    `block_delta_build_col`/`block_delta_build_count` in RAM
    (`src/course_renderer.asm:399-413`); move them to registers. Only if the
    profiler still shows `generate_block` hot afterwards: replace the
    byte-compare with a geometric delta derived from old/new edge cols +
    island intervals (mirror `dirty_island_changed`, :1067-1147).

12. **IM2 minimal handler — measure first.** The game still runs the ROM IM1
    ISR (with KEY-SCAN) every frame (`src/main.asm:33`, comment :58-59).
    Profile the ISR share with `tools/zrcp_tail_profiler.py`; if worth the
    ~1,000-2,000 T/frame, install IM2 with a bare `reti` handler — this
    requires adding `im`, `ld i,a` and `reti` encodings to `tools/build.py`
    in the same change (repo convention).

13. **Micro (bundle with other work only).**
    - Add `cpl` (0x2F) to `tools/build.py` and replace the five `xor 255` in
      the land/bridge-tank blitters (`src/sprite_renderer.asm:2723`, :2728,
      :2969, :2974, :2982).
    - Shift-0 two-byte row variant for `xor_sprite_shifted_2xn`
      (:2060-2130); runs twice per frame while a hit explosion is live
      (`src/main.asm:130-141`).
    - Per-row `sprite_write_spill` test still present in
      `write_intact_bridge_tank_shifted_2xn` (:2978-2980) and
      `write_world_sprite_shifted_2xn` (:3153-3155) — the other shifted
      writers already select spill/no-spill variants before the loop.
    - `inc de` → `inc e` in blit row loops, only after adding alignment (or
      page-fit assertions) for the cached rows in `src/sprite_cache.asm`.

## Cleanups

14. **Dead code.** No callers anywhere: `get_course_background_byte_indexed`
    (`src/course_renderer.asm:438`, orphaned by the run-fill rewrite),
    `calc_river_center_col` (`src/course_renderer.asm:1252`),
    `timex_next_attribute_row` (`src/render_timex.asm:168-189`, byte-for-byte
    duplicate of `timex_advance_object_row_fast` :145-166). Delete after a
    final grep; reword the comment at `src/course_renderer.asm:287` if it
    references a removed routine.

15. **Cold island/fallback path: document or remove.** The `count=255`
    overflow fallback (`src/course_renderer.asm:397`, :417-419, :887-947)
    and the ~187-line island case logic in `render_v3_row_indexed`
    (:1030-1216) are reachable only from that practically-unreachable
    fallback and from bridge repair (`src/entities.asm:1305`), where islands
    are impossible by construction (bridge zones generate `island=255`,
    forks end ~32 blocks before a bridge). Either document it as a safety
    net, or remove it and assert at build time that a block delta never
    exceeds 15 pairs.

16. **`prepare_transition_old_projectile_x` masks `A and 7` twice**
    (`src/sprite_renderer.asm:774-795`, masks at :777 and :782-783). Compute
    once and branch on the 0/7/other cases; readability only, mirror
    `prepare_transition_new_projectile_x` (:797-811).

## Considered and rejected (do not revisit without new evidence)

- **Trimming `PLAYFIELD_BOTTOM` 168→160.** Proposed by three reviews as a
  ~500 T/frame saving; after the dirty-row rewrite an unchanged row is
  nearly free, so the saving collapsed. Now purely a design tradeoff
  (8 fewer visible scanlines), not a performance fix.
- **Speed-cap refinements** (dropping individual actors from the heavy-scene
  list, 1-1-2 cadence). The whole limiter was deleted; fast scroll is a flat
  2 px/frame everywhere (`src/input.asm:109-116`) and 50 Hz holds.
- **Replacing `bridge_fill_full_bitmap_row` with `fill_uniform_sprite_rect`.**
  The former is now an unrolled ~11 T/byte fill; the proposed replacement
  would be slower.
- **Merging the delta count byte into the ops record.** The separate
  8×-mirrored count page is load-bearing (free circular predecessor step,
  `src/course_renderer.asm:420-435`).
