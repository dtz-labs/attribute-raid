; ---------------------------------------------------------------------------
; State
; ---------------------------------------------------------------------------

; Scroll/generator state. The 256-byte geometry tables below contain only 32
; live entries, but page alignment lets a block index be installed in L.
course_block_head: db 31
course_phase: db 7
speed_pixels: db 1               ; resolved scroll for this frame: 0, 1 or 2
paused: db 0
fire_down: db 0                  ; edge detector shared by SPACE and FIRE
r_down: db 0                     ; edge detector for manual new-game reset
profile_enabled: db PROFILE_BORDER

gen_center_x: db 128
gen_half_x: db 76
center_step: db 0
half_step: db 0
motion_timer: db 0
lfsr: db 0xa7
feature_countdown: db 40
fork_step: db 0
next_feature: db 0
bridge_spawn_pending: db 0
generated_island_left: db 255
generated_island_right: db 255   ; 255 in both island fields means no fork

; Scratch shared by full and dirty renderers. Keeping these in RAM releases
; registers for the byte masks and avoids stack traffic in the inner row code.
dirty_first_y: db 0
dirty_y: db 0
dirty_residues: db 0
dirty_rows_remaining: db 0
dirty_delta_ptr: dw 0
row_block_index: db 0
row_screen_addr: dw 0
redraw_y: db 0

; Actor X coordinates are real pixels. tank_col is retained only as temporary
; byte geometry when placing a shore tank; drawing and collision use tank_x.
; Y always refers to the top scanline of the sprite.
player_y: db PLAYFIELD_BOTTOM-14
player_x: db 120
player_move: db 0
player_bank: db 0                ; 255=left roll, 0=level, 1=right roll
player_full_redraw: db 0         ; pose/X changed; redraw all 14 rows once
player_dirty_row: db 0
player_dirty_rows: db 0
player_dirty_source_base: dw 0
crashed: db 0
bullet_active: db 0
fire_pending: db 0
bullet_y: db PLAYFIELD_BOTTOM-18
bullet_x: db 120
bullet_background_y: db 0
bullet_background_rows: db 0
bullet_background_col: db 0
bullet_background_mask_0: db 0
bullet_background_mask_1: db 0
ship0_y: db 16
ship0_x: db 96                   ; top-left of a 32-pixel hull
ship0_active: db 1
ship0_delay: db 0
ship1_y: db 92
ship1_x: db 136                  ; top-left of a 32-pixel hull
ship1_active: db 0
ship1_delay: db 80
ship1_dir: db 1
ship1_timer: db 2
enemy_plane_y: db 16
enemy_plane_x: db 0
enemy_plane_active: db 0          ; first crossing waits for a clear top entry
enemy_plane_delay: db 48          ; 255=shot down; otherwise top-entry retry
helicopter_y: db 126
helicopter_x: db 120
helicopter_active: db 0
helicopter_delay: db 140
helicopter_move: db 1
helicopter_dir: db 1
helicopter_frame: db 0            ; two mirrored rotor poses, body unchanged
helicopter_anim_timer: db 2
fuel_y: db 112
fuel_x: db 112                     ; byte-aligned top-left of vertical 8x32 depot
fuel_active: db 1
fuel_delay: db 0
fuel_level: db 48                  ; six HUD cells, eight units per cell
fuel_consume_timer: db 32
fuel_refill_timer: db 1
fuel_refueling: db 0               ; skips consumption while player overlaps
balloon_y: db 16
balloon_x: db 120                   ; byte-aligned top-left of 16x20 balloon
balloon_active: db 0
balloon_delay: db 120
tank_y: db 46
tank_col: db 3
tank_x: db 24
tank_side: db 0
tank_active: db 1
tank_delay: db 0
tank_fire_timer: db 72           ; initial bank-tank delay; later shots use 96
bridge_tank_y: db 16
bridge_tank_x: db 0
bridge_tank_side: db 0            ; 0 enters from left, 1 enters from right
bridge_tank_active: db 0
bridge_tank_mode: db 0            ; 1=cross intact bridge, 2=fire after blast, 3=pending
bridge_width_mode: db 0           ; alternates unrestricted and narrow bridges
bridge_tank_fire_timer: db 12
bridge_tank_move_phase: db 0      ; fixed speed alternates one/two-pixel steps
firing_tank_y: db 0               ; selected shore/bridge firing-source scratch
firing_tank_side: db 0
tank_shell_active: db 0           ; 0=absent, 1=flying, 2=landing splash
tank_shell_y: db 50
tank_shell_x: db 40              ; actual left edge of the 2x2 projectile
tank_shell_dir: db 1             ; 1=right, 255=left
tank_shell_target_x: db 120       ; safe water point selected when fired
tank_splash_timer: db 0
bridge_active: db 0              ; bridge bitmap persists between frames
destroyed_road_active: db 0      ; white approaches remain after span removal
bridge_y: db 0
bridge_col: db 0
bridge_width: db 0
bridge_rows_left: db 0
bridge_restore_y: db 0
bridge_restore_rows: db 0
bridge_attr_row: db 0
bridge_attr_rows: db 0
bridge_center_attr: db 0x4a       ; BRIGHT red intact span or normal water
bridge_edge_residue: db 0         ; dirty modulo-eight class under the bridge
bridge_edge_residues: db 0        ; remaining classes: one per scroll pixel
bridge_edge_y: db 0               ; first of two bridge rows in that class
road_mark_y: db 0
road_mark_rows: db 0
dirty_old_island_left: db 255
dirty_old_island_right: db 255
dirty_new_island_left: db 255
dirty_new_island_right: db 255
sprite_saved_sp: dw 0            ; real SP while POP HL walks scanline table
sprite_write_spill: db 0         ; nonzero when an opaque shifted row needs spill
sprite_fill_rows: db 0           ; opaque uniform-background rectangle scratch
sprite_fill_width: db 0
sprite_fill_value: db 0
; Common resident-sprite snapshot. The bitmap renderer consumes these fields
; in both binaries; TIMEX_HICOLOR is consulted only by the attribute pass.
sprite_old_player_x: db 0
sprite_old_player_y: db 0
sprite_old_player_bank: db 0
sprite_old_bullet_active: db 0
sprite_old_bullet_x: db 0
sprite_old_bullet_y: db 0
sprite_old_shell_active: db 0
sprite_old_shell_x: db 0
sprite_old_shell_y: db 0
sprite_old_ship1_dir: db 0
sprite_old_helicopter_frame: db 0
sprite_old_helicopter_dir: db 0
sprite_old_tank_side: db 0
sprite_old_enemy_active: db 0
sprite_old_enemy_x: db 0
sprite_old_enemy_y: db 0
sprite_old_bridge_tank_active: db 0
sprite_old_bridge_tank_x: db 0
sprite_old_bridge_tank_y: db 0
sprite_old_bridge_tank_side: db 0

