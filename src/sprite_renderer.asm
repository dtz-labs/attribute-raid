; ---------------------------------------------------------------------------
; Resident bitmap sprite renderer
; ---------------------------------------------------------------------------
;
; The original Atari object data is eight bits wide and displayed doubled in
; X. Most tables below preserve that 2:1 pixel shape as 16-pixel Spectrum
; sprites; the ships use a separate 32-pixel cache. Both hardware builds use
; this same resident bitmap engine: it restores only exposed top/side bytes and
; stores complete zero/one rows for the new shape. Timex differs only in the
; later 8x1 attribute pass. Impact and crash explosions intentionally use XOR.

init_entities:
    ; All spawn Y values lie inside the 152-line playfield. River-bound actors
    ; ask the current course sample for a safe X; the crossing aircraft is the
    ; exception because it intentionally flies over water and land.
    ld a,PLAYFIELD_BOTTOM-14
    ld (player_y),a
    call calc_safe_river_x
    ld (player_x),a

    ld a,16
    ld (ship0_y),a
    call calc_safe_river_x_wide
    ld (ship0_x),a
    ld a,1
    ld (ship0_active),a
    xor a
    ld (ship0_delay),a
    ; A restart repaints the whole colour field, so the previous life's ship
    ; footprint must not satisfy the attribute pass's "unchanged" test.
    ld (timex_bitmap_ship0_active),a

    ld a,92
    ld (ship1_y),a
    call calc_safe_river_x_wide
    ld (ship1_x),a
    ld a,1
    ld (ship1_dir),a
    ld a,2
    ld (ship1_timer),a
    xor a
    ld (ship1_active),a
    ld (timex_bitmap_ship1_active),a
    ld a,80
    ld (ship1_delay),a

    ld a,16
    ld (enemy_plane_y),a
    xor a
    ld (enemy_plane_x),a
    ld (enemy_plane_active),a
    ld a,48                         ; first crossing also enters from the top
    ld (enemy_plane_delay),a

    ld a,126
    ld (helicopter_y),a
    call calc_safe_river_x
    ld (helicopter_x),a
    ld a,1
    ld (helicopter_move),a
    ld (helicopter_dir),a
    xor a
    ld (helicopter_frame),a
    ld a,2
    ld (helicopter_anim_timer),a
    xor a
    ld (helicopter_active),a
    ld a,140
    ld (helicopter_delay),a

    ld a,16                          ; inactive depot waits above the playfield
    ld (fuel_y),a
    call calc_safe_river_x
    and 0xf8                         ; vertical FUEL occupies one bitmap byte
    ld (fuel_x),a
    xor a
    ld (fuel_active),a
    ld (fuel_refueling),a
    ld (fuel_delay),a
    inc a
    ld (fuel_refill_timer),a
    ld a,48
    ld (fuel_level),a
    ld a,32
    ld (fuel_consume_timer),a

    ld a,16                          ; static balloon waits at the playfield top
    ld (balloon_y),a
    call calc_safe_river_x
    and 0xf8
    ld (balloon_x),a
    xor a
    ld (balloon_active),a
    ld a,120                         ; first balloon appears after a short gap
    ld (balloon_delay),a

    ld a,16                          ; first shore tank enters with the scenery
    ld (tank_y),a
    xor a
    ld (tank_side),a
    ld a,1
    ld (tank_active),a
    ld a,(tank_y)
    call calc_tank_col
    ld (tank_col),a
    add a,a
    add a,a
    add a,a
    ld (tank_x),a
    ld a,72
    ld (tank_fire_timer),a
    xor a
    ld (tank_delay),a
    ld (tank_shell_active),a
    ld (bridge_tank_active),a
    ld (bridge_tank_mode),a
    ld (bridge_width_mode),a
    ld (bridge_tank_side),a
    ld (bridge_tank_move_phase),a
    ld (bridge_active),a
    ld (destroyed_road_active),a
    ld (player_move),a
    ld (player_bank),a
    ld (bullet_active),a
    ld (fire_pending),a
    ld (fire_down),a
    ld (crashed),a
    ld (explosion_timer),a
    ld (explosion_anim_timer),a
    ld (explosion_frame),a
    ld (hit_explosion_active),a
    ld (missile_sound_left),a
    ld (c_sound_left),a
    ld (c_sound_kind),a
    ld (a_burst_left),a
    ld (crash_sound_kind),a
    ld (slow_phase),a
    ld (joystick_state),a
    ld a,1
    ld (requested_speed),a
    ld (speed_pixels),a
    ret

snapshot_resident_sprite_state:
    ; Save the state which produced the resident bitmap. This snapshot is
    ; shared by Spectrum and Timex; only the later attribute pass differs.
    ld a,(player_x)
    ld (sprite_old_player_x),a
    ld a,(player_y)
    ld (sprite_old_player_y),a
    ld a,(player_bank)
    ld (sprite_old_player_bank),a
    ld a,(bullet_active)
    ld (sprite_old_bullet_active),a
    ld a,(bullet_x)
    ld (sprite_old_bullet_x),a
    ld a,(bullet_y)
    ld (sprite_old_bullet_y),a
    ld a,(tank_shell_active)
    ld (sprite_old_shell_active),a
    ld a,(tank_shell_x)
    ld (sprite_old_shell_x),a
    ld a,(tank_shell_y)
    ld (sprite_old_shell_y),a
    ld a,(ship0_active)
    ld (timex_bitmap_ship0_active),a
    ld a,(ship0_x)
    ld (timex_bitmap_ship0_x),a
    ld a,(ship0_y)
    ld (timex_bitmap_ship0_y),a
    ld a,(ship1_active)
    ld (timex_bitmap_ship1_active),a
    ld a,(ship1_x)
    ld (timex_bitmap_ship1_x),a
    ld a,(ship1_y)
    ld (timex_bitmap_ship1_y),a
    ld a,(ship1_dir)
    ld (sprite_old_ship1_dir),a
    ld a,(helicopter_active)
    ld (timex_attr_helicopter_active),a
    ld a,(helicopter_x)
    ld (timex_attr_helicopter_x),a
    ld a,(helicopter_y)
    ld (timex_attr_helicopter_y),a
    ld a,(helicopter_frame)
    ld (sprite_old_helicopter_frame),a
    ld a,(helicopter_dir)
    ld (sprite_old_helicopter_dir),a
    ld a,(fuel_active)
    ld (timex_attr_fuel_active),a
    ld a,(fuel_x)
    ld (timex_attr_fuel_x),a
    ld a,(fuel_y)
    ld (timex_attr_fuel_y),a
    ld a,(balloon_active)
    ld (timex_attr_balloon_active),a
    ld a,(balloon_x)
    ld (timex_attr_balloon_x),a
    ld a,(balloon_y)
    ld (timex_attr_balloon_y),a
    ld a,(tank_active)
    ld (timex_attr_tank_active),a
    ld a,(tank_x)
    ld (timex_attr_tank_x),a
    ld a,(tank_y)
    ld (timex_attr_tank_y),a
    ld a,(tank_side)
    ld (sprite_old_tank_side),a
    ld a,(enemy_plane_active)
    ld (sprite_old_enemy_active),a
    ld a,(enemy_plane_x)
    ld (sprite_old_enemy_x),a
    ld a,(enemy_plane_y)
    ld (sprite_old_enemy_y),a
    ld a,(bridge_tank_active)
    ld (sprite_old_bridge_tank_active),a
    ld a,(bridge_tank_x)
    ld (sprite_old_bridge_tank_x),a
    ld a,(bridge_tank_y)
    ld (sprite_old_bridge_tank_y),a
    ld a,(bridge_tank_side)
    ld (sprite_old_bridge_tank_side),a
    ret

#if TIMEX_HICOLOR
cleanup_timex_saved_object_attributes:
    ; Current colours have already been painted. Clear only the part of each
    ; old footprint which is no longer covered by the new rectangle; clearing
    ; the whole old rectangle here would briefly turn the moving sprite green.
    ld a,0x4c
    ld (object_attr_value),a
    call cleanup_timex_saved_ship0_attributes
    call cleanup_timex_saved_ship1_attributes
    call cleanup_timex_saved_helicopter_attributes
    call cleanup_timex_saved_fuel_attributes
    call cleanup_timex_saved_balloon_attributes
    jp cleanup_timex_saved_tank_attributes

cleanup_timex_saved_helicopter_attributes:
    ld a,(timex_attr_helicopter_active)
    or a
    ret z
    ld a,10
    ld (object_attr_rows),a
    ld a,(helicopter_active)
    or a
    jr z,cleanup_timex_helicopter_vertical
    ld a,(helicopter_y)
    ld b,a
    ld a,(timex_attr_helicopter_y)
    ld c,a
    ld a,b
    sub c
    jr c,cleanup_timex_helicopter_full_height
    jr z,cleanup_timex_helicopter_horizontal
    cp 10
    jr nc,cleanup_timex_helicopter_full_height
    ld (object_attr_rows),a
    jr cleanup_timex_helicopter_vertical
cleanup_timex_helicopter_full_height:
    ld a,10
    ld (object_attr_rows),a
cleanup_timex_helicopter_vertical:
    ld a,(timex_attr_helicopter_x)
    and 7
    ld a,2
    jr z,cleanup_timex_helicopter_width_ready
    inc a