transition_old_y: db 0
transition_old_col: db 0
transition_old_width: db 0
transition_new_active: db 0
transition_new_y: db 0
transition_new_col: db 0
transition_new_width: db 0
transition_height: db 0
transition_background: db 0       ; 0=water, 1=world geometry
transition_fill_y: db 0
transition_fill_rows: db 0
transition_fill_col: db 0
transition_fill_width: db 0

background_query_y: db 0
background_query_col: db 0
background_cache_y: db 255
background_cache_index: db 0
world_background_byte_0: db 0
world_background_byte_1: db 0
world_background_byte_2: db 0
block_bitmap_build_index: db 0
block_bitmap_build_col: db 0
block_bitmap_build_ptr: dw 0
block_delta_build_index: db 0
block_delta_build_col: db 0
block_delta_build_count: db 0
player_core_left: db 0
player_core_right: db 0
player_core_y: db 0
player_core_rows: db 0
player_core_block_index: db 0
player_core_block_residue: db 0
world_write_y: db 0
world_write_col: db 0
world_write_rows: db 0
world_write_spill: db 0
world_write_byte_0: db 0
world_write_byte_1: db 0
world_write_byte_2: db 0
world_source_ptr: dw 0             ; player dirty-row source cursor
bridge_tank_write_row: db 0

; The ship fields predate the common resident-sprite compositor and retain
; their names for now, but are snapshots consumed identically by both builds.
timex_bitmap_ship0_active: db 0
timex_bitmap_ship0_x: db 0
timex_bitmap_ship0_y: db 0
timex_bitmap_ship1_active: db 0
timex_bitmap_ship1_x: db 0
timex_bitmap_ship1_y: db 0
timex_attr_helicopter_active: db 0
timex_attr_helicopter_x: db 0
timex_attr_helicopter_y: db 0
timex_attr_fuel_active: db 0
timex_attr_fuel_x: db 0
timex_attr_fuel_y: db 0
timex_attr_balloon_active: db 0
timex_attr_balloon_x: db 0
timex_attr_balloon_y: db 0
timex_attr_tank_active: db 0
timex_attr_tank_x: db 0
timex_attr_tank_y: db 0
timex_attr_cleanup_overlap: db 0