cleanup_timex_helicopter_width_ready:
    ld (object_attr_width),a
    ld a,(timex_attr_helicopter_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(timex_attr_helicopter_y)
    ld (object_attr_y),a
    call timex_paint_object_rows
    ld a,(helicopter_active)
    or a
    ret z

cleanup_timex_helicopter_horizontal:
    ; Clear a departing left column after a rightward byte crossing.
    ld a,(timex_attr_helicopter_x)
    srl a
    srl a
    srl a
    ld b,a
    ld a,(helicopter_x)
    srl a
    srl a
    srl a
    ld c,a
    cp b
    jr c,cleanup_timex_helicopter_check_right
    jr z,cleanup_timex_helicopter_check_right
    sub b
    ld (object_attr_width),a
    ld a,b
    ld (object_attr_col),a
    ld a,(timex_attr_helicopter_y)
    ld (object_attr_y),a
    ld a,10
    ld (object_attr_rows),a
    call timex_paint_object_rows

cleanup_timex_helicopter_check_right:
    ; Moving left from shift 1 to the aligned shape contracts three byte
    ; columns to two without changing the left column. Clear that old right
    ; spill as well; this is the attribute counterpart of the bitmap fix.
    ld a,(timex_attr_helicopter_x)
    ld b,a
    and 7
    ld d,2
    jr z,cleanup_timex_helicopter_old_width_ready
    inc d
cleanup_timex_helicopter_old_width_ready:
    ld a,b
    srl a
    srl a
    srl a
    add a,d
    ld b,a                           ; old exclusive right column
    ld a,(helicopter_x)
    ld c,a
    and 7
    ld d,2
    jr z,cleanup_timex_helicopter_new_width_ready
    inc d
cleanup_timex_helicopter_new_width_ready:
    ld a,c
    srl a
    srl a
    srl a
    add a,d
    ld c,a                           ; new exclusive right column
    ld a,b
    cp c
    ret c
    ret z
    sub c
    ld (object_attr_width),a
    ld a,c
    ld (object_attr_col),a
    ld a,(timex_attr_helicopter_y)
    ld (object_attr_y),a
    ld a,10
    ld (object_attr_rows),a
    jp timex_paint_object_rows

cleanup_timex_saved_fuel_attributes:
    ld a,(timex_attr_fuel_active)
    or a
    ret z
    ld a,32
    ld (object_attr_rows),a
    ; The first test above asks whether an old footprint exists.  This second
    ; one must inspect the current object: when fuel was collected, repaint
    ; all 32 old attribute rows instead of treating it as still present.
    ld a,(fuel_active)
    or a
    jr z,cleanup_timex_fuel_rect
    ld a,(fuel_y)
    ld b,a
    ld a,(timex_attr_fuel_y)
    ld c,a
    ld a,b
    sub c
    ret z
    jr c,cleanup_timex_fuel_full_height
    cp 32
    jr nc,cleanup_timex_fuel_full_height
    ld (object_attr_rows),a
    jr cleanup_timex_fuel_rect
cleanup_timex_fuel_full_height:
    ld a,32
    ld (object_attr_rows),a
cleanup_timex_fuel_rect:
    ld a,1
    ld (object_attr_width),a
    ld a,(timex_attr_fuel_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(timex_attr_fuel_y)
    ld (object_attr_y),a
    jp timex_paint_object_rows

cleanup_timex_saved_balloon_attributes:
    ld a,(timex_attr_balloon_active)
    or a
    ret z
    ld a,20
    ld (object_attr_rows),a
    ld a,(balloon_active)
    or a
    jr z,cleanup_timex_balloon_rect
    ld a,(balloon_y)
    ld b,a
    ld a,(timex_attr_balloon_y)
    ld c,a
    ld a,b
    sub c
    ret z
    jr c,cleanup_timex_balloon_full_height
    cp 20
    jr nc,cleanup_timex_balloon_full_height
    ld (object_attr_rows),a
    jr cleanup_timex_balloon_rect
cleanup_timex_balloon_full_height:
    ld a,20
    ld (object_attr_rows),a
cleanup_timex_balloon_rect:
    ld a,2
    ld (object_attr_width),a
    ld a,(timex_attr_balloon_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(timex_attr_balloon_y)
    ld (object_attr_y),a
    jp timex_paint_object_rows

cleanup_timex_saved_tank_attributes:
    ld a,(timex_attr_tank_active)
    or a
    ret z

    ; Preserve road colours when the shore tank's old world line overlaps an
    ; intact or destroyed bridge approach.
    xor a
    ld (timex_attr_cleanup_overlap),a
    ld a,(tank_y)
    push af
    ld a,(timex_attr_tank_y)
    ld (tank_y),a
    call tank_attributes_overlap_road
    jr z,cleanup_timex_tank_not_road
    ld a,1
    ld (timex_attr_cleanup_overlap),a
cleanup_timex_tank_not_road:
    pop af
    ld (tank_y),a
    ld a,(timex_attr_cleanup_overlap)
    or a
    ret nz

    ld a,10
    ld (object_attr_rows),a
    ld a,(tank_active)
    or a
    jr z,cleanup_timex_tank_rect
    ld a,(tank_y)
    ld b,a
    ld a,(timex_attr_tank_y)
    ld c,a
    ld a,b
    sub c
    ret z
    jr c,cleanup_timex_tank_full_height
    cp 10
    jr nc,cleanup_timex_tank_full_height
    ld (object_attr_rows),a
    jr cleanup_timex_tank_rect
cleanup_timex_tank_full_height:
    ld a,10
    ld (object_attr_rows),a
cleanup_timex_tank_rect:
    ld a,2
    ld (object_attr_width),a
    ld a,(timex_attr_tank_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(timex_attr_tank_y)
    ld (object_attr_y),a
    jp timex_paint_object_rows
#endif

cleanup_resident_sprite_delta:
    ; The old rectangle is still visible. Restore only rows/byte-columns not
    ; covered by the new rectangle; the caller immediately overwrites the full
    ; new shape, including its transparent zeroes. A zero old width means that
    ; the object did not exist in the preceding frame.
    ld a,(transition_old_width)
    or a
    ret z
    ld a,(transition_new_active)
    or a
    jp z,fill_transition_old_rect

    ld a,(transition_new_y)
    ld b,a
    ld a,(transition_old_y)
    ld c,a
    ld a,b
    sub c
    jr z,cleanup_transition_horizontal
    jr c,cleanup_transition_moved_up
    ld b,a
    ld a,(transition_height)
    cp b
    jp c,fill_transition_old_rect
    jp z,fill_transition_old_rect
    ld a,(transition_old_y)
    ld (transition_fill_y),a
    ld a,b
    ld (transition_fill_rows),a
    call fill_transition_old_columns
    jr cleanup_transition_horizontal

cleanup_transition_moved_up:
    ; A holds the wrapped negative delta. Recover old_y-new_y and restore the
    ; departing rows at the old bottom edge.
    ld a,(transition_old_y)
    ld b,a
    ld a,(transition_new_y)
    ld c,a
    ld a,b
    sub c
    ld b,a
    ld a,(transition_height)
    cp b
    jp c,fill_transition_old_rect
    jp z,fill_transition_old_rect
    ld a,(transition_new_y)
    ld c,a
    ld a,(transition_height)
    add a,c
    ld (transition_fill_y),a
    ld a,b
    ld (transition_fill_rows),a
    call fill_transition_old_columns

cleanup_transition_horizontal:
    ; Restore an old left byte-column exposed by rightward movement.
    ld a,(transition_new_col)
    ld b,a
    ld a,(transition_old_col)
    ld c,a
    ld a,b
    cp c
    jr c,cleanup_transition_right_edge
    jr z,cleanup_transition_right_edge
    sub c
    ld b,a
    ld a,(transition_old_width)
    cp b
    jr nc,cleanup_transition_left_count_ready
    ld b,a
cleanup_transition_left_count_ready:
    ld a,(transition_old_y)
    ld (transition_fill_y),a
    ld a,(transition_height)
    ld (transition_fill_rows),a
    ld a,(transition_old_col)
    ld (transition_fill_col),a
    ld a,b
    ld (transition_fill_width),a
    call dispatch_transition_fill

cleanup_transition_right_edge:
    ; Compare old and new exclusive right columns and restore any old excess.
    ld a,(transition_old_col)
    ld b,a
    ld a,(transition_old_width)
    add a,b
    ld b,a                          ; old right exclusive
    ld a,(transition_new_col)
    ld c,a
    ld a,(transition_new_width)
    add a,c                         ; new right exclusive
    ld c,a
    ld a,b
    cp c
    ret c
    ret z
    sub c
    ld (transition_fill_width),a
    ld a,c
    ld (transition_fill_col),a
    ld a,(transition_old_y)
    ld (transition_fill_y),a
    ld a,(transition_height)
    ld (transition_fill_rows),a
    jp dispatch_transition_fill

fill_transition_old_rect:
    ld a,(transition_old_y)
    ld (transition_fill_y),a
    ld a,(transition_height)
    ld (transition_fill_rows),a
fill_transition_old_columns:
    ld a,(transition_old_col)
    ld (transition_fill_col),a
    ld a,(transition_old_width)
    ld (transition_fill_width),a
    jp dispatch_transition_fill

dispatch_transition_fill:
    ld a,(transition_background)
    or a
    jr nz,dispatch_transition_world
    ld a,(transition_fill_y)
    ld b,a
    ld a,(transition_fill_rows)
    ld c,a
    ld a,(transition_fill_col)
    ld d,a
    ld a,(transition_fill_width)
    ld e,a
    jp fill_water_rect_preserve_bridge
dispatch_transition_world:
    ld a,(transition_fill_y)
    ld b,a
    ld a,(transition_fill_rows)
    ld c,a
    ld a,(transition_fill_col)
    ld d,a
    ld a,(transition_fill_width)
    ld e,a
    jp fill_world_background_rect

fill_water_rect_preserve_bridge:
    ; Input B=Y, C=rows, D=column, E=width. An intact bridge has already drawn
    ; its world layer. Skip rows inside its band so removing a water actor can
    ; never cut blue holes back into the span.
    ld a,c
    or a
    ret z
    ld a,e
    or a
    ret z
    ld a,b
    ld (transition_fill_y),a
    ld a,c
    ld (transition_fill_rows),a
    ld a,d
    ld (transition_fill_col),a
    ld a,e
    ld (transition_fill_width),a
fill_water_transition_row:
    ld a,(bridge_active)
    or a
    jr z,fill_water_transition_write
    ld a,(bridge_y)
    ld b,a
    ld a,(transition_fill_y)
    cp b
    jr c,fill_water_transition_write
    ld c,a
    ld a,b
    add a,16
    cp c
    jr c,fill_water_transition_write
    jr z,fill_water_transition_write
    jr fill_water_transition_next
fill_water_transition_write:
    ld a,(transition_fill_col)
    ld c,a
    ld a,(transition_fill_width)
    ld d,a
    ld a,(transition_fill_y)
    ld b,1
    ld e,0
    call fill_uniform_sprite_rect
fill_water_transition_next:
    ld a,(transition_fill_y)
    inc a
    ld (transition_fill_y),a
    ld a,(transition_fill_rows)
    dec a
    ld (transition_fill_rows),a
    jr nz,fill_water_transition_row
    ret

draw_current_ships_direct:
    call draw_current_ship0_direct
    jp draw_current_ship1_direct

draw_current_ship0_direct:
    ld a,(ship0_active)
    or a
    ret z
    ld a,(ship0_x)
    ld c,a
    ld a,(ship0_y)
    ld b,8
    ld de,ship_wide_shift_table
    jp write_water_sprite_shifted_4xn

draw_current_ship1_direct:
    ld a,(ship1_active)
    or a
    ret z
    ld a,(ship1_x)
    ld c,a
    ld a,(ship1_y)
    ld b,8
    ld de,ship_wide_shift_table
    push af
    ld a,(ship1_dir)
    cp 255
    jr nz,current_ship1_direction_ready
    ld de,ship_left_wide_shift_table
current_ship1_direction_ready:
    pop af
    jp write_water_sprite_shifted_4xn

prepare_transition_old_x_2:
    ld c,a
    and 7
    ld a,2
    jr z,prepare_transition_old_width_ready
    inc a
prepare_transition_old_width_ready:
    ld (transition_old_width),a
    ld a,c
    srl a
    srl a
    srl a
    ld (transition_old_col),a
    ret

prepare_transition_new_x_2:
    ld c,a
    and 7
    ld a,2
    jr z,prepare_transition_new_width_ready
    inc a
prepare_transition_new_width_ready:
    ld (transition_new_width),a
    ld a,c
    srl a
    srl a
    srl a
    ld (transition_new_col),a
    ret

prepare_transition_old_x_4:
    ld c,a
    and 7
    ld a,4
    jr z,prepare_transition_old_wide_ready
    inc a
prepare_transition_old_wide_ready:
    ld (transition_old_width),a
    ld a,c
    srl a
    srl a
    srl a
    ld (transition_old_col),a
    ret

prepare_transition_new_x_4:
    ld c,a
    and 7
    ld a,4
    jr z,prepare_transition_new_wide_ready
    inc a
prepare_transition_new_wide_ready:
    ld (transition_new_width),a
    ld a,c
    srl a
    srl a
    srl a
    ld (transition_new_col),a
    ret

prepare_transition_old_projectile_x:
    ; A is the actual two-pixel left edge. The pair spills into the following
    ; byte only at pixel offset 7, so this is the same test as
    ; prepare_transition_new_projectile_x below, writing the old fields.
    ld c,a
    and 7
    cp 7
    ld a,1
    jr nz,prepare_transition_old_projectile_ready
    inc a
prepare_transition_old_projectile_ready:
    ld (transition_old_width),a
    ld a,c
    srl a
    srl a
    srl a
    ld (transition_old_col),a
    ret

prepare_transition_new_projectile_x:
    ld c,a
    and 7
    cp 7
    ld a,1
    jr nz,prepare_transition_new_projectile_ready
    inc a
prepare_transition_new_projectile_ready:
    ld (transition_new_width),a
    ld a,c
    srl a
    srl a
    srl a
    ld (transition_new_col),a
    ret

draw_current_player_direct:
    ld a,(crashed)
    or a
    ret nz
    ld de,player_shift_table
    ld a,(player_bank)
    or a
    jr z,draw_current_player_table_ready
    ld de,player_right_shift_table
    cp 255
    jr nz,draw_current_player_table_ready
    ld de,player_left_shift_table
draw_current_player_table_ready:
    ld a,(player_x)
    ld c,a
    ld a,(player_y)
    ld b,14
    jp write_world_sprite_shifted_2xn

erase_current_player_for_crash:
    ; Collision now runs after the common compositor, so replace the resident
    ; player once with pure world bytes before the XOR explosion is added.
    ld a,(player_y)
    ld b,a
    ld c,14
    ld a,(player_x)
    ld d,a
    and 7
    ld e,2
    jr z,crash_player_width_ready
    inc e
crash_player_width_ready:
    ld a,d
    srl a
    srl a
    srl a
    ld d,a
    jp fill_world_background_rect

draw_current_bullet_direct:
    ld a,(bullet_active)
    or a
    ret z
    ld a,(bullet_x)
    add a,7
    ld c,a
    ld a,(bullet_y)
    ld b,4
    jp write_water_projectile_2xn

draw_current_shell_direct:
    ld a,(tank_shell_active)
    or a
    ret z
    cp 1
    jr nz,draw_current_splash_direct
    ld a,(tank_shell_x)
    ld c,a
    ld a,(tank_shell_y)
    ld b,2
    jp write_water_projectile_2xn
draw_current_splash_direct:
    ld de,tank_splash_sprite_0
    ld a,(tank_splash_timer)
    cp 6
    jr nc,draw_current_splash_table_ready
    ld de,tank_splash_sprite_1
draw_current_splash_table_ready:
    ld a,(tank_shell_x)
    srl a
    srl a
    srl a
    ld c,a
    ld a,(tank_shell_y)
    ld b,6
    jp write_water_sprite_2xn

draw_current_balloon_direct:
    ld a,(balloon_active)
    or a
    ret z
    ld a,(balloon_x)
    srl a
    srl a
    srl a
    ld c,a
    ld a,(balloon_y)
    ld b,20
    ld de,balloon_sprite
    jp write_water_sprite_2xn

draw_current_fuel_direct:
    ld a,(fuel_active)
    or a
    ret z
    ld a,(fuel_x)
    srl a
    srl a
    srl a
    ld c,a
    ld a,(fuel_y)
    ld b,32
    ld de,fuel_vertical_sprite
    jp write_water_sprite_1xn

draw_current_helicopter_direct:
    ld a,(helicopter_active)
    or a
    ret z
    ld de,helicopter_shift_table
    ld a,(helicopter_dir)
    cp 255
    jr nz,draw_current_helicopter_right
    ld de,helicopter_left_shift_table
    ld a,(helicopter_frame)
    or a
    jr z,draw_current_helicopter_table_ready
    ld de,helicopter_left_alt_shift_table
    jr draw_current_helicopter_table_ready
draw_current_helicopter_right:
    ld a,(helicopter_frame)
    or a
    jr z,draw_current_helicopter_table_ready
    ld de,helicopter_alt_shift_table
draw_current_helicopter_table_ready:
    ld a,(helicopter_x)
    ld c,a
    ld a,(helicopter_y)
    ld b,10
    jp write_water_sprite_shifted_2xn

draw_current_enemy_plane_direct:
    ld a,(enemy_plane_active)
    or a
    ret z
    ld a,(enemy_plane_x)
    ld c,a
    ld a,(enemy_plane_y)
    ld b,8
    ld de,enemy_plane_shift_table
    jp write_world_sprite_shifted_2xn

draw_current_shore_tank_direct:
    ld a,(tank_active)
    or a
    ret z
    ld de,tank_facing_right_sprite
    ld a,(tank_side)
    or a
    jr z,draw_current_shore_tank_table_ready
    ld de,tank_facing_left_sprite
draw_current_shore_tank_table_ready:
    ld a,(tank_x)
    srl a
    srl a
    srl a
    ld c,a
    ld a,(tank_y)
    ld b,10
    jp write_land_sprite_2xn

draw_current_bridge_tank_direct:
    ld a,(bridge_tank_active)
    or a
    ret z
    ld de,tank_right_shift_table
    ld a,(bridge_tank_side)
    or a
    jr z,draw_current_bridge_tank_table_ready
    ld de,tank_left_shift_table
draw_current_bridge_tank_table_ready:
    ld a,(bridge_tank_x)
    ld c,a
    ld a,(bridge_tank_y)
    ld b,10
#if TIMEX_HICOLOR
    push af
    ld a,(bridge_active)
    or a
    jr z,draw_current_bridge_tank_world
    pop af
    jp write_intact_bridge_tank_shifted_2xn
draw_current_bridge_tank_world:
    pop af
#else
    ; The standard road carries bitmap lines, so the crossing tank composes
    ; against the real queried background instead of assuming solid 0xff.
#endif
    jp write_world_sprite_shifted_2xn

draw_all_current_sprites_direct:
    call draw_current_bullet_direct
    call draw_current_shell_direct
    call draw_current_ships_direct
    call draw_current_balloon_direct
    call draw_current_fuel_direct
    call draw_current_enemy_plane_direct
    call draw_current_helicopter_direct
    call draw_current_shore_tank_direct
    call draw_current_bridge_tank_direct
    jp draw_current_player_direct

transition_player_direct:
    ; The player is fixed in Y. Keep its bitmap resident when X and the banked
    ; silhouette are unchanged; the final pass will then repair only rows that
    ; the dirty terrain renderer actually touched. A steering/pose change still
    ; restores the old rectangle and requests one complete redraw.
    xor a
    ld (player_full_redraw),a
    ld a,(crashed)
    or a
    jr nz,transition_player_cleanup
    ld a,(sprite_old_player_x)
    ld b,a
    ld a,(player_x)
    cp b
    jr nz,transition_player_changed
    ld a,(sprite_old_player_bank)
    ld b,a
    ld a,(player_bank)
    cp b
    ret z
transition_player_changed:
    ld a,1
    ld (player_full_redraw),a
transition_player_cleanup:
    ld a,(sprite_old_player_x)
    call prepare_transition_old_x_2
    ld a,(sprite_old_player_y)
    ld (transition_old_y),a
    ld a,(player_y)
    ld (transition_new_y),a
    ld a,(player_x)
    call prepare_transition_new_x_2
    ld a,(crashed)
    xor 1
    and 1
    ld (transition_new_active),a
    ld a,14
    ld (transition_height),a
    ld a,1
    ld (transition_background),a
    call cleanup_resident_sprite_delta
    ret

finish_player_transition_direct:
    ld a,(crashed)
    or a
    ret nz
    ld a,(player_full_redraw)
    or a
    jp nz,draw_current_player_direct

    ; Bridge/road writers are outside the eight-line course residue pass, but
    ; they touch the player only while their sixteen-row band actually overlaps
    ; it. A distant bridge must not force fourteen expensive world rows.
    ld a,(bridge_active)
    ld b,a
    ld a,(destroyed_road_active)
    or b
    jr z,player_bridge_band_clear
    ld a,(player_y)
    add a,14
    ld b,a                           ; player bottom exclusive
    ld a,(bridge_y)
    cp b
    jr nc,player_bridge_band_clear
    add a,16                         ; bridge/road bottom exclusive
    ld b,a
    ld a,(player_y)
    cp b
    jp c,draw_current_player_direct
player_bridge_band_clear:

    ; The depot redraws its scrolling column after the player transition, so
    ; while the two rectangles overlap the player must be composed again as
    ; the last writer: the aircraft covers FUEL, not the other way round.
    ld a,(fuel_active)
    or a
    jr z,player_fuel_band_clear
    ld a,(player_y)
    add a,14
    ld b,a                           ; player bottom exclusive
    ld a,(fuel_y)
    cp b
    jr nc,player_fuel_band_clear     ; depot fully below the player
    add a,32                         ; depot bottom exclusive
    ld b,a
    ld a,(player_y)
    cp b
    jr nc,player_fuel_band_clear     ; depot fully above the player
    ld a,(player_x)
    srl a
    srl a
    srl a
    ld b,a
    ld a,(fuel_x)
    srl a
    srl a
    srl a
    sub b                            ; depot column within the player triplet?
    cp 3
    jp c,draw_current_player_direct
player_fuel_band_clear:

    ld a,(speed_pixels)
    or a
    ret z
    jp draw_current_player_dirty_rows

draw_current_player_dirty_rows:
    ; Resolve the current pose and X shift once, then derive the two/four rows
    ; touched by render_dirty_rows directly from the current residue.
    ld de,player_shift_table
    ld a,(player_bank)
    or a
    jr z,player_dirty_pose_ready
    ld de,player_right_shift_table
    cp 255
    jr nz,player_dirty_pose_ready
    ld de,player_left_shift_table
player_dirty_pose_ready:
    ld a,(player_x)
    and 7
    add a,a
    ld l,a
    ld h,0
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (player_dirty_source_base),de

    ; Dirty screen rows have residues course_phase, course_phase-1 at speed 2.
    ; Convert those residues directly to offsets inside the fixed-Y player;
    ; each residue occurs at most twice in a fourteen-row sprite.
    ld a,(speed_pixels)
    ld (player_dirty_rows),a
    ld a,(course_phase)
    ld b,a
    ld a,(player_y)
    ld c,a
    ld a,b
    sub c
    and 7
    ld (player_dirty_row),a
player_dirty_row_loop:
    call draw_current_player_dirty_row

    ld a,(player_dirty_row)
    add a,8
    cp 14
    jr nc,player_dirty_second_row_done
    ld (player_dirty_row),a
    call draw_current_player_dirty_row
    ld a,(player_dirty_row)
    sub 8
    ld (player_dirty_row),a
player_dirty_second_row_done:
    ld a,(player_dirty_row)
    dec a
    and 7
    ld (player_dirty_row),a
    ld a,(player_dirty_rows)
    dec a
    ld (player_dirty_rows),a
    jr nz,player_dirty_row_loop
    ret

draw_current_player_dirty_row:
    ; Select this row inside the already shifted 3-byte pose cache.
    ld a,(player_dirty_row)
    ld l,a
    ld h,0
    ld e,a
    ld d,0
    add hl,hl
    add hl,de
    ld de,(player_dirty_source_base)
    add hl,de
    ld (world_source_ptr),hl

    ld a,(player_x)
    ld c,a
    and 7
    ld (world_write_spill),a
    ld a,c
    srl a
    srl a
    srl a
    ld (world_write_col),a
    ld a,(player_y)
    ld b,a
    ld a,(player_dirty_row)
    add a,b
    ld (world_write_y),a

    ld a,(world_write_col)
    ld c,a
    ld a,(world_write_y)
    call load_world_background_triplet

    ld hl,(world_source_ptr)
    ld a,(world_background_byte_0)
    xor (hl)
    ld (world_write_byte_0),a
    inc hl
    ld a,(world_background_byte_1)
    xor (hl)
    ld (world_write_byte_1),a
    inc hl
    ld a,(world_background_byte_2)
    xor (hl)
    ld (world_write_byte_2),a

    ld a,(world_write_y)
    call calc_screen_line_addr
    ld a,(world_write_col)
    add a,l
    ld l,a
    ld a,(world_write_byte_0)
    ld (hl),a
    inc l
    ld a,(world_write_byte_1)
    ld (hl),a
    ld a,(world_write_spill)
    or a
    ret z
    inc l
    ld a,(world_write_byte_2)
    ld (hl),a
    ret

transition_bullet_direct:
    ld a,(sprite_old_bullet_active)
    ld b,a
    ld a,(bullet_active)
    or b
    ret z
    xor a
    ld (transition_old_width),a
    ld a,(sprite_old_bullet_active)
    or a
    jr z,transition_bullet_old_ready
    ld a,(sprite_old_bullet_x)
    add a,7
    call prepare_transition_old_projectile_x
transition_bullet_old_ready:
    ld a,(sprite_old_bullet_y)
    ld (transition_old_y),a
    ld a,(bullet_y)
    ld (transition_new_y),a
    xor a
    ld (transition_new_width),a
    ld a,(bullet_active)
    ld (transition_new_active),a
    or a
    jr z,transition_bullet_new_ready
    ld a,(bullet_x)
    add a,7
    call prepare_transition_new_projectile_x
transition_bullet_new_ready:
    ld a,4
    ld (transition_height),a
    xor a
    ld (transition_background),a
    call cleanup_resident_sprite_delta
    jp draw_current_bullet_direct

transition_ship0_direct:
    ; Hot path: ship 0 changes only by the course scroll. Its complete old
    ; image remains resident, so replace the few departing top scanlines in
    ; one table-driven fill and overwrite the new final image once.
    ld a,(timex_bitmap_ship0_active)
    or a
    jr z,transition_ship0_spawned
    ld a,(ship0_active)
    or a
    jr z,transition_ship0_exception
    ld a,(speed_pixels)
    or a
    ret z
    ld b,a
    ld a,(timex_bitmap_ship0_x)
    ld c,a
    and 7
    ld d,4
    jr z,transition_ship0_width_ready
    inc d
transition_ship0_width_ready:
    ld a,c
    srl a
    srl a
    srl a
    ld c,a
    ld a,(timex_bitmap_ship0_y)
    ld e,0
    call fill_uniform_sprite_rect
    jp draw_current_ship0_direct
transition_ship0_spawned:
    jp draw_current_ship0_direct

transition_ship0_exception:
    xor a
    ld (transition_old_width),a
    ld a,(timex_bitmap_ship0_active)
    or a
    jr z,transition_ship0_old_ready
    ld a,(timex_bitmap_ship0_x)
    call prepare_transition_old_x_4
transition_ship0_old_ready:
    ld a,(timex_bitmap_ship0_y)
    ld (transition_old_y),a
    ld a,(ship0_y)
    ld (transition_new_y),a
    xor a
    ld (transition_new_width),a
    ld a,(ship0_active)
    ld (transition_new_active),a
    or a
    jr z,transition_ship0_new_ready
    ld a,(ship0_x)
    call prepare_transition_new_x_4
transition_ship0_new_ready:
    ld a,8
    ld (transition_height),a
    xor a
    ld (transition_background),a
    jp cleanup_resident_sprite_delta

transition_ship1_direct:
    ; Regular patrol: Y advances by speed_pixels and X by at most one pixel.
    ; Clear the top strip in one blit. A side byte leaves the footprint only
    ; on a rightward 7->0 byte-boundary crossing; all other old bytes are
    ; overwritten by the new five-byte cached row.
    ld a,(timex_bitmap_ship1_active)
    or a
    jp z,transition_ship1_spawned
    ld a,(ship1_active)
    or a
    jp z,transition_ship1_exception

    ld a,(speed_pixels)
    or a
    jr z,transition_ship1_check_side
    ld b,a
    ld a,(timex_bitmap_ship1_x)
    ld c,a
    and 7
    ld d,4
    jr z,transition_ship1_top_width_ready
    inc d
transition_ship1_top_width_ready:
    ld a,c
    srl a
    srl a
    srl a
    ld c,a
    ld a,(timex_bitmap_ship1_y)
    ld e,0
    call fill_uniform_sprite_rect

transition_ship1_check_side:
    ld a,(timex_bitmap_ship1_x)
    ld b,a
    ld a,(ship1_x)
    cp b
    jr c,transition_ship1_moved_left
    jr z,transition_ship1_maybe_unchanged
    srl a
    srl a
    srl a
    ld c,a
    ld a,b
    srl a
    srl a
    srl a
    cp c
    jr z,transition_ship1_draw
    ld c,a
    ld a,(timex_bitmap_ship1_y)
    ld b,8
    ld d,1
    ld e,0
    call fill_uniform_sprite_rect
    jr transition_ship1_draw

transition_ship1_moved_left:
    ; At old shift 1 -> new shift 0 the five-byte shifted footprint contracts
    ; to four bytes without changing its left byte column. Clear the departing
    ; right spill byte; otherwise its last 2-3 set pixels remain as black marks
    ; behind the inverse/left-facing ship.
    ld a,b
    and 7
    cp 1
    jr nz,transition_ship1_draw
    ld a,b
    srl a
    srl a
    srl a
    add a,4
    ld c,a
    ld a,(timex_bitmap_ship1_y)
    ld b,8
    ld d,1
    ld e,0
    call fill_uniform_sprite_rect
    jr transition_ship1_draw

transition_ship1_maybe_unchanged:
    ld a,(speed_pixels)
    or a
    jr nz,transition_ship1_draw
    ld a,(sprite_old_ship1_dir)
    ld b,a
    ld a,(ship1_dir)
    cp b
    ret z
transition_ship1_draw:
    jp draw_current_ship1_direct
transition_ship1_spawned:
    jp draw_current_ship1_direct

transition_ship1_exception:
    xor a
    ld (transition_old_width),a
    ld a,(timex_bitmap_ship1_active)
    or a
    jr z,transition_ship1_old_ready
    ld a,(timex_bitmap_ship1_x)
    call prepare_transition_old_x_4
transition_ship1_old_ready:
    ld a,(timex_bitmap_ship1_y)
    ld (transition_old_y),a
    ld a,(ship1_y)
    ld (transition_new_y),a
    xor a
    ld (transition_new_width),a
    ld a,(ship1_active)
    ld (transition_new_active),a
    or a
    jr z,transition_ship1_new_ready
    ld a,(ship1_x)
    call prepare_transition_new_x_4
transition_ship1_new_ready:
    ld a,8
    ld (transition_height),a
    xor a
    ld (transition_background),a
    jp cleanup_resident_sprite_delta

transition_balloon_direct:
    ; Byte-aligned, fixed-X world actor: ordinary frames need only the newly
    ; exposed top rows. A zero-speed slow phase performs no bitmap work.
    ld a,(timex_attr_balloon_active)
    or a
    jr z,transition_balloon_spawned
    ld a,(balloon_active)
    or a
    jr z,transition_balloon_exception
    ld a,(speed_pixels)
    or a
    ret z
    ld b,a
    ld a,(timex_attr_balloon_x)
    srl a
    srl a
    srl a
    ld c,a
    ld d,2
    ld e,0
    ld a,(timex_attr_balloon_y)
    call fill_uniform_sprite_rect
    jp draw_current_balloon_direct
transition_balloon_spawned:
    jp draw_current_balloon_direct

transition_balloon_exception:
    xor a
    ld (transition_old_width),a
    ld a,(timex_attr_balloon_active)
    or a
    jr z,transition_balloon_old_ready
    ld a,2
    ld (transition_old_width),a
transition_balloon_old_ready:
    ld a,(timex_attr_balloon_x)
    srl a
    srl a
    srl a
    ld (transition_old_col),a
    ld a,(timex_attr_balloon_y)
    ld (transition_old_y),a
    ld a,(balloon_y)
    ld (transition_new_y),a
    ld a,(balloon_x)
    srl a
    srl a
    srl a
    ld (transition_new_col),a
    ld a,2
    ld (transition_new_width),a
    ld a,(balloon_active)
    ld (transition_new_active),a
    ld a,20
    ld (transition_height),a
    xor a
    ld (transition_background),a
    call cleanup_resident_sprite_delta
    jp draw_current_balloon_direct

transition_fuel_direct:
    ; The 32-line depot is the most profitable fixed-X case: never run the
    ; generic rectangle-intersection engine while it merely scrolls down.
    ld a,(timex_attr_fuel_active)
    or a
    jr z,transition_fuel_spawned
    ld a,(fuel_active)
    or a
    jr z,transition_fuel_exception
    ld a,(speed_pixels)
    or a
    ret z
    ld b,a
    ld a,(timex_attr_fuel_x)
    srl a
    srl a
    srl a
    ld c,a
    ld d,1
    ld e,0
    ld a,(timex_attr_fuel_y)
    call fill_uniform_sprite_rect
    jp draw_current_fuel_direct
transition_fuel_spawned:
    jp draw_current_fuel_direct

transition_fuel_exception:
    xor a
    ld (transition_old_width),a
    ld a,(timex_attr_fuel_active)
    or a
    jr z,transition_fuel_old_ready
    ld a,1
    ld (transition_old_width),a
transition_fuel_old_ready:
    ld a,(timex_attr_fuel_x)
    srl a
    srl a
    srl a
    ld (transition_old_col),a
    ld a,(timex_attr_fuel_y)
    ld (transition_old_y),a
    ld a,(fuel_y)
    ld (transition_new_y),a
    ld a,(fuel_x)
    srl a
    srl a
    srl a
    ld (transition_new_col),a
    ld a,1
    ld (transition_new_width),a
    ld a,(fuel_active)
    ld (transition_new_active),a
    ld a,32
    ld (transition_height),a
    xor a
    ld (transition_background),a
    call cleanup_resident_sprite_delta
    jp draw_current_fuel_direct

transition_helicopter_direct:
    ; The helicopter also moves by at most one horizontal pixel. Rotor changes
    ; still force the final write, but they do not require background cleanup.
    ld a,(timex_attr_helicopter_active)
    or a
    jp z,transition_helicopter_spawned
    ld a,(helicopter_active)
    or a
    jp z,transition_helicopter_exception

    ld a,(speed_pixels)
    or a
    jr z,transition_helicopter_check_side
    ld b,a
    ld a,(timex_attr_helicopter_x)
    ld c,a
    and 7
    ld d,2
    jr z,transition_helicopter_top_width_ready
    inc d
transition_helicopter_top_width_ready:
    ld a,c
    srl a
    srl a
    srl a
    ld c,a
    ld a,(timex_attr_helicopter_y)
    ld e,0
    call fill_uniform_sprite_rect

transition_helicopter_check_side:
    ld a,(timex_attr_helicopter_x)
    ld b,a
    ld a,(helicopter_x)
    cp b
    jr c,transition_helicopter_moved_left
    jr z,transition_helicopter_check_visual
    srl a
    srl a
    srl a
    ld c,a
    ld a,b
    srl a
    srl a
    srl a
    cp c
    jr z,transition_helicopter_draw
    ld c,a
    ld a,(timex_attr_helicopter_y)
    ld b,10
    ld d,1
    ld e,0
    call fill_uniform_sprite_rect
    jr transition_helicopter_draw

transition_helicopter_moved_left:
    ; Same contracting-footprint case as the patrolling ship: shift 1 uses a
    ; third byte, while the following aligned frame writes only two bytes.
    ld a,b
    and 7
    cp 1
    jr nz,transition_helicopter_draw
    ld a,b
    srl a
    srl a
    srl a
    add a,2
    ld c,a
    ld a,(timex_attr_helicopter_y)
    ld b,10
    ld d,1
    ld e,0
    call fill_uniform_sprite_rect
    jr transition_helicopter_draw

transition_helicopter_check_visual:
    ld a,(speed_pixels)
    or a
    jr nz,transition_helicopter_draw
    ld a,(sprite_old_helicopter_frame)
    ld b,a
    ld a,(helicopter_frame)
    cp b
    jr nz,transition_helicopter_draw
    ld a,(sprite_old_helicopter_dir)
    ld b,a
    ld a,(helicopter_dir)
    cp b
    ret z
transition_helicopter_draw:
    jp draw_current_helicopter_direct
transition_helicopter_spawned:
    jp draw_current_helicopter_direct

transition_helicopter_exception:
    xor a
    ld (transition_old_width),a
    ld a,(timex_attr_helicopter_active)
    or a
    jr z,transition_helicopter_old_ready
    ld a,(timex_attr_helicopter_x)
    call prepare_transition_old_x_2
transition_helicopter_old_ready:
    ld a,(timex_attr_helicopter_y)
    ld (transition_old_y),a
    ld a,(helicopter_y)
    ld (transition_new_y),a
    xor a
    ld (transition_new_width),a
    ld a,(helicopter_active)
    ld (transition_new_active),a
    or a
    jr z,transition_helicopter_new_ready
    ld a,(helicopter_x)
    call prepare_transition_new_x_2
transition_helicopter_new_ready:
    ld a,10
    ld (transition_height),a
    xor a
    ld (transition_background),a
    call cleanup_resident_sprite_delta
    jp draw_current_helicopter_direct

transition_enemy_plane_direct:
    ; The crossing plane always travels right by three pixels. Its old left
    ; world byte leaves only when that step crosses an 8px boundary; restore
    ; that column and the scrolling top strip without general intersections.
    ld a,(sprite_old_enemy_active)
    or a
    jr z,transition_enemy_spawned
    ld a,(enemy_plane_active)
    or a
    jr z,transition_enemy_exception

    ld a,(speed_pixels)
    or a
    jr z,transition_enemy_check_side
    ld c,a                          ; row count
    ld a,(sprite_old_enemy_x)
    ld d,a
    and 7
    ld e,2
    jr z,transition_enemy_top_width_ready
    inc e
transition_enemy_top_width_ready:
    ld a,d
    srl a
    srl a
    srl a
    ld d,a                          ; old byte column
    ld a,(sprite_old_enemy_y)
    ld b,a
    call fill_world_background_rect

transition_enemy_check_side:
    ld a,(sprite_old_enemy_x)
    ld b,a
    srl a
    srl a
    srl a
    ld d,a                          ; old column
    ld a,(enemy_plane_x)
    srl a
    srl a
    srl a
    cp d
    jr z,transition_enemy_draw
    jr c,transition_enemy_wrapped   ; X wrapped from the right edge to zero
    ld a,(sprite_old_enemy_y)
    ld b,a
    ld c,8
    ld e,1
    call fill_world_background_rect
transition_enemy_draw:
    jp draw_current_enemy_plane_direct
transition_enemy_spawned:
    jp draw_current_enemy_plane_direct
transition_enemy_wrapped:
    ; The whole old footprint leaves at once, not just one column. Repaint
    ; its full two-or-three byte width with the world background, or the
    ; right screen edge keeps a slice of the aircraft.
    ld a,b                          ; old X, still held in B
    and 7
    ld e,2
    jr z,transition_enemy_wrap_width_ready
    inc e
transition_enemy_wrap_width_ready:
    ld a,(sprite_old_enemy_y)
    ld b,a
    ld c,8
    call fill_world_background_rect
    jr transition_enemy_draw

transition_enemy_exception:
    xor a
    ld (transition_old_width),a
    ld a,(sprite_old_enemy_active)
    or a
    jr z,transition_enemy_old_ready
    ld a,(sprite_old_enemy_x)
    call prepare_transition_old_x_2
transition_enemy_old_ready:
    ld a,(sprite_old_enemy_y)
    ld (transition_old_y),a
    ld a,(enemy_plane_y)
    ld (transition_new_y),a
    xor a
    ld (transition_new_width),a
    ld a,(enemy_plane_active)
    ld (transition_new_active),a
    or a
    jr z,transition_enemy_new_ready
    ld a,(enemy_plane_x)
    call prepare_transition_new_x_2
transition_enemy_new_ready:
    ld a,8
    ld (transition_height),a
    ld a,1
    ld (transition_background),a
    call cleanup_resident_sprite_delta
    jp draw_current_enemy_plane_direct

transition_shore_tank_direct:
    ; The ordinary bank tank has a fixed byte column for its lifetime. Restore
    ; only the departing land rows, then write its cut-out at the new Y.
    ld a,(timex_attr_tank_active)
    or a
    jr z,transition_shore_tank_spawned
    ld a,(tank_active)
    or a
    jr z,transition_shore_tank_exception
    ld a,(speed_pixels)
    or a
    ret z
    ld b,a
    ld a,(timex_attr_tank_x)
    srl a
    srl a
    srl a
    ld c,a
    ld d,2
    ld e,255
    ld a,(timex_attr_tank_y)
    call fill_uniform_sprite_rect
    jp draw_current_shore_tank_direct
transition_shore_tank_spawned:
    jp draw_current_shore_tank_direct

transition_shore_tank_exception:
    xor a
    ld (transition_old_width),a
    ld a,(timex_attr_tank_active)
    or a
    jr z,transition_shore_tank_old_ready
    ld a,2
    ld (transition_old_width),a
transition_shore_tank_old_ready:
    ld a,(timex_attr_tank_x)
    srl a
    srl a
    srl a
    ld (transition_old_col),a
    ld a,(timex_attr_tank_y)
    ld (transition_old_y),a
    ld a,(tank_y)
    ld (transition_new_y),a
    ld a,(tank_x)
    srl a
    srl a
    srl a
    ld (transition_new_col),a
    ld a,2
    ld (transition_new_width),a
    ld a,(tank_active)
    ld (transition_new_active),a
    ld a,10
    ld (transition_height),a
    ld a,1
    ld (transition_background),a
    call cleanup_resident_sprite_delta
    jp draw_current_shore_tank_direct

transition_bridge_tank_direct:
    ld a,(sprite_old_bridge_tank_active)
    ld b,a
    ld a,(bridge_tank_active)
    or b
    ret z
    xor a
    ld (transition_old_width),a
    ld a,(sprite_old_bridge_tank_active)
    or a
    jr z,transition_bridge_tank_old_ready
    ld a,(sprite_old_bridge_tank_x)
    call prepare_transition_old_x_2
transition_bridge_tank_old_ready:
    ld a,(sprite_old_bridge_tank_y)
    ld (transition_old_y),a
    ld a,(bridge_tank_y)
    ld (transition_new_y),a
    xor a
    ld (transition_new_width),a
    ld a,(bridge_tank_active)
    ld (transition_new_active),a
    or a
    jr z,transition_bridge_tank_new_ready
    ld a,(bridge_tank_x)
    call prepare_transition_new_x_2
transition_bridge_tank_new_ready:
    ld a,10
    ld (transition_height),a
    ld a,1
    ld (transition_background),a
    call cleanup_resident_sprite_delta
    jp draw_current_bridge_tank_direct

prepare_old_shell_geometry:
    xor a
    ld (transition_old_width),a
    ld a,(sprite_old_shell_active)
    or a
    ret z
    cp 1
    jr nz,prepare_old_splash_geometry
    ld a,(sprite_old_shell_x)
    call prepare_transition_old_projectile_x
    ld a,2
    ld (transition_height),a
    ret
prepare_old_splash_geometry:
    ld a,(sprite_old_shell_x)
    srl a
    srl a
    srl a
    ld (transition_old_col),a
    ld a,2
    ld (transition_old_width),a
    ld a,6
    ld (transition_height),a
    ret

prepare_new_shell_geometry:
    xor a
    ld (transition_new_width),a
    ld a,(tank_shell_active)
    ld (transition_new_active),a
    or a
    ret z
    cp 1
    jr nz,prepare_new_splash_geometry
    ld a,(tank_shell_x)
    call prepare_transition_new_projectile_x
    ld a,2
    ld (transition_height),a
    ret
prepare_new_splash_geometry:
    ld a,(tank_shell_x)
    srl a
    srl a
    srl a
    ld (transition_new_col),a
    ld a,2
    ld (transition_new_width),a
    ld a,6
    ld (transition_height),a
    ret

transition_shell_direct:
    ld a,(sprite_old_shell_active)
    ld b,a
    ld a,(tank_shell_active)
    or b
    ret z
    call prepare_old_shell_geometry
    ld a,(sprite_old_shell_y)
    ld (transition_old_y),a
    ld a,(tank_shell_y)
    ld (transition_new_y),a
    xor a
    ld (transition_background),a

    ; Projectile -> splash changes both height and representation. Restore the
    ; old tiny footprint, then write the new splash directly; there is no
    ; reason to force unlike rectangles through the overlap calculation.
    ld a,(sprite_old_shell_active)
    ld b,a
    ld a,(tank_shell_active)
    cp b
    jr z,transition_shell_same_kind
    xor a
    ld (transition_new_active),a
    call cleanup_resident_sprite_delta
    jp draw_current_shell_direct
transition_shell_same_kind:
    ; A flying shell is at most two bytes on two rows and always sits over
    ; water, so restore its old footprint with direct zero writes and redraw.
    ; The general rectangle-overlap engine stays for the taller splash and
    ; for the projectile<->splash change handled above.
    ld a,(tank_shell_active)
    cp 1
    jr nz,transition_shell_general
    ld a,(transition_old_y)
    ld b,a
    call restore_flying_shell_row
    ld a,(transition_old_y)
    inc a
    ld b,a
    call restore_flying_shell_row
    jp draw_current_shell_direct
transition_shell_general:
    call prepare_new_shell_geometry
    call cleanup_resident_sprite_delta
    jp draw_current_shell_direct

restore_flying_shell_row:
    ; B = scanline of the old flying-shell image. Rows inside an intact
    ; bridge band belong to the bridge writer and are skipped, exactly like
    ; fill_water_rect_preserve_bridge.
    ld a,(bridge_active)
    or a
    jr z,restore_flying_shell_clip
    ld a,(bridge_y)
    ld c,a
    ld a,b
    cp c
    jr c,restore_flying_shell_clip
    ld a,c
    add a,16
    cp b
    jr c,restore_flying_shell_clip
    jr z,restore_flying_shell_clip
    ret
restore_flying_shell_clip:
    ld a,b
    cp PLAYFIELD_BOTTOM
    ret nc
    call calc_screen_line_addr
    ld a,(transition_old_col)
    add a,l
    ld l,a
    xor a
    ld (hl),a
    ld a,(transition_old_width)
    cp 2
    ret c
    inc l
    xor a
    ld (hl),a
    ret

transition_all_resident_sprites:
    ; Common bitmap engine for Spectrum and Timex. The bridge/world layer has
    ; already finished, so every call below stores the final visible bytes.
    call transition_player_direct
    call transition_bullet_direct
    call transition_shell_direct
    call transition_ship0_direct
    call transition_ship1_direct
    call transition_balloon_direct
    call transition_fuel_direct
    call transition_enemy_plane_direct
    call transition_helicopter_direct
    call transition_shore_tank_direct
    call transition_bridge_tank_direct
    jp finish_player_transition_direct

xor_crash_explosion:
    ; The crash scene is otherwise frozen. Keeping this primitive separate
    ; lets crash_wait_frame replace only the 13-row animation every fifth
    ; frame instead of erasing and redrawing every actor on all 75 frames.
    ld de,explosion_0_shift_table
    ld a,(explosion_frame)
    or a
    jr z,xor_explosion_table_ready
    ld de,explosion_1_shift_table
    cp 1
    jr z,xor_explosion_table_ready
    ld de,explosion_2_shift_table
xor_explosion_table_ready:
    ld a,(player_x)
    ld c,a
    ld a,(player_y)
    ld b,13
    jp xor_sprite_shifted_2xn

xor_current_hit_explosion:
    ; Explosions deliberately keep the old XOR effect. Unlike ordinary sprites,
    ; this routine is called once to remove the old phase and once to add the
    ; new phase; no terrain or actor is routed through it.
    ld a,(hit_explosion_active)
    or a
    ret z
    ld de,explosion_0_shift_table
    ld a,(hit_explosion_frame)
    or a
    jr z,hit_explosion_table_ready
    ld de,explosion_1_shift_table
    cp 1
    jr z,hit_explosion_table_ready
    ld de,explosion_2_shift_table
hit_explosion_table_ready:
    ld a,(hit_explosion_x)
    ld c,a
    ld a,(hit_explosion_y)
    ld b,13
    jp xor_sprite_shifted_2xn

xor_sprite_shifted_2xn:
    ; Input A=Y, C=pixel X (0..240), B=height, DE=eight-pointer shift table.
    ; Every cached row is already a three-byte 24-bit shifted pattern, making
    ; the blit cost constant instead of repeating up to seven rotations.
    cp 192
    ret nc
    ld l,a
    ld a,192
    sub l
    ld h,a
    ld a,b
    cp h
    jr c,shifted_rows_ready
    jr z,shifted_rows_ready
    ld b,h
shifted_rows_ready:
    ; Preserve Y while HL is borrowed to index the selected shift pointer.
    ; Losing this value made X&7 masquerade as Y, pinning sprites near the top
    ; and making sideways motion look like vertical jumps.
    ld a,l
    ex af,af'
    ld a,c
    and 7
    add a,a
    ld l,a
    ld h,0
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,c
    srl a
    srl a
    srl a
    ld c,a

    ex af,af'
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,shifted_table_page_ready
    inc h
shifted_table_page_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
shifted_sprite_row:
    pop hl
    ld a,c
    add a,l
    ld l,a

    ld a,(de)
    xor (hl)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    xor (hl)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    xor (hl)
    ld (hl),a
    inc de

    djnz shifted_sprite_row
    ld sp,(sprite_saved_sp)
    ei
    ret

fill_uniform_sprite_rect:
    ; Input A=Y, B=height, C=byte column, D=width, E=literal background.
    ; Used only where gameplay placement guarantees all-water or all-land bytes.
    push af
    ld a,b
    or a
    jr z,uniform_rect_empty
    ld a,d
    or a
    jr z,uniform_rect_empty
    pop af
    cp PLAYFIELD_BOTTOM
    ret nc
    ld l,a
    ld a,PLAYFIELD_BOTTOM
    sub l
    ld h,a
    ld a,b
    cp h
    jr c,uniform_rect_rows_ready
    jr z,uniform_rect_rows_ready
    ld b,h
uniform_rect_rows_ready:
    ld a,b
    ld (sprite_fill_rows),a
    ld a,d
    ld (sprite_fill_width),a
    ld a,e
    ld (sprite_fill_value),a
    ld a,l
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,uniform_rect_table_ready
    inc h
uniform_rect_table_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
uniform_rect_row:
    pop hl
    ld a,l
    add a,c
    ld l,a
    ld a,(sprite_fill_width)
    ld b,a
    ld a,(sprite_fill_value)
uniform_rect_byte:
    ld (hl),a
    inc l
    djnz uniform_rect_byte
    ld a,(sprite_fill_rows)
    dec a
    ld (sprite_fill_rows),a
    jr nz,uniform_rect_row
    ld sp,(sprite_saved_sp)
    ei
    ret
uniform_rect_empty:
    pop af
    ret

get_world_background_byte:
    ; Input A=Y, C=bitmap byte column. Terrain plus the FUEL depot overlay:
    ; the depot belongs to the background model, so sprites composed or
    ; restored over its column keep the depot body instead of punching
    ; water-coloured holes into it. The player therefore covers FUEL.
    call get_world_terrain_byte
    ld e,a
    ld a,(fuel_active)
    or a
    jr z,world_background_overlay_done
    ld a,(fuel_x)
    srl a
    srl a
    srl a
    ld b,a
    ld a,(background_query_col)
    cp b
    jr nz,world_background_overlay_done
    ld a,(fuel_y)
    ld b,a
    ld a,(background_query_y)
    sub b
    cp 32
    jr nc,world_background_overlay_done
    ld hl,fuel_vertical_sprite
    add a,l
    ld l,a
    jr nc,world_background_overlay_row
    inc h
world_background_overlay_row:
    ld a,(hl)
    or e
    ret
world_background_overlay_done:
    ld a,e
    ret

get_world_terrain_byte:
    ; Input A=Y, C=bitmap byte column. Return the world bitmap byte without any
    ; sprites. This pure query lets crossing actors be written directly over
    ; water, banks or the bridge instead of toggling the visible framebuffer.
    ld (background_query_y),a
    ld a,c
    ld (background_query_col),a
    ld a,(background_query_y)
    cp 16
    jr c,world_background_water
    cp PLAYFIELD_BOTTOM
    jr nc,world_background_water

#if TIMEX_HICOLOR
    ; An intact bridge/road is the lower world layer: sixteen solid rows
    ; with no centre marking.
    ld a,(bridge_active)
    or a
    jr z,world_background_course
    ld a,(bridge_y)
    ld b,a
    ld a,(background_query_y)
    cp b
    jr c,world_background_course
    sub b
    cp 16
    jr nc,world_background_course
    ld a,255
    ret
#else
    ; Standard build: the road look lives in the bitmap, so the band model
    ; includes it: solid black edge lines at band rows 1/14, over the land
    ; approaches only. A destroyed road keeps its lines while its former
    ; span is ordinary water served by the course model.
    ld a,(bridge_active)
    ld b,a
    ld a,(destroyed_road_active)
    or b
    jr z,world_background_course
    ld a,(bridge_y)
    ld b,a
    ld a,(background_query_y)
    cp b
    jr c,world_background_course
    sub b
    cp 16
    jr nc,world_background_course
    cp 1
    jp z,world_background_band_edge
    cp 14
    jp z,world_background_band_edge
world_background_band_solid:
    ld a,(bridge_active)
    or a
    jp z,world_background_course    ; destroyed road: course model serves it
    ld a,255
    ret
#endif

world_background_course:
    call resolve_course_block_index
    ld b,a
    ld a,(background_query_col)
    ld c,a
    ld a,b
    call block_bitmap_address
    ld a,(hl)
    ret

world_background_water:
    xor a
    ret

#if not TIMEX_HICOLOR
world_background_band_edge:
    ld a,(background_query_col)
    ld c,a
    call standard_band_edge_byte
    or a
    ret z                           ; a black line byte over the approach
    jr world_background_band_solid  ; span column: solid road or water

standard_band_edge_byte:
    ; Input C=byte column. A=0 over a land approach, 255 over the span.
    ld a,(bridge_col)
    ld b,a
    ld a,c
    cp b
    jr c,standard_band_edge_line
    ld a,(bridge_width)
    add a,b
    ld b,a
    ld a,c
    cp b
    jr c,standard_band_edge_solid
standard_band_edge_line:
    xor a
    ret
standard_band_edge_solid:
    ld a,255
    ret
#endif

resolve_course_block_index:
    ; background_query_y -> A = course block index through the row cache.
    ; The per-row sprite writers walk Y sequentially, and a block spans eight
    ; scanlines, so a Y+1 query usually stays in the cached block and skips
    ; the full circular-index computation.
    ld a,(background_query_y)
    ld b,a
    ld a,(background_cache_y)
    cp b
    jr z,resolve_block_cached
    inc a
    cp b
    jr nz,resolve_block_recompute
    ld a,(background_cache_rows_left)
    dec a
    jr z,resolve_block_recompute    ; Y+1 starts the next block
    ld (background_cache_rows_left),a
    ld a,b
    ld (background_cache_y),a
resolve_block_cached:
    ld a,(background_cache_index)
    ret
resolve_block_recompute:
    ; get_block_index_for_y clobbers B and C; reload Y from the query slot.
    ld a,b
    call get_block_index_for_y
    ld a,l
    ld (background_cache_index),a
    ld a,(course_phase)
    ld c,a
    ld a,(background_query_y)
    add a,7
    sub c
    and 7
    ld c,a
    ld a,8
    sub c
    ld (background_cache_rows_left),a
    ld a,(background_query_y)
    ld (background_cache_y),a
    ld a,(background_cache_index)
    ret

load_world_background_triplet:
    ; Input A=Y, C=first byte column; preserves DE. Terrain triplet plus the
    ; FUEL depot overlay (same layering as get_world_background_byte).
    call load_world_terrain_triplet
    ld a,(fuel_active)
    or a
    ret z
    ld a,(background_query_col)
    ld b,a
    ld a,(fuel_x)
    srl a
    srl a
    srl a
    sub b                            ; depot column relative to the triplet
    cp 3
    ret nc
    ld c,a
    ld a,(fuel_y)
    ld b,a
    ld a,(background_query_y)
    sub b
    cp 32
    ret nc
    ld hl,fuel_vertical_sprite
    add a,l
    ld l,a
    jr nc,triplet_overlay_row_ready
    inc h
triplet_overlay_row_ready:
    ld b,(hl)                        ; depot row byte
    ld hl,world_background_byte_0
    ld a,c
    add a,l
    ld l,a                           ; the three triplet slots are consecutive
    jr nc,triplet_overlay_slot_ready
    inc h
triplet_overlay_slot_ready:
    ld a,(hl)
    or b
    ld (hl),a
    ret

load_world_terrain_triplet:
    ; Input A=Y, C=first byte column. Materialize three adjacent background
    ; bytes for the mixed-terrain sprite writers. One bridge test and one
    ; block lookup replace three complete get_world_background_byte calls.
    ld (background_query_y),a
    ld a,c
    ld (background_query_col),a
    ld a,(background_query_y)
    cp 16
    jp c,world_triplet_water
    cp PLAYFIELD_BOTTOM
    jp nc,world_triplet_water

#if TIMEX_HICOLOR
    ld a,(bridge_active)
    or a
    jr z,world_triplet_course
    ld a,(bridge_y)
    ld b,a
    ld a,(background_query_y)
    cp b
    jr c,world_triplet_course
    sub b
    cp 16
    jr nc,world_triplet_course
    ld a,255
    ld (world_background_byte_0),a
    ld (world_background_byte_1),a
    ld (world_background_byte_2),a
    ret
#else
    ; Standard band model with road lines: build the base triplet (solid for
    ; an intact band, course bytes for a destroyed road), then overlay black
    ; line bytes on approach columns of the four marking rows.
    ld a,(bridge_active)
    ld b,a
    ld a,(destroyed_road_active)
    or b
    jp z,world_triplet_course
    ld a,(bridge_y)
    ld b,a
    ld a,(background_query_y)
    cp b
    jp c,world_triplet_course
    sub b
    cp 16
    jp nc,world_triplet_course
    ld (band_row_scratch),a
    ld a,(bridge_active)
    or a
    jr z,world_triplet_band_course_base
    ld a,255
    ld (world_background_byte_0),a
    ld (world_background_byte_1),a
    ld (world_background_byte_2),a
    jr world_triplet_band_overlay
world_triplet_band_course_base:
    call world_triplet_course
world_triplet_band_overlay:
    ld a,(band_row_scratch)
    cp 1
    jr z,world_triplet_overlay_edge
    cp 14
    jr z,world_triplet_overlay_edge
    ret
world_triplet_overlay_edge:
    ld a,(background_query_col)
    ld c,a
    call world_triplet_overlay_byte_0
    ld a,(background_query_col)
    inc a
    ld c,a
    call world_triplet_overlay_byte_1
    ld a,(background_query_col)
    add a,2
    ld c,a
world_triplet_overlay_byte_2:
    call standard_band_edge_byte
    or a
    ret nz                          ; span column keeps its base byte
    ld (world_background_byte_2),a
    ret
world_triplet_overlay_byte_0:
    call standard_band_edge_byte
    or a
    ret nz
    ld (world_background_byte_0),a
    ret
world_triplet_overlay_byte_1:
    call standard_band_edge_byte
    or a
    ret nz
    ld (world_background_byte_1),a
    ret
#endif

world_triplet_course:
    call resolve_course_block_index
    ld b,a
    ; Pure open water is the common case under the player: when all three
    ; columns lie strictly between the bank edge bytes of an island-free
    ; block, the triplet is three zeros without touching the block bitmap.
    ld l,a
    ld h,HIGH(block_island_left)
    ld a,(hl)
    inc a                           ; 255 means no island
    jr nz,world_triplet_course_mixed
    ld h,HIGH(block_left_col)
    ld a,(background_query_col)
    ld c,a
    ld a,(hl)
    cp c
    jr nc,world_triplet_course_mixed ; touches the left edge byte or land
    ld h,HIGH(block_right_col)
    ld a,c
    add a,2
    cp (hl)
    jr nc,world_triplet_course_mixed ; touches the right edge byte or land
    xor a
    ld (world_background_byte_0),a
    ld (world_background_byte_1),a
    ld (world_background_byte_2),a
    ret
world_triplet_course_mixed:
    ld a,(background_query_col)
    ld c,a
    ld a,b
    call block_bitmap_address
    ld a,(hl)
    ld (world_background_byte_0),a
    inc hl
    ld a,(hl)
    ld (world_background_byte_1),a
    inc hl
    ld a,(hl)
    ld (world_background_byte_2),a
    ret

world_triplet_water:
    xor a
    ld (world_background_byte_0),a
    ld (world_background_byte_1),a
    ld (world_background_byte_2),a
    ret

reset_world_background_cache:
    ld a,255
    ld (background_cache_y),a
    ret

fill_world_background_rect:
    ; Input B=Y, C=rows, D=column, E=width. Reconstruct only exposed bytes of
    ; a sprite which may cross mixed terrain; never repaint an entire row.
    ; Course rows are straight copies of the materialized block rows; only
    ; road-band rows keep the per-byte query engine, and the off-playfield
    ; margins are plain water zeroes. The old all-byte engine dominated the
    ; overrun frames of every bridge board carrying any sprite.
    ld a,c
    or a
    ret z
    ld a,e
    or a
    ret z
    ld a,b
    ld (transition_fill_y),a
    ld a,c
    ld (transition_fill_rows),a
    ld a,d
    ld (transition_fill_col),a
    ld a,e
    ld (transition_fill_width),a
fill_world_background_row:
    ld a,(transition_fill_y)
    cp 16
    jr c,fill_world_row_zero
    cp PLAYFIELD_BOTTOM
    jr nc,fill_world_row_zero
#if TIMEX_HICOLOR
    ld a,(bridge_active)
    or a
    jr z,fill_world_row_fast
#else
    ld a,(bridge_active)
    ld b,a
    ld a,(destroyed_road_active)
    or b
    jr z,fill_world_row_fast
#endif
    ld a,(bridge_y)
    ld b,a
    ld a,(transition_fill_y)
    cp b
    jr c,fill_world_row_fast
    sub b
    cp 16
    jr c,fill_world_row_slow
fill_world_row_fast:
    ld a,(transition_fill_y)
    ld (background_query_y),a
    call resolve_course_block_index
    ld b,a
    ld a,(transition_fill_col)
    ld c,a
    ld a,b
    call block_bitmap_address
    push hl
    ld a,(transition_fill_y)
    call calc_screen_line_addr
    ld a,(transition_fill_col)
    add a,l
    ld e,a
    ld d,h
    pop hl
    ld a,(transition_fill_width)
    ld b,a
fill_world_fast_byte:
    ld a,(hl)
    ld (de),a
    inc l
    inc e
    djnz fill_world_fast_byte
    jr fill_world_row_next
fill_world_row_zero:
    ld a,(transition_fill_y)
    call calc_screen_line_addr
    ld a,(transition_fill_col)
    add a,l
    ld l,a
    ld a,(transition_fill_width)
    ld b,a
    xor a
fill_world_zero_byte:
    ld (hl),a
    inc l
    djnz fill_world_zero_byte
    jr fill_world_row_next
fill_world_row_slow:
    ld a,(transition_fill_y)
    call calc_screen_line_addr
    ld (row_screen_addr),hl
    ld a,(transition_fill_col)
    ld (background_query_col),a
    ld a,(transition_fill_width)
    ld (sprite_fill_width),a
fill_world_background_byte_loop:
    ld a,(background_query_col)
    ld c,a
    ld a,(transition_fill_y)
    call get_world_background_byte
    push af
    ld hl,(row_screen_addr)
    ld a,(background_query_col)
    add a,l
    ld l,a
    pop af
    ld (hl),a
    ld a,(background_query_col)
    inc a
    ld (background_query_col),a
    ld a,(sprite_fill_width)
    dec a
    ld (sprite_fill_width),a
    jr nz,fill_world_background_byte_loop
fill_world_row_next:
    ld a,(transition_fill_y)
    inc a
    ld (transition_fill_y),a
    ld a,(transition_fill_rows)
    dec a
    ld (transition_fill_rows),a
    jp nz,fill_world_background_row
    ret

write_water_sprite_1xn:
    ; Opaque byte-aligned sprite over guaranteed clear water. Unlike XOR this
    ; stores the source zeroes too, so the new rectangle is fully replaced.
    cp PLAYFIELD_BOTTOM
    ret nc
    ld l,a
    ld a,PLAYFIELD_BOTTOM
    sub l
    ld h,a
    ld a,b
    cp h
    jr c,write_water_1_rows_ready
    jr z,write_water_1_rows_ready
    ld b,h
write_water_1_rows_ready:
    ld a,l
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,write_water_1_table_ready
    inc h
write_water_1_table_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
write_water_1_row:
    pop hl
    ld a,l
    add a,c
    ld l,a
    ld a,(de)
    ld (hl),a
    inc de
    djnz write_water_1_row
    ld sp,(sprite_saved_sp)
    ei
    ret

write_water_sprite_2xn:
    ; Opaque byte-aligned 16-pixel sprite over water.
    cp PLAYFIELD_BOTTOM
    ret nc
    ld l,a
    ld a,PLAYFIELD_BOTTOM
    sub l
    ld h,a
    ld a,b
    cp h
    jr c,write_water_2_rows_ready
    jr z,write_water_2_rows_ready
    ld b,h
write_water_2_rows_ready:
    ld a,l
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,write_water_2_table_ready
    inc h
write_water_2_table_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
write_water_2_row:
    pop hl
    ld a,l
    add a,c
    ld l,a
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    djnz write_water_2_row
    ld sp,(sprite_saved_sp)
    ei
    ret

write_land_sprite_2xn:
    ; A shore tank sits inside bytes known to be full land (0xff). The visible
    ; cut-out is therefore the inverse of its ordinary one-bit source row.
    cp PLAYFIELD_BOTTOM
    ret nc
    ld l,a
    ld a,PLAYFIELD_BOTTOM
    sub l
    ld h,a
    ld a,b
    cp h
    jr c,write_land_2_rows_ready
    jr z,write_land_2_rows_ready
    ld b,h
write_land_2_rows_ready:
    ld a,l
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,write_land_2_table_ready
    inc h
write_land_2_table_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
write_land_2_row:
    pop hl
    ld a,l
    add a,c
    ld l,a
    ld a,(de)
    xor 255
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    xor 255
    ld (hl),a
    inc de
    djnz write_land_2_row
    ld sp,(sprite_saved_sp)
    ei
    ret

write_water_sprite_shifted_2xn:
    ; Opaque cached 16-pixel sprite. At shift zero the cached spill byte is
    ; deliberately skipped: writing it at X=240 would wrap past screen byte 31.
    cp PLAYFIELD_BOTTOM
    ret nc
    ld l,a
    ld a,PLAYFIELD_BOTTOM
    sub l
    ld h,a
    ld a,b
    cp h
    jr c,write_water_shifted_2_rows_ready
    jr z,write_water_shifted_2_rows_ready
    ld b,h
write_water_shifted_2_rows_ready:
    ld a,l
    ex af,af'
    ld a,c
    and 7
    ld (sprite_write_spill),a
    add a,a
    ld l,a
    ld h,0
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,c
    srl a
    srl a
    srl a
    ld c,a

    ex af,af'
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,write_water_shifted_2_table_ready
    inc h
write_water_shifted_2_table_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
    ld a,(sprite_write_spill)
    or a
    jr z,write_water_shifted_2_no_spill_row
write_water_shifted_2_row:
    pop hl
    ld a,c
    add a,l
    ld l,a
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    djnz write_water_shifted_2_row
    jr write_water_shifted_2_done
write_water_shifted_2_no_spill_row:
    pop hl
    ld a,c
    add a,l
    ld l,a
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    inc de                           ; skip the cached zero spill byte
    djnz write_water_shifted_2_no_spill_row
write_water_shifted_2_done:
    ld sp,(sprite_saved_sp)
    ei
    ret

write_water_sprite_shifted_4xn:
    ; Opaque cached 32-pixel ship, with the same shift-zero spill protection.
    cp PLAYFIELD_BOTTOM
    ret nc
    ld l,a
    ld a,PLAYFIELD_BOTTOM
    sub l
    ld h,a
    ld a,b
    cp h
    jr c,write_water_shifted_4_rows_ready
    jr z,write_water_shifted_4_rows_ready
    ld b,h
write_water_shifted_4_rows_ready:
    ld a,l
    ex af,af'
    ld a,c
    and 7
    ld (sprite_write_spill),a
    add a,a
    ld l,a
    ld h,0
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,c
    srl a
    srl a
    srl a
    ld c,a

    ex af,af'
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,write_water_shifted_4_table_ready
    inc h
write_water_shifted_4_table_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
    ld a,(sprite_write_spill)
    or a
    jr z,write_water_shifted_4_no_spill_row
write_water_shifted_4_row:
    pop hl
    ld a,c
    add a,l
    ld l,a
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    djnz write_water_shifted_4_row
    jr write_water_shifted_4_done
write_water_shifted_4_no_spill_row:
    pop hl
    ld a,c
    add a,l
    ld l,a
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    ld (hl),a
    inc de
    inc de                           ; skip the cached zero spill byte
    djnz write_water_shifted_4_no_spill_row
write_water_shifted_4_done:
    ld sp,(sprite_saved_sp)
    ei
    ret

write_intact_bridge_tank_shifted_2xn:
    ; Input A=Y, C=pixel X, B=10, DE=shift table. An active bridge tank always
    ; occupies bridge-relative rows 3..12, and with no centre marking every
    ; underlying byte is solid road (0xff). This avoids ten world queries.
    cp PLAYFIELD_BOTTOM
    ret nc
    ld l,a
    ld a,PLAYFIELD_BOTTOM
    sub l
    ld h,a
    ld a,b
    cp h
    jr c,bridge_tank_direct_rows_ready
    jr z,bridge_tank_direct_rows_ready
    ld b,h
bridge_tank_direct_rows_ready:
    ld a,l
    ex af,af'
    ld a,c
    and 7
    ld (sprite_write_spill),a
    add a,a
    ld l,a
    ld h,0
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,c
    srl a
    srl a
    srl a
    ld c,a
    xor a
    ld (bridge_tank_write_row),a

    ex af,af'
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,bridge_tank_screen_table_ready
    inc h
bridge_tank_screen_table_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
bridge_tank_direct_row:
    pop hl
    ld a,c
    add a,l
    ld l,a
    ld a,(de)
    xor 255
    ld (hl),a
    inc de
    inc l
    ld a,(de)
    xor 255
    ld (hl),a
    inc de
    inc l
    ld a,(sprite_write_spill)
    or a
    jr z,bridge_tank_solid_skip_spill
    ld a,(de)
    xor 255
    ld (hl),a
bridge_tank_solid_skip_spill:
    inc de

bridge_tank_direct_next_row:
    ld a,(bridge_tank_write_row)
    inc a
    ld (bridge_tank_write_row),a
    djnz bridge_tank_direct_row
    ld sp,(sprite_saved_sp)
    ei
    ret

write_water_projectile_2xn:
    ; Input A=Y, C=pixel X, B=height. Store the two-pixel mask directly over
    ; guaranteed water; unlike XOR this cannot remove an already visible shot.
    ld (world_write_y),a
    ld a,b
    ld (world_write_rows),a
    ld a,c
    and 7
    add a,a
    ld e,a
    ld d,0
    ld hl,projectile_mask_table
    add hl,de
    ld a,(hl)
    ld (world_write_byte_0),a
    inc hl
    ld a,(hl)
    ld (world_write_byte_1),a
    ld a,c
    srl a
    srl a
    srl a
    ld (world_write_col),a
write_water_projectile_row:
    ld a,(world_write_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    call calc_screen_line_addr
    ld a,(world_write_col)
    add a,l
    ld l,a
    ld a,(world_write_byte_0)
    ld (hl),a
    ld a,(world_write_byte_1)
    or a
    jr z,write_water_projectile_skip_spill
    inc l
    ld (hl),a
write_water_projectile_skip_spill:
    ld a,(world_write_y)
    inc a
    ld (world_write_y),a
    ld a,(world_write_rows)
    dec a
    ld (world_write_rows),a
    jr nz,write_water_projectile_row
    ret

write_world_sprite_2xn:
    ; Input A=Y, C=byte column, B=height, DE=two source bytes per row.
    ; Compose final bytes from fresh world geometry and the sprite mask, then
    ; store the result once. No visible XOR erase phase exists.
    ld (world_write_y),a
    ld a,c
    ld (world_write_col),a
    ld a,b
    ld (world_write_rows),a
write_world_2_row:
    ld a,(world_write_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    ld a,(world_write_col)
    ld c,a
    ld a,(world_write_y)
    call load_world_background_triplet

    ld a,(de)
    inc de
    ld b,a
    ld a,(world_background_byte_0)
    xor b
    ld (world_write_byte_0),a

    ld a,(de)
    inc de
    ld b,a
    ld a,(world_background_byte_1)
    xor b
    ld (world_write_byte_1),a

    ld a,(world_write_y)
    push de                           ; calc_screen_line_addr returns via DE/HL
    call calc_screen_line_addr
    pop de                            ; keep the sprite source cursor resident
    ld a,(world_write_col)
    add a,l
    ld l,a
    ld a,(world_write_byte_0)
    ld (hl),a
    inc l
    ld a,(world_write_byte_1)
    ld (hl),a
    ld a,(world_write_y)
    inc a
    ld (world_write_y),a
    ld a,(world_write_rows)
    dec a
    ld (world_write_rows),a
    jr nz,write_world_2_row
    ret

write_world_sprite_shifted_2xn:
    ; Input A=Y, C=pixel X, B=height, DE=eight-pointer shift table. This is the
    ; direct mixed-terrain compositor used by the player, the crossing plane
    ; and the bridge tank. The screen address advances incrementally between
    ; rows and the three bytes compose in registers, because a steering player
    ; runs all fourteen rows through here every frame.
    ld (world_write_y),a
    ld a,b
    ld (world_write_rows),a
    ld a,c
    and 7
    ld (world_write_spill),a
    add a,a
    ld l,a
    ld h,0
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ex de,hl                          ; DE = resolved sprite row cursor
    ld a,c
    srl a
    srl a
    srl a
    ld (world_write_col),a
    ld a,(world_write_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    push de
    call calc_screen_line_addr
    pop de
    ld a,(world_write_col)
    add a,l
    ld l,a
    ld (world_write_addr),hl
write_world_shifted_2_row:
    ld a,(world_write_col)
    ld c,a
    ld a,(world_write_y)
    call load_world_background_triplet

    ld hl,(world_write_addr)
    ld a,(world_background_byte_0)
    ld b,a
    ld a,(de)
    xor b
    ld (hl),a
    inc de
    inc l
    ld a,(world_background_byte_1)
    ld b,a
    ld a,(de)
    xor b
    ld (hl),a
    inc de
    ld a,(world_write_spill)
    or a
    jr z,write_world_shifted_2_skip_spill
    inc l
    ld a,(world_background_byte_2)
    ld b,a
    ld a,(de)
    xor b
    ld (hl),a
write_world_shifted_2_skip_spill:
    inc de

    ld a,(world_write_rows)
    dec a
    ld (world_write_rows),a
    ret z
    ld a,(world_write_y)
    inc a
    ld (world_write_y),a
    cp PLAYFIELD_BOTTOM
    ret nc
    ; Incremental Spectrum display-file step to Y+1 for the same columns.
    ld hl,(world_write_addr)
    inc h
    and 7
    jr nz,write_world_shifted_2_addr_ready
    ld a,h
    sub 8
    ld h,a
    ld a,l
    add a,32
    ld l,a
    jr nc,write_world_shifted_2_addr_ready
    ld a,h
    add a,8
    ld h,a
write_world_shifted_2_addr_ready:
    ld (world_write_addr),hl
    jp write_world_shifted_2_row

bridge_fill_rows:
    ; Input A=start Y, B=row count, C=byte value. The bridge is maintained as
    ; a persistent bitmap band: only rows entering or leaving its 16-line
    ; envelope are touched during scrolling. The two clipping stages remove
    ; The upper margin at the top and the status panel at the bottom.
    cp 16
    jr nc,bridge_fill_top_clipped
    ld l,a
    ld a,16
    sub l
    cp b
    ret nc
    ld e,a
    ld a,b
    sub e
    ld b,a
    ld a,16
bridge_fill_top_clipped:
    cp PLAYFIELD_BOTTOM
    ret nc
    ld l,a
    ld a,PLAYFIELD_BOTTOM
    sub l
    cp b
    jr nc,bridge_fill_count_ready
    ld b,a
bridge_fill_count_ready:
    ld a,b
    ld (bridge_rows_left),a
    ld a,l
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,bridge_fill_table_ready
    inc h
bridge_fill_table_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
bridge_fill_row:
    pop hl
    ld a,(bridge_col)
    add a,l
    ld l,a
    ld a,(bridge_width)
    ld b,a
bridge_fill_byte:
    ld (hl),c
    inc l
    djnz bridge_fill_byte
    ld a,(bridge_rows_left)
    dec a
    ld (bridge_rows_left),a
    jr nz,bridge_fill_row
    ld sp,(sprite_saved_sp)
    ei
    ret

bridge_refresh_edges:
    ; The bank pass touches only speed_pixels residue classes modulo eight.
    ; A 16-line bridge therefore has two affected rows per residue: four rows
    ; at fast speed, not all sixteen. Enumerating the same residues as
    ; render_dirty_rows removes the former worst-case bridge bottleneck.
    ld a,(course_phase)
    ld (bridge_edge_residue),a
    ld a,(speed_pixels)
    ld (bridge_edge_residues),a
bridge_refresh_residue:
    ; First affected row is bridge_y plus the modulo-eight distance to this
    ; dirty residue. The second is exactly eight scanlines below it.
    ld a,(bridge_y)
    and 7
    ld b,a
    ld a,(bridge_edge_residue)
    sub b
    and 7
    ld b,a
    ld a,(bridge_y)
    add a,b
    ld (bridge_edge_y),a
    call bridge_refresh_edge_row
    ld a,(bridge_edge_y)
    add a,8
    call bridge_refresh_edge_row

    ld a,(bridge_edge_residue)
    dec a
    and 7
    ld (bridge_edge_residue),a
    ld a,(bridge_edge_residues)
    dec a
    ld (bridge_edge_residues),a
    jr nz,bridge_refresh_residue
    ret

bridge_refresh_edge_row:
    ; Input A=one dirty bridge Y. HUD and lower margin remain immutable.
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    call calc_screen_line_addr
    ld a,(bridge_col)
    add a,l
    ld l,a
    ld (hl),255
    inc l
    ld (hl),255
    ld a,(bridge_width)
    sub 3
    add a,l
    ld l,a
    ld (hl),255
    inc l
    ld (hl),255
    ret

bridge_paint_road_attributes:
    ; A 16-line bridge covers two attribute rows when aligned and three while
    ; between cells. White-on-green road attributes fill the land on both
    ; sides; the river span is then overwritten with the brown bridge colour.
    ld a,0x4a                       ; BRIGHT red ink over BRIGHT blue water
    ld (bridge_center_attr),a
    jr bridge_paint_road_attribute_span

bridge_paint_destroyed_road_attributes:
    ; Broken bridge: retain both white approaches but restore blue water in
    ; the former span. The road remnant continues scrolling with the world.
    ld a,0x4c                       ; water must remain the same BRIGHT blue
    ld (bridge_center_attr),a
bridge_paint_road_attribute_span:
#if TIMEX_HICOLOR
    jp timex_bridge_paint_road_span
#else
    ld a,(bridge_y)
    srl a
    srl a
    srl a
    ld (bridge_attr_row),a
    ld a,(bridge_y)
    and 7
    ld a,2
    jr z,bridge_attr_count_ready
    inc a
bridge_attr_count_ready:
    ld (bridge_attr_rows),a
bridge_attr_row_loop:
    ld a,(bridge_attr_row)
    call bridge_paint_road_attribute_row
advance_bridge_attribute_row:
    ld a,(bridge_attr_row)
    inc a
    ld (bridge_attr_row),a
    ld a,(bridge_attr_rows)
    dec a
    ld (bridge_attr_rows),a
    jr nz,bridge_attr_row_loop
    ret
#endif

bridge_clear_road_attributes:
    ; Restore every attribute cell touched by the road, not merely the river
    ; span. This prevents white bank rectangles remaining after destruction.
#if TIMEX_HICOLOR
    jp timex_bridge_clear_road_span
#else
    ld a,(bridge_y)
    srl a
    srl a
    srl a
    ld (bridge_attr_row),a
    ld a,(bridge_y)
    and 7
    ld a,2
    jr z,bridge_clear_attr_count_ready
    inc a
bridge_clear_attr_count_ready:
    ld (bridge_attr_rows),a
bridge_clear_attr_loop:
    ld a,(bridge_attr_row)
    ld c,0x4c
    call bridge_paint_full_attribute_row
    ld a,(bridge_attr_row)
    inc a
    ld (bridge_attr_row),a
    ld a,(bridge_attr_rows)
    dec a
    ld (bridge_attr_rows),a
    jr nz,bridge_clear_attr_loop
    ret
#endif

#if not TIMEX_HICOLOR
bridge_paint_road_attribute_row:
    ; Input A=attribute row. Paint the left road, bridge and right road in one
    ; 32-byte pass. The previous full-white pass followed by a brown overwrite
    ; touched the wide river span twice and caused visible bridge-frame stalls.
    cp 2
    ret c
    cp 21
    ret nc
    ld b,a
    and 7
    rrca
    rrca
    rrca
    ld l,a
    ld a,b
    srl a
    srl a
    srl a
    add a,0x58
    ld h,a

    ld a,(bridge_col)
    or a
    jr z,bridge_attr_paint_span
    ld b,a
    ld a,0x44                       ; terrain-green ink over black paper: the
                                    ; road look comes from bitmap lines, so
                                    ; the 8x8 cells never clash with the banks
bridge_attr_left_byte:
    ld (hl),a
    inc l
    djnz bridge_attr_left_byte
bridge_attr_paint_span:
    ld a,(bridge_width)
    ld b,a
    ld a,(bridge_center_attr)       ; brown intact span or normal broken water
bridge_attr_span_byte:
    ld (hl),a
    inc l
    djnz bridge_attr_span_byte

    ld a,(bridge_col)
    ld b,a
    ld a,(bridge_width)
    add a,b
    ld b,a
    ld a,32
    sub b
    ret z
    ld b,a
    ld a,0x44
bridge_attr_right_byte:
    ld (hl),a
    inc l
    djnz bridge_attr_right_byte
    ret

bridge_paint_full_attribute_row:
    ; Input A=row (2..22), C=value. Paint all 32 cells in that character row.
    cp 2
    ret c
    cp 21
    ret nc
    ld b,a
    and 7
    rrca
    rrca
    rrca
    ld l,a
    ld a,b
    srl a
    srl a
    srl a
    add a,0x58
    ld h,a
    ld b,4
    ld a,c
bridge_full_attr_byte:
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    djnz bridge_full_attr_byte
    ret
#endif

bridge_update_attributes:
    ; The bitmap bridge moves every pixel, but its set of 8x8 colour cells
    ; normally does not.  Compare the old and new inclusive attribute spans:
    ; at most one row leaves at the top and one arrives at the bottom.
    ; bridge_restore_y is scratch for reconstructing the departing bitmap
    ; rows and has already advanced, so recover old Y from new Y - speed.
#if TIMEX_HICOLOR
    jp timex_bridge_update_attributes
#else
    ld a,(speed_pixels)
    ld d,a
    ld a,(bridge_y)
    sub d
    srl a
    srl a
    srl a
    ld b,a
    ld a,(bridge_y)
    srl a
    srl a
    srl a
    cp b
    jr z,bridge_attr_top_unchanged
    ld a,b
    ld c,0x4c
    call bridge_paint_full_attribute_row
bridge_attr_top_unchanged:
    ld a,(bridge_y)
    sub d
    add a,15
    srl a
    srl a
    srl a
    ld b,a
    ld a,(bridge_y)
    add a,15
    srl a
    srl a
    srl a
    cp b
    ret z
    jp bridge_paint_road_attribute_row
#endif

#if TIMEX_HICOLOR
timex_bridge_paint_road_span:
    ld a,(bridge_y)
    ld (timex_attr_y),a
    ld a,16
    ld (bridge_attr_rows),a
timex_bridge_paint_span_row:
    ld a,(timex_attr_y)
    call timex_bridge_paint_road_scanline
    ld a,(timex_attr_y)
    inc a
    ld (timex_attr_y),a
    ld a,(bridge_attr_rows)
    dec a
    ld (bridge_attr_rows),a
    jr nz,timex_bridge_paint_span_row
    ret

timex_bridge_clear_road_span:
    ld a,(bridge_y)
    ld (timex_attr_y),a
    ld a,16
    ld (bridge_attr_rows),a
timex_bridge_clear_span_row:
    ld a,(timex_attr_y)
    call timex_bridge_clear_scanline
    ld a,(timex_attr_y)
    inc a
    ld (timex_attr_y),a
    ld a,(bridge_attr_rows)
    dec a
    ld (bridge_attr_rows),a
    jr nz,timex_bridge_clear_span_row
    ret

timex_bridge_update_attributes:
    ; The bitmap moved by one or two lines. Restore those exact departing 8x1
    ; rows and paint only the same number entering at the new bottom edge.
    ld a,(speed_pixels)
    ld (bridge_attr_rows),a
    ld b,a
    ld a,(bridge_y)
    sub b
    ld (timex_attr_y),a
timex_bridge_restore_old_row:
    ld a,(bridge_attr_rows)
    or a
    jr z,timex_bridge_prepare_new_rows
    ld a,(timex_attr_y)
    call timex_bridge_clear_scanline
    ld a,(timex_attr_y)
    inc a
    ld (timex_attr_y),a
    ld a,(bridge_attr_rows)
    dec a
    ld (bridge_attr_rows),a
    jr timex_bridge_restore_old_row

timex_bridge_prepare_new_rows:
    ld a,(speed_pixels)
    ld (bridge_attr_rows),a
    ld b,a
    ld a,(bridge_y)
    add a,16
    sub b
    ld (timex_attr_y),a
timex_bridge_paint_new_row:
    ld a,(bridge_attr_rows)
    or a
    ret z
    ld a,(timex_attr_y)
    call timex_bridge_paint_road_scanline
    ld a,(timex_attr_y)
    inc a
    ld (timex_attr_y),a
    ld a,(bridge_attr_rows)
    dec a
    ld (bridge_attr_rows),a
    jr timex_bridge_paint_new_row

timex_bridge_clear_scanline:
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    ld c,0x4c
    jp timex_fill_attribute_scanline

timex_bridge_paint_road_scanline:
    ; Input A=physical Y. Road approaches stay white/green while the centre is
    ; brown when intact or ordinary green/blue after the span is destroyed.
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    call timex_attribute_address
    ld a,(bridge_col)
    or a
    jr z,timex_bridge_attr_span
    ld b,a
    ld a,0x67
timex_bridge_attr_left_byte:
    ld (hl),a
    inc l
    djnz timex_bridge_attr_left_byte
timex_bridge_attr_span:
    ld a,(bridge_width)
    ld b,a
    ld a,(bridge_center_attr)
timex_bridge_attr_center_byte:
    ld (hl),a
    inc l
    djnz timex_bridge_attr_center_byte
    ld a,(bridge_col)
    ld b,a
    ld a,(bridge_width)
    add a,b
    ld b,a
    ld a,32
    sub b
    ret z
    ld b,a
    ld a,0x67
timex_bridge_attr_right_byte:
    ld (hl),a
    inc l
    djnz timex_bridge_attr_right_byte
    ret
#endif