; One-time cache builder scratch. Runtime blitters never use these fields.
precompute_source: dw 0
precompute_cursor: dw 0
precompute_dest: dw 0
precompute_height: db 0
precompute_rows: db 0
precompute_shift: db 0
requested_speed: db 1            ; raw Q/A/Kempston request before 0.5x phase
slow_phase: db 0                 ; alternates 0/1 scroll for average 0.5 px
fast_phase: db 0                 ; alternates 1/2 scroll for average 1.5 px
joystick_state: db 0             ; sanitized Kempston bits 0..4
ay_last_speed: db 255             ; avoids rewriting unchanged engine registers
timex_ay_present: db 0            ; 1 only for a ROM-confirmed TC2068/TS2068
shot_sound_timer: db 0            ; 17..0 software amplitude/frequency envelope
shot_sound_period: db 80           ; larger AY period gives the requested lower shot
explosion_sound_timer: db 0       ; channel C impact envelope, 16..0
explosion_sound_period: dw 384
ding_sound_timer: db 0             ; four-frame channel C refuelling bell
ding_sound_period: db 160          ; normal refuel ping; full-tank ping uses 80

; Game/HUD state. Score digits live beside hud_text in writable constant data;
; direct ASCII carry makes a HUD refresh division-free.
lives: db 2
game_state: db 0                 ; 0=playing, 1=explosion, 2=between games
hud_dirty: db 1                  ; bit 0=lives, bit 1=score
hud_initialized: db 0            ; wait screen clears the otherwise static panel
hud_update_mask: db 0            ; saved bit mask while ROM glyphs are copied
score_redraw_count: db 4         ; 1 normally, grows leftward when 9 carries
hud_clear_y: db 0
object_collision_width: db 16    ; solid-body width selected per actor
explosion_timer: db 0
explosion_anim_timer: db 0
explosion_frame: db 0
hit_explosion_active: db 0        ; short impact animation for shot actors
hit_explosion_x: db 0
hit_explosion_y: db 16
hit_explosion_timer: db 0
hit_explosion_anim_timer: db 0
hit_explosion_frame: db 0
; Shared rectangle painter scratch for white helicopter and yellow explosion
; attributes. Rows 0, 1 and 23 are rejected by the painter.
object_attr_value: db 0
object_attr_width: db 0
object_attr_col: db 0
object_attr_row: db 0
object_attr_rows: db 0
object_attr_y: db 0               ; exact pixel row in the Timex 8x1 painter
fuel_attr_rows_remaining: db 0    ; custom F/U/E/L alternating-colour painter
fuel_attr_phase: db 0             ; even=magenta, odd=white (F/U/E/L)
fuel_attr_repeat: db 0            ; handles an attribute boundary after midpoint
timex_attr_y: db 0
timex_color_phase: db 0

; Minimal ROM-font renderer scratch. Text is copied only for HUD changes and
; the between-games screen, so these bytes are not performance-hot.
text_cursor: dw 0
text_remaining: db 0
text_y: db 0
text_col: db 0
font_source: dw 0
font_row_y: db 0
font_rows: db 0
footer_index: db 0
footer_timer: db 8
footer_row_y: db 184


; Each array is page-aligned so an index can be installed directly in L.
align 256
block_left_col:
    ds 256,0
align 256
block_left_mask:
    ds 256,0
align 256
block_right_col:
    ds 256,0
align 256
block_right_mask:
    ds 256,0
align 256
block_left_x:
    ds 256,0
align 256
block_right_x:
    ds 256,0
align 256
block_island_left:
    ds 256,255
align 256
block_island_right:
    ds 256,255

; Complete materialized terrain rows for 32 course blocks. A block occupies
; 32 bytes; eight blocks fit exactly in each of four aligned pages.
align 256
block_bitmap_rows:
    ds 1024,0

; Per-block dirty-row replay: one page of counts plus sixteen (column,value)
; pairs per block. A count of 255 selects the full renderer.
align 256
block_delta_count:
    ds 256,0
align 256
block_delta_ops:
    ds 1024,0


; Pre-shifted sprite cache.  Each table selects one contiguous variant for
; X&7; every cached row is three bytes wide, including shift zero.
player_shift_table:
    dw player_shift_data,player_shift_data+42,player_shift_data+84
    dw player_shift_data+126,player_shift_data+168,player_shift_data+210
    dw player_shift_data+252,player_shift_data+294
player_left_shift_table:
    dw player_left_shift_data,player_left_shift_data+42
    dw player_left_shift_data+84,player_left_shift_data+126
    dw player_left_shift_data+168,player_left_shift_data+210
    dw player_left_shift_data+252,player_left_shift_data+294
player_right_shift_table:
    dw player_right_shift_data,player_right_shift_data+42
    dw player_right_shift_data+84,player_right_shift_data+126
    dw player_right_shift_data+168,player_right_shift_data+210
    dw player_right_shift_data+252,player_right_shift_data+294
enemy_plane_shift_table:
    dw enemy_plane_shift_data,enemy_plane_shift_data+24
    dw enemy_plane_shift_data+48,enemy_plane_shift_data+72
    dw enemy_plane_shift_data+96,enemy_plane_shift_data+120
    dw enemy_plane_shift_data+144,enemy_plane_shift_data+168
helicopter_shift_table:
    dw helicopter_shift_data,helicopter_shift_data+30
    dw helicopter_shift_data+60,helicopter_shift_data+90
    dw helicopter_shift_data+120,helicopter_shift_data+150
    dw helicopter_shift_data+180,helicopter_shift_data+210

helicopter_alt_shift_table:
    dw helicopter_alt_shift_data,helicopter_alt_shift_data+30
    dw helicopter_alt_shift_data+60,helicopter_alt_shift_data+90
    dw helicopter_alt_shift_data+120,helicopter_alt_shift_data+150
    dw helicopter_alt_shift_data+180,helicopter_alt_shift_data+210
helicopter_left_shift_table:
    dw helicopter_left_shift_data,helicopter_left_shift_data+30
    dw helicopter_left_shift_data+60,helicopter_left_shift_data+90
    dw helicopter_left_shift_data+120,helicopter_left_shift_data+150
    dw helicopter_left_shift_data+180,helicopter_left_shift_data+210
helicopter_left_alt_shift_table:
    dw helicopter_left_alt_shift_data,helicopter_left_alt_shift_data+30
    dw helicopter_left_alt_shift_data+60,helicopter_left_alt_shift_data+90
    dw helicopter_left_alt_shift_data+120,helicopter_left_alt_shift_data+150
    dw helicopter_left_alt_shift_data+180,helicopter_left_alt_shift_data+210
tank_right_shift_table:
    dw tank_right_shift_data,tank_right_shift_data+30
    dw tank_right_shift_data+60,tank_right_shift_data+90
    dw tank_right_shift_data+120,tank_right_shift_data+150
    dw tank_right_shift_data+180,tank_right_shift_data+210
tank_left_shift_table:
    dw tank_left_shift_data,tank_left_shift_data+30
    dw tank_left_shift_data+60,tank_left_shift_data+90
    dw tank_left_shift_data+120,tank_left_shift_data+150
    dw tank_left_shift_data+180,tank_left_shift_data+210
explosion_0_shift_table:
    dw explosion_0_shift_data,explosion_0_shift_data+39
    dw explosion_0_shift_data+78,explosion_0_shift_data+117
    dw explosion_0_shift_data+156,explosion_0_shift_data+195
    dw explosion_0_shift_data+234,explosion_0_shift_data+273
explosion_1_shift_table:
    dw explosion_1_shift_data,explosion_1_shift_data+39
    dw explosion_1_shift_data+78,explosion_1_shift_data+117
    dw explosion_1_shift_data+156,explosion_1_shift_data+195
    dw explosion_1_shift_data+234,explosion_1_shift_data+273
explosion_2_shift_table:
    dw explosion_2_shift_data,explosion_2_shift_data+39
    dw explosion_2_shift_data+78,explosion_2_shift_data+117
    dw explosion_2_shift_data+156,explosion_2_shift_data+195
    dw explosion_2_shift_data+234,explosion_2_shift_data+273

player_shift_data: ds 336,0
player_left_shift_data: ds 336,0
player_right_shift_data: ds 336,0
enemy_plane_shift_data: ds 192,0
helicopter_shift_data: ds 240,0
helicopter_alt_shift_data: ds 240,0
helicopter_left_shift_data: ds 240,0
helicopter_left_alt_shift_data: ds 240,0
tank_right_shift_data: ds 240,0
tank_left_shift_data: ds 240,0
explosion_0_shift_data: ds 312,0
explosion_1_shift_data: ds 312,0
explosion_2_shift_data: ds 312,0
