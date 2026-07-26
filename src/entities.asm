; ---------------------------------------------------------------------------
; Object movement
; ---------------------------------------------------------------------------

update_entities:
    ; Order matters: player steering precedes collisions, the scrolling actors
    ; advance before the projectile test, and bridge exclusion runs last so a
    ; freshly respawned ship/helicopter cannot share its vertical band.
    call update_player
    call update_hit_explosion
    call advance_ship0
    call advance_ship1
    call advance_enemy_plane
    call advance_helicopter
    call advance_balloon
    call update_fuel
    call update_tank
    call update_bridge_tank
    call update_tank_shell
    ; The bridge is world geometry and therefore updates before the common
    ; resident-sprite compositor. No object group is globally removed for it.
    call update_bridge
    call reset_world_background_cache
    call update_bullet
    call keep_water_objects_off_bridge
    ; Commit the current sprite positions before testing them. A lethal object
    ; is therefore always visible at the coordinates used by collision logic.
    call transition_all_resident_sprites
    jp check_player_collision

update_player:
    ld a,(player_move)
    ld (player_bank),a              ; pose used by both draw and collision
    or a
    ret z
    cp 255
    jr nz,move_player_right
    ld a,(player_x)
    cp 2
    jr nc,move_player_left_two
    xor a
    ld (player_x),a
    ret
move_player_left_two:
    sub 2
    ld (player_x),a
    ret
move_player_right:
    ld a,(player_x)
    add a,2
    cp 241
    jr c,store_player_x
    ld a,240
store_player_x:
    ld (player_x),a
    ret

can_spawn_water_enemy:
    ; Cap combat sprites over the river at two simultaneous actors. The static
    ; balloon, FUEL and tanks have separate roles and are not counted here.
    ld b,0
    ld a,(ship0_active)
    add a,b
    ld b,a
    ld a,(ship1_active)
    add a,b
    ld b,a
    ld a,(helicopter_active)
    add a,b
    ld b,a
    ld a,(enemy_plane_active)
    add a,b
    cp 2
    jr c,water_enemy_slot_available
    xor a
    ret
water_enemy_slot_available:
    ld a,1
    ret

advance_ship0:
    ; Y follows river scroll. Leaving or destruction starts a quiet interval;
    ; respawn is also held until one of the two combat-sprite slots is free.
    ld a,(ship0_active)
    or a
    jr z,wait_for_ship0
    ld a,(speed_pixels)
    ld b,a
    ld a,(ship0_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr c,store_ship0_y
    xor a
    ld (ship0_active),a
    ld a,160
    ld (ship0_delay),a
    ret
store_ship0_y:
    ld (ship0_y),a
    ret
wait_for_ship0:
    ld a,(ship0_delay)
    or a
    jr z,try_spawn_ship0
    dec a
    ld (ship0_delay),a
    ret
try_spawn_ship0:
    call can_spawn_water_enemy
    or a
    jr nz,spawn_ship0
    ld a,16
    ld (ship0_delay),a
    ret
spawn_ship0:
    ld a,16
    call choose_clear_water_actor_y
    cp 16
    jr nz,defer_ship0_spawn
    ld (ship0_y),a
    ld a,1
    ld (ship0_active),a
    call calc_safe_river_x_wide
    ld (ship0_x),a
    ret
defer_ship0_spawn:
    ld a,16
    ld (ship0_delay),a
    ret

advance_ship1:
    ld a,(ship1_active)
    or a
    jr z,wait_for_ship1
    ld a,(speed_pixels)
    ld b,a
    ld a,(ship1_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr c,store_ship1_y
    xor a
    ld (ship1_active),a
    ld a,160
    ld (ship1_delay),a
    ret
wait_for_ship1:
    ld a,(ship1_delay)
    or a
    jr z,try_spawn_ship1
    dec a
    ld (ship1_delay),a
    ret
try_spawn_ship1:
    call can_spawn_water_enemy
    or a
    jr nz,spawn_ship1
    ld a,16
    ld (ship1_delay),a
    ret
spawn_ship1:
    ld a,16
    call choose_clear_water_actor_y
    cp 16
    jr nz,defer_ship1_spawn
    ld (ship1_y),a
    ld a,1
    ld (ship1_active),a
    call calc_safe_river_x_wide
    ld (ship1_x),a
    ld a,1
    ld (ship1_dir),a
    ld a,2
    ld (ship1_timer),a
    ret
defer_ship1_spawn:
    ld a,16
    ld (ship1_delay),a
    ret
store_ship1_y:
    ld (ship1_y),a

patrol_ship1:
    ; Ship 0 is fixed in its world sample. Ship 1 advances by one real pixel
    ; every other frame and treats an island as a bank of its current branch.
    ld a,(ship1_timer)
    dec a
    ld (ship1_timer),a
    ret nz
    ld a,2
    ld (ship1_timer),a
    ld a,(ship1_x)
    ld c,a
    ld a,(ship1_y)
    call get_pixel_lane_bounds
    ; The generic bounds reserve 16 pixels; subtract another 16 for this hull.
    ld a,e
    sub 16
    ld e,a
    ld a,(ship1_dir)
    cp 255
    jr z,ship1_patrol_left
    ld a,(ship1_x)
    inc a
    cp e
    jr c,store_ship1_x
    jr z,store_ship1_x
    jr ship1_turn_left
store_ship1_x:
    ld (ship1_x),a
    ret
ship1_turn_left:
    ld a,255
    ld (ship1_dir),a
    ret
ship1_patrol_left:
    ld a,(ship1_x)
    cp d
    jr c,ship1_turn_right
    jr z,ship1_turn_right
    dec a
    ld (ship1_x),a
    ret
ship1_turn_right:
    ld a,1
    ld (ship1_dir),a
    ret

advance_enemy_plane:
    ; The aircraft crosses land and water at three real pixels per frame, but
    ; its Y advances with the course. It stays on the world line on which it
    ; started instead of being pinned to the monitor. Once shot down it stays
    ; absent until the scene is initialized again.
    ld a,(enemy_plane_active)
    or a
    jr z,wait_for_enemy_plane
    ld a,(speed_pixels)
    ld b,a
    ld a,(enemy_plane_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr c,store_enemy_plane_y
    xor a
    ld (enemy_plane_active),a
    ld a,16
    ld (enemy_plane_delay),a
    ret
store_enemy_plane_y:
    ld (enemy_plane_y),a

    ld a,(enemy_plane_x)
    add a,3
    cp 241
    jr c,store_enemy_plane_x
    xor a
store_enemy_plane_x:
    ld (enemy_plane_x),a
    ret

wait_for_enemy_plane:
    ; 255 means the one-per-life aircraft was shot down. Otherwise it waits
    ; off-screen until the Y=16 entrance is genuinely clear.
    ld a,(enemy_plane_delay)
    cp 255
    ret z
    or a
    jr z,try_spawn_enemy_plane
    dec a
    ld (enemy_plane_delay),a
    ret
try_spawn_enemy_plane:
    ; The crossing aircraft never shares a board with a bridge: while a span,
    ; its queued course block or a destroyed road is around, keep waiting.
    call bridge_scene_active
    or a
    jr nz,defer_enemy_plane_spawn
    call can_spawn_water_enemy
    or a
    jr z,defer_enemy_plane_spawn
    ld a,16
    call choose_clear_water_actor_y
    cp 16
    jr nz,defer_enemy_plane_spawn
    ld (enemy_plane_y),a
    xor a
    ld (enemy_plane_x),a
    inc a
    ld (enemy_plane_active),a
    ret
defer_enemy_plane_spawn:
    ld a,16
    ld (enemy_plane_delay),a
    ret

update_hit_explosion:
    ; Impact fire is attached to the world like other river objects. It moves
    ; down with the course and advances through three five-frame silhouettes.
    ld a,(hit_explosion_active)
    or a
    ret z
    ld a,(speed_pixels)
    ld b,a
    ld a,(hit_explosion_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr nc,finish_hit_explosion
    ld (hit_explosion_y),a

    ld a,(hit_explosion_timer)
    dec a
    ld (hit_explosion_timer),a
    jr z,finish_hit_explosion
    ld a,(hit_explosion_anim_timer)
    dec a
    ld (hit_explosion_anim_timer),a
    ret nz
    ld a,5
    ld (hit_explosion_anim_timer),a
    ld a,(hit_explosion_frame)
    inc a
    cp 3
    jr c,store_hit_explosion_frame
    ld a,2
store_hit_explosion_frame:
    ld (hit_explosion_frame),a
    ret
finish_hit_explosion:
    xor a
    ld (hit_explosion_active),a
    ret

start_hit_explosion:
    ; Input A=X of the 16-pixel effect, B=actor Y. Clamp it to the playfield,
    ; then restart both the visual animation and the AY impact burst.
    ld (hit_explosion_x),a
    ld a,b
    cp 18
    jr nc,hit_explosion_has_top_room
    ld a,16
    jr hit_explosion_y_ready
hit_explosion_has_top_room:
    sub 2
    cp PLAYFIELD_BOTTOM-12
    jr c,hit_explosion_y_ready
    ld a,PLAYFIELD_BOTTOM-13
hit_explosion_y_ready:
    ld (hit_explosion_y),a
    ld a,15
    ld (hit_explosion_timer),a
    ld a,5
    ld (hit_explosion_anim_timer),a
    xor a
    ld (hit_explosion_frame),a
    inc a
    ld (hit_explosion_active),a
    jp start_ay_explosion

choose_clear_water_actor_y:
    ; Runtime spawns are allowed only at the first playfield line. If it is too
    ; close to another actor, return zero and let the caller retry later; never
    ; search lower lanes, which used to make sprites pop into mid-screen.
    ld b,16
    ld a,(ship0_active)
    or a
    jr z,check_ship1_spawn_y
    ld a,(ship0_y)
    call actor_y_too_close
    jr c,top_actor_y_is_busy
check_ship1_spawn_y:
    ld a,(ship1_active)
    or a
    jr z,check_helicopter_spawn_y
    ld a,(ship1_y)
    call actor_y_too_close
    jr c,top_actor_y_is_busy
check_helicopter_spawn_y:
    ld a,(helicopter_active)
    or a
    jr z,check_balloon_spawn_y
    ld a,(helicopter_y)
    call actor_y_too_close
    jr c,top_actor_y_is_busy
check_balloon_spawn_y:
    ld a,(balloon_active)
    or a
    jr z,check_plane_spawn_y
    ld a,(balloon_y)
    call actor_y_too_close
    jr c,top_actor_y_is_busy
check_plane_spawn_y:
    ld a,(enemy_plane_active)
    or a
    jr z,check_fuel_spawn_y
    ld a,(enemy_plane_y)
    call actor_y_too_close
    jr c,top_actor_y_is_busy
check_fuel_spawn_y:
    ld a,(fuel_active)
    or a
    jr z,actor_y_is_clear
    ld a,(fuel_y)
    call actor_y_overlaps_fuel
    jr c,top_actor_y_is_busy
actor_y_is_clear:
    ld a,16
    ret
top_actor_y_is_busy:
    xor a
    ret

actor_y_too_close:
    ; Input A=existing actor Y, B=candidate Y. Carry means less than twenty-two
    ; scanlines apart, covering the 20-line balloon plus a two-line gap.
    ld c,a
    ld a,b
    cp c
    jr nc,actor_candidate_below
    ld a,c
    sub b
    cp 22
    ret
actor_candidate_below:
    sub c
    cp 22
    ret

actor_y_overlaps_fuel:
    ; Input A=FUEL top, B=candidate combat-actor top. Carry means that the
    ; tallest 20-line body plus a two-line gap intersects the full 32-line
    ; depot. This is used when another water actor spawns after FUEL exists.
    ld c,a
    ld a,b
    add a,22                       ; tallest candidate plus a two-line gap
    cp c
    jr c,actor_clears_fuel
    jr z,actor_clears_fuel
    ld a,c
    cp PLAYFIELD_BOTTOM-32
    jr nc,fuel_bottom_is_playfield_edge
    add a,32
    jr fuel_bottom_ready
fuel_bottom_is_playfield_edge:
    ld a,PLAYFIELD_BOTTOM
fuel_bottom_ready:
    cp b
    jr c,actor_clears_fuel
    jr z,actor_clears_fuel
    xor a
    cp 1                            ; 0 < 1 sets carry in the compact assembler
    ret
actor_clears_fuel:
    or a                            ; clear carry
    ret

choose_clear_fuel_y:
    ; FUEL follows the same top-only rule. A symmetric 32-line gap is
    ; deliberately conservative; a busy entrance makes the depot wait.
    ld b,16
    ld a,(ship0_active)
    or a
    jr z,check_ship1_fuel_y
    ld a,(ship0_y)
    call fuel_y_too_close
    jr c,top_fuel_y_is_busy
check_ship1_fuel_y:
    ld a,(ship1_active)
    or a
    jr z,check_helicopter_fuel_y
    ld a,(ship1_y)
    call fuel_y_too_close
    jr c,top_fuel_y_is_busy
check_helicopter_fuel_y:
    ld a,(helicopter_active)
    or a
    jr z,check_plane_fuel_y
    ld a,(helicopter_y)
    call fuel_y_too_close
    jr c,top_fuel_y_is_busy
check_plane_fuel_y:
    ld a,(enemy_plane_active)
    or a
    jr z,check_balloon_fuel_y
    ld a,(enemy_plane_y)
    call fuel_y_too_close
    jr c,top_fuel_y_is_busy
check_balloon_fuel_y:
    ld a,(balloon_active)
    or a
    jr z,fuel_y_is_clear
    ld a,(balloon_y)
    call fuel_y_too_close
    jr c,top_fuel_y_is_busy
fuel_y_is_clear:
    ld a,16
    ret
top_fuel_y_is_busy:
    xor a
    ret

fuel_y_too_close:
    ; Input A=existing actor Y, B=candidate FUEL Y. Carry means that their
    ; top lines differ by less than the depot's full 32-pixel height.
    ld c,a
    ld a,b
    cp c
    jr nc,fuel_candidate_below
    ld a,c
    sub b
    cp 32
    ret
fuel_candidate_below:
    sub c
    cp 32
    ret

advance_helicopter:
    ; Every pass through the lower edge toggles stationary/patrolling mode.
    ld a,(helicopter_active)
    or a
    jr z,wait_for_helicopter
    call animate_helicopter_rotor
    ld a,(speed_pixels)
    ld b,a
    ld a,(helicopter_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr c,store_helicopter_y
    xor a
    ld (helicopter_active),a
    ld a,160
    ld (helicopter_delay),a
    ret
wait_for_helicopter:
    ld a,(helicopter_delay)
    or a
    jr z,try_spawn_helicopter
    dec a
    ld (helicopter_delay),a
    ret
try_spawn_helicopter:
    call can_spawn_water_enemy
    or a
    jr nz,spawn_helicopter
    ld a,16
    ld (helicopter_delay),a
    ret
spawn_helicopter:
    ld a,16
    call choose_clear_water_actor_y
    cp 16
    jr nz,defer_helicopter_spawn
    ld (helicopter_y),a
    ld a,1
    ld (helicopter_active),a
    call calc_safe_river_x
    ld (helicopter_x),a
    ld a,(helicopter_move)
    xor 1
    ld (helicopter_move),a
    ld a,1
    ld (helicopter_dir),a
    jr patrol_helicopter
defer_helicopter_spawn:
    ld a,16
    ld (helicopter_delay),a
    ret
store_helicopter_y:
    ld (helicopter_y),a

patrol_helicopter:
    ; Alternate helicopter appearances are stationary or one-pixel patrols.
    ; The active fork branch supplies the collision limits.
    ld a,(helicopter_move)
    or a
    ret z
    ld a,(helicopter_x)
    ld c,a
    ld a,(helicopter_y)
    call get_pixel_lane_bounds
    ld a,(helicopter_dir)
    cp 255
    jr z,helicopter_patrol_left
    ld a,(helicopter_x)
    inc a
    cp e
    jr c,store_helicopter_x
    jr z,store_helicopter_x
    jr helicopter_turn_left
store_helicopter_x:
    ld (helicopter_x),a
    ret
helicopter_turn_left:
    ld a,255
    ld (helicopter_dir),a
    ret
helicopter_patrol_left:
    ld a,(helicopter_x)
    cp d
    jr c,helicopter_turn_right
    jr z,helicopter_turn_right
    dec a
    ld (helicopter_x),a
    ret
helicopter_turn_right:
    ld a,1
    ld (helicopter_dir),a
    ret

animate_helicopter_rotor:
    ; River Raid toggles Heli0/Heli1 every second display frame. Only the two
    ; rotor rows differ, so the body remains stable at the authentic cadence.
    ld a,(helicopter_anim_timer)
    dec a
    ld (helicopter_anim_timer),a
    ret nz
    ld a,2
    ld (helicopter_anim_timer),a
    ld a,(helicopter_frame)
    xor 1
    ld (helicopter_frame),a
    ret

advance_balloon:
    ; The balloon is fixed in X like an obstacle anchored in the world. It has
    ; no patrol or animation; only the ordinary course scroll changes its Y.
    ld a,(balloon_active)
    or a
    jr z,wait_for_balloon
    ld a,(speed_pixels)
    ld b,a
    ld a,(balloon_y)
    add a,b
    cp PLAYFIELD_BOTTOM-19           ; keep all twenty rows in the playfield
    jr c,store_balloon_y
    xor a
    ld (balloon_active),a
    ld a,180
    ld (balloon_delay),a
    ret
store_balloon_y:
    ld (balloon_y),a
    ret

wait_for_balloon:
    ld a,(balloon_delay)
    or a
    jr z,try_spawn_balloon
    dec a
    ld (balloon_delay),a
    ret
try_spawn_balloon:
    ld a,16
    call choose_clear_water_actor_y
    cp 16
    jr nz,defer_balloon_spawn
    ld (balloon_y),a
    call calc_safe_river_x
    and 0xf8                        ; byte alignment avoids a shifted cache
    ld (balloon_x),a
    ld a,1
    ld (balloon_active),a
    ret
defer_balloon_spawn:
    ld a,16
    ld (balloon_delay),a
    ret

update_fuel:
    ; FUEL is a non-lethal river object. Touching its 8x32 rectangle pauses
    ; consumption and transfers one unit every five frames; without contact,
    ; one unit is burned every 32 frames.
    xor a
    ld (fuel_refueling),a
    ld a,(fuel_active)
    or a
    jr z,update_fuel_waiting

    ld a,(speed_pixels)
    ld b,a
    ld a,(fuel_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr c,store_scrolling_fuel_y
    xor a
    ld (fuel_active),a
    ld a,96
    ld (fuel_delay),a
    jp consume_fuel
store_scrolling_fuel_y:
    ld (fuel_y),a

check_player_refuels:
    ld a,8
    ld (object_collision_width),a
    ld a,(fuel_x)
    ld c,a
    ld a,(fuel_y)
    ld b,32
    call player_overlaps_object
    jr nc,player_not_refueling
    ld a,1
    ld (fuel_refueling),a
    jp refill_player_fuel
player_not_refueling:
    ld a,1
    ld (fuel_refill_timer),a
    jp consume_fuel

update_fuel_waiting:
    ld a,(fuel_delay)
    or a
    jr z,spawn_fuel
    dec a
    ld (fuel_delay),a
    jp consume_fuel
spawn_fuel:
    ld a,16
    call choose_clear_fuel_y
    cp 16
    jr z,spawn_fuel_at_top
    ; A crowded entrance used to move the depot to an arbitrary on-screen Y.
    ; Wait instead, so FUEL always arrives from the top of the playfield.
    ld a,16
    ld (fuel_delay),a
    jp consume_fuel
spawn_fuel_at_top:
    ld (fuel_y),a
    call calc_safe_river_x
    and 0xf8
    ld (fuel_x),a
    ld a,1
    ld (fuel_active),a
    ld (fuel_refill_timer),a
    jp consume_fuel

refill_player_fuel:
    ld a,(fuel_refill_timer)
    dec a
    ld (fuel_refill_timer),a
    ret nz
    ld a,5
    ld (fuel_refill_timer),a
    ld a,(fuel_level)
    cp 48
    jp nc,start_fuel_ding           ; full tank keeps the higher confirmation ping
    inc a
    ld (fuel_level),a
    push af
    call start_fuel_ding
    pop af
    and 7                           ; one HUD cell changes every eight units
    ret nz
    jp mark_fuel_hud_dirty

consume_fuel:
#if AUTOPILOT
    ret                             ; the benchmark flight never runs dry
#endif
    ld a,(fuel_consume_timer)
    dec a
    ld (fuel_consume_timer),a
    ret nz
    ld a,32
    ld (fuel_consume_timer),a
    ld a,(fuel_level)
    or a
    jr z,out_of_fuel
    dec a
    ld (fuel_level),a
    and 7
    cp 7                            ; 8->7, 16->15, ... removes one full cell
    jr nz,check_consumed_fuel_empty
    call mark_fuel_hud_dirty
check_consumed_fuel_empty:
    ld a,(fuel_level)
    or a
    ret nz
out_of_fuel:
    ld a,1
    ld (crashed),a
    ret

mark_fuel_hud_dirty:
    ld a,(hud_dirty)
    or 4
    ld (hud_dirty),a
    ret

update_tank:
    ; The ordinary shore gun has its own actor slot. Bridge creation no longer
    ; steals these coordinates or interrupts a shell already in flight.
    jp update_shore_tank

update_bridge_tank:
    ; Mode 1 crosses an intact bridge. Mode 2 exists only after destruction,
    ; when a survivor on an approach becomes a shore gun. Mode 3 waits above
    ; the playfield for its intact bridge to become visible.
    ld a,(bridge_tank_mode)
    cp 3
    jr nc,activate_waiting_bridge_tank
    or a
    ret z

    ld a,(bridge_tank_active)
    or a
    ret z
    call scroll_bridge_tank_down
    or a
    ret z
    ld a,(bridge_tank_mode)
    cp 2
    jp z,maybe_fire_bridge_tank
    jp drive_tank_across_bridge

activate_waiting_bridge_tank:
    ld a,(bridge_active)
    or a
    jr z,cancel_waiting_bridge_tank
    ld a,(bridge_y)
    cp 13                           ; tank Y=bridge Y+3 must start at Y >= 16
    ret c
    ld a,1
    ld (bridge_tank_mode),a
    ld a,1
    ld (bridge_tank_active),a
    ld a,(bridge_y)
    add a,3
    ld (bridge_tank_y),a
    ld a,12
    ld (bridge_tank_fire_timer),a

    ; A crossing tank enters from the physical screen edge, not from the river
    ; bank. The complete white approach road is therefore part of its journey.
    ld a,1
    ld (bridge_tank_move_phase),a    ; first base-speed step is one pixel
    ld a,(bridge_tank_side)
    or a
    jr nz,start_crossing_tank_on_right
    xor a
    ld (bridge_tank_x),a
    ret
start_crossing_tank_on_right:
    ld a,240                        ; 16px hull exactly touches right edge
    ld (bridge_tank_x),a
    ret

cancel_waiting_bridge_tank:
    xor a
    ld (bridge_tank_mode),a
    ld (bridge_tank_active),a
    ret

scroll_bridge_tank_down:
    ; Keep exactly the same world-line offset as the scrolling bridge.
    ld a,(speed_pixels)
    ld b,a
    ld a,(bridge_tank_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr c,store_bridge_tank_y
    xor a
    ld (bridge_tank_active),a
    ld (bridge_tank_mode),a
    ret
store_bridge_tank_y:
    ld (bridge_tank_y),a
    ld a,1
    ret

drive_tank_across_bridge:
    ; Traverse the complete road from one screen edge to the other. At base
    ; alternating 1/2-pixel steps average 1.5 px/frame, slightly slower than
    ; the former fixed 2 px. This is the tank's own speed and is deliberately
    ; independent of the player's Q/A scroll modifier.
    ld a,(bridge_tank_side)
    or a
    jr nz,drive_bridge_tank_left

    ld a,(bridge_tank_x)
    cp 240
    jr nc,bridge_tank_finished_road
    ld c,a
    call get_bridge_tank_horizontal_step
    ld b,a
    ld a,c
    add a,b
    cp 241
    jr c,store_bridge_tank_right_x
    ld a,240
store_bridge_tank_right_x:
    ld (bridge_tank_x),a
    ret

drive_bridge_tank_left:
    ld a,(bridge_tank_x)
    or a
    jr z,bridge_tank_finished_road
    ld c,a
    call get_bridge_tank_horizontal_step
    ld b,a
    ld a,c
    cp b
    jr nc,subtract_bridge_tank_left_step
    xor a
    jr store_bridge_tank_left_x
subtract_bridge_tank_left_step:
    sub b
store_bridge_tank_left_x:
    ld (bridge_tank_x),a
    ret

get_bridge_tank_horizontal_step:
    ; Return alternating 1/2 regardless of course speed. Q/A changes how fast
    ; the world approaches the player, never an actor's sideways motor speed.
    ld a,(bridge_tank_move_phase)
    xor 1
    ld (bridge_tank_move_phase),a
    inc a
    ret

bridge_tank_finished_road:
    xor a
    ld (bridge_tank_active),a
    ld (bridge_tank_mode),a
    ret

update_shore_tank:
    ; A live shore tank follows its bank down the screen and counts down to a
    ; shot. The shell may outlive the firing tank after it leaves the screen.
    ld a,(tank_active)
    or a
    jr z,wait_for_tank
    call scroll_tank_down
    or a
    ret z
    jp maybe_fire_tank

scroll_tank_down:
    ; Return A=1 while the tank remains in the 152-line playfield, else zero.
    ld a,(speed_pixels)
    ld b,a
    ld a,(tank_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr c,store_tank_y
    xor a
    ld (tank_active),a
    ld a,72
    ld (tank_delay),a
    xor a
    ret
store_tank_y:
    ld (tank_y),a
    ld a,1
    ret
wait_for_tank:
    ld a,(tank_delay)
    or a
    jr z,spawn_tank
    dec a
    ld (tank_delay),a
    ret
spawn_tank:
    ; New shore guns also stay off bridge boards; a live tank finishes its
    ; run, but respawns wait until the road scene has fully passed.
    call bridge_scene_active
    or a
    jr nz,defer_tank_spawn
    ld a,1
    ld (tank_active),a
    ld a,16
    ld (tank_y),a
    ld a,(tank_side)
    xor 1
    ld (tank_side),a
    ld a,16
    call calc_tank_col
    ld (tank_col),a
    add a,a
    add a,a
    add a,a
    ld (tank_x),a
    ld a,72
    ld (tank_fire_timer),a
    ret
defer_tank_spawn:
    ld a,16
    ld (tank_delay),a
    ret

bridge_scene_active:
    ; A=nonzero while a bridge occupies or is queued for the scene: an intact
    ; or pending span, or the destroyed road still scrolling through.
    ld a,(bridge_spawn_pending)
    ld b,a
    ld a,(bridge_active)
    or b
    ld b,a
    ld a,(destroyed_road_active)
    or b
    ret

maybe_fire_bridge_tank:
    ld a,(bridge_tank_fire_timer)
    or a
    jr z,bridge_tank_fire_timer_elapsed
    dec a
    ld (bridge_tank_fire_timer),a
    ret
bridge_tank_fire_timer_elapsed:
    ld a,(tank_shell_active)
    or a
    ret nz
    ld a,48
    ld (bridge_tank_fire_timer),a
    ld a,(bridge_tank_y)
    ld (firing_tank_y),a
    ld a,(bridge_tank_side)
    ld (firing_tank_side),a
    jr fire_selected_tank

maybe_fire_tank:
    ld a,(tank_fire_timer)
    or a
    jr z,tank_fire_timer_elapsed
    dec a
    ld (tank_fire_timer),a
    ret
tank_fire_timer_elapsed:
    ; A single shell may exist at once. Leave an elapsed timer at zero while
    ; that shell is active; if the tank is still visible when it disappears,
    ; the next shot can begin immediately instead of losing a firing cycle.
    ld a,(tank_shell_active)
    or a
    ret nz
    ld a,96
    ld (tank_fire_timer),a
    ld a,(tank_y)
    ld (firing_tank_y),a
    ld a,(tank_side)
    ld (firing_tank_side),a

fire_selected_tank:
    call start_tank_shot_sound
    ld a,(firing_tank_y)
    add a,4
    ld (tank_shell_y),a
    ld a,(firing_tank_y)
    call get_bounds_for_y
    ld a,(firing_tank_side)
    or a
    jr nz,fire_tank_from_right_bank

    ; D is the last left-bank byte. Start in the first complete water byte
    ; and travel toward the centre of the river.
    ld a,d
    inc a
    add a,a
    add a,a
    add a,a
    ld (tank_shell_x),a
    ld a,1
    ld (tank_shell_dir),a
    jr activate_tank_shell
fire_tank_from_right_bank:
    ; E is the right-bank edge. A two-pixel shell begins immediately before
    ; it and travels left, again entering water rather than crossing land.
    ld a,e
    add a,a
    add a,a
    add a,a
    sub 2
    ld (tank_shell_x),a
    ld a,255
    ld (tank_shell_dir),a
activate_tank_shell:
    ; Aim at the player's current centre, clamped to the adjacent navigable
    ; branch. The shot therefore visibly tracks the jet but still has a finite
    ; water landing point, even when an island splits the river.
    ld c,0
    ld a,(firing_tank_side)
    or a
    jr z,tank_shell_lane_selected
    dec c                            ; 255 selects the right fork branch
tank_shell_lane_selected:
    ld a,(firing_tank_y)
    add a,4
    call get_pixel_lane_bounds
    ld a,(player_x)
    add a,8
    ld b,a
    ld a,d
    add a,8
    cp b
    jr c,tank_target_above_minimum
    jr z,tank_target_above_minimum
    ld b,a
tank_target_above_minimum:
    ld a,e
    add a,8
    cp b
    jr nc,tank_target_below_maximum
    ld b,a
tank_target_below_maximum:
    ld a,b
    ld (tank_shell_target_x),a
    ld a,1
    ld (tank_shell_active),a
    ret

update_tank_shell:
    ld a,(tank_shell_active)
    or a
    ret z
    cp 2
    jr z,update_tank_splash

    ; The shell stays on its world scanline while the scenery scrolls. Its
    ; independent horizontal component is four real pixels per frame. The gun
    ; fires less often, but each shell becomes an immediate, sharper threat.
    ld a,(speed_pixels)
    ld b,a
    ld a,(tank_shell_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr nc,remove_tank_shell
    ld (tank_shell_y),a

    ld a,(tank_shell_dir)
    cp 255
    jr z,move_tank_shell_left
    ld a,(tank_shell_x)
    add a,4
    jr c,remove_tank_shell
    ld (tank_shell_x),a
    ld b,a
    ld a,(tank_shell_target_x)
    cp b
    jr c,land_tank_shell
    jr z,land_tank_shell
    ret
move_tank_shell_left:
    ld a,(tank_shell_x)
    cp 4
    jr c,remove_tank_shell
    sub 4
    ld (tank_shell_x),a
    ld b,a
    ld a,(tank_shell_target_x)
    cp b
    jr nc,land_tank_shell
    ret

land_tank_shell:
    ld a,(tank_shell_target_x)
    ld (tank_shell_x),a
    call start_ay_splash
    ld a,10
    ld (tank_splash_timer),a
    ld a,2
    ld (tank_shell_active),a
    ret

update_tank_splash:
    ; The splash belongs to the same world line as the water beneath it.
    ld a,(speed_pixels)
    ld b,a
    ld a,(tank_shell_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr nc,remove_tank_shell
    ld (tank_shell_y),a
    ld a,(tank_splash_timer)
    dec a
    ld (tank_splash_timer),a
    ret nz
remove_tank_shell:
    xor a
    ld (tank_shell_active),a
    ret

calc_tank_col:
    ; Input A=Y. Uses tank_side. Returns a two-byte full-land position.
    call get_bounds_for_y
    ld a,(tank_side)
    or a
    jr nz,tank_on_right
    ld a,d
    cp 3
    jr nc,tank_left_has_room
    xor a
    ret
tank_left_has_room:
    sub 3
    ret
tank_on_right:
    ld a,e
    add a,2
    cp 31
    ret c
    ld a,30
    ret

update_bridge:
    call update_destroyed_road
    ld a,(bridge_spawn_pending)
    or a
    jr z,advance_active_bridge
    xor a
    ld (bridge_spawn_pending),a
    ld a,1
    ld (bridge_active),a
    xor a
    ld (destroyed_road_active),a
    ; Anchor the band on the block boundary: the newest block occupies rows
    ; 0..phase, so the two latched flat blocks begin at exactly phase+1.
    ld a,(course_phase)
    inc a
    ld (bridge_y),a
    call get_bounds_for_y
    ld a,d
    ld (bridge_col),a
    ld b,a
    ld a,e
    sub b
    inc a
    ld (bridge_width),a
    call setup_bridge_tank
    ld b,16
    ld c,255
    xor a
    call bridge_fill_rows
    call bridge_paint_road_attributes
    ret

setup_bridge_tank:
    ; An intact bridge is always a road, never a firing position. Its tank
    ; enters in pending mode 3 and becomes a crossing mode-1 actor when visible.
    ; Only destruction can later convert a survivor on an approach to mode 2.
    xor a
    ld (bridge_tank_active),a
    ld a,(bridge_tank_side)
    xor 1
    ld (bridge_tank_side),a
    ld a,3
    ld (bridge_tank_mode),a
    ret
advance_active_bridge:
    ld a,(bridge_active)
    or a
    ret z
    ld a,(speed_pixels)
    or a
    ret z

    ; Remove only the rows which leave the top. Clearing the broad band is
    ; followed by an exact bank/island reconstruction for those scanlines.
    ld a,(bridge_y)
    ld (bridge_restore_y),a
    ld a,(speed_pixels)
    ld (bridge_restore_rows),a
    ld b,a
    ld c,0
    ld a,(bridge_y)
    call bridge_fill_rows
bridge_restore_top:
    ld a,(bridge_restore_rows)
    or a
    jr z,bridge_top_restored
    ld a,(bridge_restore_y)
    cp PLAYFIELD_BOTTOM
    jr nc,bridge_top_restored
    ld (dirty_y),a
    call render_v3_row
    ld a,(bridge_restore_y)
    inc a
    ld (bridge_restore_y),a
    ld a,(bridge_restore_rows)
    dec a
    ld (bridge_restore_rows),a
    jr bridge_restore_top

bridge_top_restored:
    ld a,(speed_pixels)
    ld b,a
    ld a,(bridge_y)
    add a,b
    cp PLAYFIELD_BOTTOM
    jr c,store_bridge_y
    ; No new bridge span remains on screen, so clear its last colour cells.
    call bridge_clear_road_attributes
    xor a
    ld (bridge_active),a
    ld (bridge_tank_mode),a
    ld (bridge_tank_active),a
    ret
store_bridge_y:
    ld (bridge_y),a

    ; The new bottom rows begin just below the old 16-line envelope.
    ld a,(bridge_y)
    add a,16
    ld l,a
    ld a,(speed_pixels)
    ld b,a
    ld a,l
    sub b
    ld l,a
    ld c,255
    ld a,l
    call bridge_fill_rows

    ; Repaint the ends which may have been touched by this frame's bank pass.
    ld a,(bridge_y)
    call bridge_refresh_edges
    ld a,0x4a                       ; intact bridge keeps BRIGHT blue paper
    ld (bridge_center_attr),a
    call bridge_update_attributes
#if not TIMEX_HICOLOR
    jp update_standard_road_lines
#else
    ret
#endif

update_destroyed_road:
    ; After the span is blown away, both white approaches remain part of the
    ; world and keep scrolling. With no centre marking they need no bitmap
    ; work at all: the approaches are ordinary land under white attributes.
    ld a,(destroyed_road_active)
    or a
    ret z
    ld a,(speed_pixels)
    or a
    ret z

    ld b,a
    ld a,(bridge_y)
    add a,b
    ld (bridge_y),a

    ld a,0x4c                       ; fixed BRIGHT-blue water after destruction
    ld (bridge_center_attr),a
    call bridge_update_attributes
#if not TIMEX_HICOLOR
    call update_standard_road_lines
#endif
    ld a,(bridge_y)
    cp PLAYFIELD_BOTTOM
    ret c
    xor a
    ld (destroyed_road_active),a
    ret

#if not TIMEX_HICOLOR
; ---------------------------------------------------------------------------
; Standard-build road lines. The road keeps terrain-green ink over black
; paper, so its look comes from the bitmap: solid black edge lines at band
; rows 1 and 14, over the land approaches only - the span and the destroyed
; span's water are never touched.
; ---------------------------------------------------------------------------
update_standard_road_lines:
    ; Repaint both edge rows at their new positions each frame and restore
    ; the rows they vacated. A vacated row inside the band becomes solid
    ; road; one that left through the top is plain approach land, so the
    ; same 0xff fill is correct for both.
    ld a,(speed_pixels)
    or a
    ret z
    ld a,1
    call restore_standard_road_line
    ld a,14
    call restore_standard_road_line
    ld a,1
    call draw_standard_road_edge
    ld a,14
    jp draw_standard_road_edge

restore_standard_road_line:
    ld c,a
    ld a,(speed_pixels)
    ld b,a
    ld a,(bridge_y)
    add a,c
    sub b                           ; previous screen row of this band row
    ld c,255
    jr standard_road_line_row
draw_standard_road_edge:
    ld c,a
    ld a,(bridge_y)
    add a,c
    ld c,0
standard_road_line_row:
    ; A=screen row, C=value: 255 restores solid land, 0 draws the line.
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    call calc_screen_line_addr
    ld a,(bridge_col)
    or a
    jr z,standard_road_line_right
    ld b,a
    call standard_road_line_segment
standard_road_line_right:
    ld a,(bridge_width)
    add a,l
    ld l,a
    ld a,(bridge_col)
    ld b,a
    ld a,(bridge_width)
    add a,b
    ld b,a
    ld a,32
    sub b
    ret z
    ld b,a
standard_road_line_segment:
    ; HL=screen ptr, B=byte count, C=value.
    ld (hl),c
    inc l
    djnz standard_road_line_segment
    ret
#endif

bridge_fill_full_bitmap_row:
    ; Input A=Y, C=byte. Road rows are inside a bridge band, so land plus
    ; bridge makes the complete 256-pixel scanline solid.
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    call calc_screen_line_addr
    ld b,4
    ld a,c
bridge_full_bitmap_byte:
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
    djnz bridge_full_bitmap_byte
    ret

update_bullet:
    ld a,(fire_pending)
    or a
    jr z,update_existing_bullet
    xor a
    ld (fire_pending),a
    ld a,1
    ld (bullet_active),a
    ret
update_existing_bullet:
    ld a,(bullet_active)
    or a
    ret z
    ld a,(bullet_y)
    ; The projectile may reach Y=16, but never enters either protected margin.
    cp 22
    jr nc,move_bullet_up
    xor a
    ld (bullet_active),a
    ret
move_bullet_up:
    sub 6
    ld (bullet_y),a

    ; Test the swept 10-line interval (6 pixels of travel plus the 4-pixel
    ; projectile) so a fast bullet cannot tunnel through an eight-line ship.
    call bullet_hits_fuel
    or a
    ret nz
    call bullet_hits_balloon
    or a
    ret nz
    call bullet_hits_ship0
    or a
    ret nz
    call bullet_hits_ship1
    or a
    ret nz
    call bullet_hits_helicopter
    or a
    ret nz
    call bullet_hits_enemy_plane
    or a
    ret nz

    ; Actor sprites are absent from the bitmap during collision, so the
    ; crossing aircraft is tested explicitly above. Bridge geometry is also
    ; explicit because a background hit on it must award points and destroy it.
    ld a,(bridge_active)
    or a
    jp z,bullet_checks_destroyed_road
    ld a,(bullet_y)
    add a,10                        ; swept projectile bottom
    ld b,a
    ld a,(bridge_y)
    cp b
    jp nc,bullet_hits_background
    add a,16
    ld b,a
    ld a,(bullet_y)
    cp b
    jp nc,bullet_hits_background

    ld a,(bridge_col)
    add a,a
    add a,a
    add a,a
    ld b,a
    ld a,(bullet_x)
    add a,8
    cp b
    jp c,bullet_background_collision ; white road left of the bridge span
    ld a,(bridge_col)
    ld b,a
    ld a,(bridge_width)
    add a,b
    add a,a
    add a,a
    add a,a
    ld b,a
    ld a,(bullet_x)
    add a,7
    cp b
    jp nc,bullet_background_collision ; white road right of the bridge span

    call destroy_bridge
    xor a
    ld (bullet_active),a
    ret

bullet_checks_destroyed_road:
    ; White approaches keep scrolling after the bridge span is gone. They are
    ; solid land in the bitmap, so this explicit band test only keeps the
    ; award/impact semantics of hitting a road distinct from a plain bank.
    ld a,(destroyed_road_active)
    or a
    jp z,bullet_hits_background
    ld a,(bullet_y)
    add a,10
    ld b,a
    ld a,(bridge_y)
    cp b
    jp nc,bullet_hits_background
    add a,16
    ld b,a
    ld a,(bullet_y)
    cp b
    jp nc,bullet_hits_background

    ld a,(bridge_col)
    add a,a
    add a,a
    add a,a
    ld b,a
    ld a,(bullet_x)
    add a,8
    cp b
    jp c,bullet_background_collision
    ld a,(bridge_col)
    ld b,a
    ld a,(bridge_width)
    add a,b
    add a,a
    add a,a
    add a,a
    ld b,a
    ld a,(bullet_x)
    add a,7
    cp b
    jp nc,bullet_background_collision
    jp bullet_hits_background

bullet_hits_background:
    ; Query pure world geometry rather than the framebuffer, which intentionally
    ; still contains resident sprites. Actors were tested explicitly above, and
    ; this path never overlaps an intact bridge/road band, so course blocks are
    ; the only geometry layer. A block shares one terrain row across its eight
    ; scanlines, so the ten-line swept interval needs at most three block tests
    ; instead of a byte pair per scanline.
    ld a,(bullet_x)
    add a,7
    ld c,a
    and 7
    add a,a
    ld e,a
    ld d,0
    ld hl,projectile_mask_table
    add hl,de
    ld a,(hl)
    ld (bullet_background_mask_0),a
    inc hl
    ld a,(hl)
    ld (bullet_background_mask_1),a
    ld a,c
    srl a
    srl a
    srl a
    ld (bullet_background_col),a
    ld a,(bullet_y)
    ld (bullet_background_y),a
    ld a,10
    ld (bullet_background_rows),a
bullet_background_block:
    ld a,(bullet_background_y)
    cp PLAYFIELD_BOTTOM
    jr nc,bullet_background_collision
    call get_block_index_for_y
    ld a,(bullet_background_col)
    ld c,a
    ld a,l
    call block_bitmap_address
    ld a,(hl)
    ld b,a
    ld a,(bullet_background_mask_0)
    and b
    jr nz,bullet_background_collision
    inc hl
    ld a,(hl)
    ld b,a
    ld a,(bullet_background_mask_1)
    and b
    jr nz,bullet_background_collision
    ; Skip straight to the first scanline of the next course block.
    ld a,(course_phase)
    ld b,a
    ld a,(bullet_background_y)
    add a,7
    sub b
    and 7
    ld b,a
    ld a,8
    sub b                           ; scanlines left in this block: 1..8
    ld b,a
    ld a,(bullet_background_rows)
    sub b
    ret z
    ret c                           ; swept interval ends inside this block
    ld (bullet_background_rows),a
    ld a,(bullet_background_y)
    add a,b
    ld (bullet_background_y),a
    jr bullet_background_block
bullet_background_collision:
    xor a
    ld (bullet_active),a
    ret

bullet_hits_fuel:
    ld a,(fuel_active)
    or a
    ret z
    ld a,(fuel_x)
    ld c,a
    ld e,8
    ld a,(fuel_y)
    ld b,32
    call bullet_hits_actor
    or a
    ret z
    ld a,(fuel_y)
    ld b,a
    ld a,(fuel_x)
    call start_hit_explosion
    xor a
    ld (bullet_active),a
    ld (fuel_active),a
    ld a,96
    ld (fuel_delay),a
    call add_score_100
    ld a,1
    ret

bullet_hits_balloon:
    ld a,(balloon_active)
    or a
    ret z
    ld a,(balloon_x)
    ld c,a
    ld e,16
    ld a,(balloon_y)
    ld b,20
    call bullet_hits_actor
    or a
    ret z
    ld a,(balloon_y)
    ld b,a
    ld a,(balloon_x)
    call start_hit_explosion
    xor a
    ld (bullet_active),a
    ld (balloon_active),a
    ld a,180
    ld (balloon_delay),a
    call add_score_100
    ld a,1
    ret

bullet_hits_ship0:
    ld a,(ship0_active)
    or a
    ret z
    ld a,(ship0_x)
    ld c,a
    ld e,32
    ld a,(ship0_y)
    ld b,8
    call bullet_hits_actor
    or a
    ret z
    ld a,(ship0_y)
    ld b,a
    ld a,(ship0_x)
    add a,8                         ; centre 16-pixel blast on 32-pixel hull
    call start_hit_explosion
    xor a
    ld (bullet_active),a
    ld (ship0_active),a
    ld a,160
    ld (ship0_delay),a
    call add_score_100
    ld a,1
    ret

bullet_hits_ship1:
    ld a,(ship1_active)
    or a
    ret z
    ld a,(ship1_x)
    ld c,a
    ld e,32
    ld a,(ship1_y)
    ld b,8
    call bullet_hits_actor
    or a
    ret z
    ld a,(ship1_y)
    ld b,a
    ld a,(ship1_x)
    add a,8
    call start_hit_explosion
    xor a
    ld (bullet_active),a
    ld (ship1_active),a
    ld a,160
    ld (ship1_delay),a
    call add_score_100
    ld a,1
    ret

bullet_hits_actor:
    ; Input A=target Y, B=height, C=target X, E=width. The bullet's two solid
    ; centre pixels are represented by X+8; its vertical interval includes
    ; both the previous and new positions to prevent high-speed tunnelling.
    ld d,a
    add a,b
    ld b,a
    ld a,(bullet_y)
    cp b
    jr nc,bullet_missed_actor
    add a,10
    ld b,a
    ld a,d
    cp b
    jr nc,bullet_missed_actor

    ld a,(bullet_x)
    add a,8
    ld d,a
    ld a,c
    cp d
    jr z,bullet_actor_left_ok
    jr nc,bullet_missed_actor
bullet_actor_left_ok:
    ld a,c
    add a,e
    cp d
    jr c,bullet_missed_actor
    jr z,bullet_missed_actor
    ld a,1
    ret
bullet_missed_actor:
    xor a
    ret

bullet_hits_helicopter:
    ld a,(helicopter_active)
    or a
    ret z
    ld a,(bullet_y)
    ld d,a
    ld a,(helicopter_y)
    add a,10
    cp d
    jr c,bullet_missed_helicopter
    jr z,bullet_missed_helicopter
    ld a,d
    add a,10
    ld d,a
    ld a,(helicopter_y)
    cp d
    jr nc,bullet_missed_helicopter

    ; Only the two central set pixels of the 16-pixel bullet are solid.
    ld a,(bullet_x)
    add a,8
    ld d,a
    ld a,(helicopter_x)
    cp d
    jr c,bullet_right_of_helicopter_left
    jr z,bullet_right_of_helicopter_left
    jr bullet_missed_helicopter
bullet_right_of_helicopter_left:
    ld a,(helicopter_x)
    add a,16
    cp d
    jr c,bullet_missed_helicopter
    jr z,bullet_missed_helicopter

    ld a,(helicopter_y)
    ld b,a
    ld a,(helicopter_x)
    call start_hit_explosion
    xor a
    ld (bullet_active),a
    ld (helicopter_active),a
    ld a,160
    ld (helicopter_delay),a
    call add_score_100
    ld a,1
    ret
bullet_missed_helicopter:
    xor a
    ret

bullet_hits_enemy_plane:
    ; The plane is allowed over land, so water-only projectile testing cannot
    ; stand in for a sprite collision. A forgiving 16x8 box makes the fast,
    ; three-pixel crossing target practical to hit.
    ld a,(enemy_plane_active)
    or a
    ret z
    ld a,(enemy_plane_x)
    ld c,a
    ld e,16
    ld a,(enemy_plane_y)
    ld b,8
    call bullet_hits_actor
    or a
    ret z
    ld a,(enemy_plane_y)
    ld b,a
    ld a,(enemy_plane_x)
    call start_hit_explosion
    xor a
    ld (bullet_active),a
    ld (enemy_plane_active),a       ; one crossing aircraft per scene/life
    dec a
    ld (enemy_plane_delay),a        ; 255 prevents an in-life respawn
    call add_score_100
    ld a,1
    ret

add_score_100:
    ; Six display digits are kept directly as ASCII. Enemy values are fixed
    ; multiples of 100, so carrying from the hundreds column is much cheaper
    ; than converting a binary score through division every HUD update.
    ld hl,score_digit_3
    ld b,4
add_score_100_digit:
    ld a,(hl)
    inc a
    cp 58
    jr c,store_score_digit
    ld (hl),48
    dec hl
    djnz add_score_100_digit
    ld c,4
    jr score_changed
store_score_digit:
    ld (hl),a
    ld a,5
    sub b
    ld c,a                          ; number of right-aligned changed digits
score_changed:
    ld a,(score_redraw_count)
    cp c
    jr nc,score_redraw_count_ready
    ld a,c
    ld (score_redraw_count),a
score_redraw_count_ready:
    ld a,(hud_dirty)
    or 2
    ld (hud_dirty),a
    ret

destroy_bridge:
    ; A bridge is worth 200 points. Only a crossing tank whose hull actually
    ; overlaps the centre span is destroyed for the 500-point combined hit.
    ; A tank still on an approach survives and becomes a firing road tank only
    ; after the span has been destroyed.
    ld a,(bridge_y)
    add a,2
    ld b,a
    ld a,(bullet_x)
    call start_hit_explosion          ; bitmap burst plus channel-C explosion
    call add_score_100
    call add_score_100
    call destroy_bridge_tank_bonus
    call bridge_paint_destroyed_road_attributes
    ld a,(bridge_y)
    ld (bridge_restore_y),a
    ld a,16
    ld (bridge_restore_rows),a
destroy_bridge_restore:
    ld a,(bridge_restore_rows)
    or a
    jr z,destroy_bridge_done
    ld a,(bridge_restore_y)
    cp PLAYFIELD_BOTTOM
    jr nc,destroy_bridge_done
    ; render_v3_row normally assumes that all bank interiors are already set.
    ; The solid span violates that invariant, so clear the complete scanline
    ; and use the deliberately slower full-row world reconstruction here.
    ld c,0
    call bridge_fill_full_bitmap_row
    ld a,(bridge_restore_y)
    call render_full_world_row
    ld a,(bridge_restore_y)
    inc a
    ld (bridge_restore_y),a
    ld a,(bridge_restore_rows)
    dec a
    ld (bridge_restore_rows),a
    jr destroy_bridge_restore
destroy_bridge_done:
    xor a
    ld (bridge_active),a
    ld a,1
    ld (destroyed_road_active),a
    jp preserve_road_tank_after_bridge

preserve_road_tank_after_bridge:
    ; destroy_bridge_tank_bonus has already removed a mode-1 tank if it was on
    ; the span. A crossing tank still on an approach stops there and becomes a
    ; firing road tank. Mode 2 cannot exist before bridge destruction.
    ld a,(bridge_tank_active)
    or a
    jr z,cancel_pending_destroyed_bridge_tank
    ld a,(bridge_tank_mode)
    cp 1
    ret nz
    ld a,2
    ld (bridge_tank_mode),a
    ld a,12
    ld (bridge_tank_fire_timer),a
    ret
cancel_pending_destroyed_bridge_tank:
    ; Mode 3 has not reached the visible road yet and must not materialise
    ; after their bridge has disappeared.
    xor a
    ld (bridge_tank_mode),a
    ret

destroy_bridge_tank_bonus:
    ld a,(bridge_tank_active)
    or a
    ret z
    ld a,(bridge_tank_mode)
    cp 1
    ret nz

    ; Half-open pixel intervals: tank [x,x+16), bridge
    ; [bridge_col*8,(bridge_col+width)*8). Y is locked to the road.
    ld a,(bridge_tank_x)
    add a,16
    ld b,a
    ld a,(bridge_col)
    add a,a
    add a,a
    add a,a
    cp b
    ret nc
    ld a,(bridge_col)
    ld b,a
    ld a,(bridge_width)
    add a,b
    add a,a
    add a,a
    add a,a
    ld b,a
    ld a,(bridge_tank_x)
    cp b
    ret nc

    xor a
    ld (bridge_tank_active),a
    ld (bridge_tank_mode),a
    call add_score_100
    call add_score_100
    jp add_score_100

object_overlaps_bridge:
    ; Input A=object Y, B=height. The forbidden vertical interval extends
    ; eight pixels above and below the 16-line bridge. This visual clearance
    ; prevents a hull from appearing to scrape a bridge without overlapping.
    ld c,a
    add a,b
    ld d,a
    ld a,(bridge_y)
    cp 8
    jr nc,bridge_lower_bound_on_screen
    xor a
    jr bridge_lower_bound_ready
bridge_lower_bound_on_screen:
    sub 8
bridge_lower_bound_ready:
    cp d
    jr nc,object_misses_bridge
    ld a,(bridge_y)
    add a,24
    ld d,a
    ld a,c
    cp d
    jr nc,object_misses_bridge
    ld a,1
    ret
object_misses_bridge:
    xor a
    ret

keep_water_objects_off_bridge:
    ; Watercraft never share the bridge's vertical band. The tank is omitted
    ; deliberately, so it may remain on land next to or over the bridge.
    ld a,(bridge_active)
    or a
    ret z
    ld a,(ship0_active)
    or a
    jr z,check_ship1_bridge
    ld a,(ship0_y)
    ld b,8
    call object_overlaps_bridge
    or a
    jr z,check_ship1_bridge
    call relocate_ship0
check_ship1_bridge:
    ld a,(ship1_active)
    or a
    jr z,check_helicopter_bridge
    ld a,(ship1_y)
    ld b,8
    call object_overlaps_bridge
    or a
    jr z,check_helicopter_bridge
    call relocate_ship1
check_helicopter_bridge:
    ld a,(helicopter_active)
    or a
    jr z,check_balloon_bridge
    ld a,(helicopter_y)
    ld b,10
    call object_overlaps_bridge
    or a
    jr z,check_balloon_bridge
    call relocate_helicopter
check_balloon_bridge:
    ld a,(balloon_active)
    or a
    jr z,check_fuel_bridge
    ld a,(balloon_y)
    ld b,20
    call object_overlaps_bridge
    or a
    jr z,check_fuel_bridge
    call relocate_balloon
check_fuel_bridge:
    ld a,(fuel_active)
    or a
    jr z,check_shore_tank_bridge
    ld a,(fuel_y)
    ld b,32
    call object_overlaps_bridge
    or a
    jr z,check_shore_tank_bridge
    call relocate_fuel
check_shore_tank_bridge:
    ; The bridge owns its road and its dedicated bridge tank. A shore gun that
    ; reaches the same vertical band leaves cleanly instead of being composited
    ; over the road.
    ld a,(tank_active)
    or a
    ret z
    ld a,(tank_y)
    ld b,10
    call object_overlaps_bridge
    or a
    ret z
    xor a
    ld (tank_active),a
    ld a,16
    ld (tank_delay),a
    ret

relocate_ship0:
    ; Never teleport an actor to a free lane in the middle of the screen. A
    ; bridge conflict removes it cleanly and the ordinary top-entry path retries.
    xor a
    ld (ship0_active),a
    ld a,16
    ld (ship0_delay),a
    ret

relocate_ship1:
    xor a
    ld (ship1_active),a
    ld a,16
    ld (ship1_delay),a
    ret

relocate_helicopter:
    xor a
    ld (helicopter_active),a
    ld a,16
    ld (helicopter_delay),a
    ret

relocate_balloon:
    xor a
    ld (balloon_active),a
    ld a,16
    ld (balloon_delay),a
    ret

relocate_fuel:
    xor a
    ld (fuel_active),a
    ld a,16
    ld (fuel_delay),a
    ret

check_player_collision:
#if AUTOPILOT
    ret                             ; the benchmark flight is invulnerable
#endif
    ; The shell uses the same forgiving 6x6 player core as moving enemies,
    ; but its collision rectangle is the actual two-pixel projectile. Explicit
    ; actor checks precede the pure bank/island/bridge geometry test. The common
    ; compositor has already committed these current coordinates to the bitmap.
    ld a,(tank_shell_active)
    cp 1                            ; the harmless splash cannot kill the jet
    jr nz,check_player_ship0
    ld a,2
    ld (object_collision_width),a
    ld a,(tank_shell_x)
    ld c,a
    ld a,(tank_shell_y)
    ld b,2
    call player_overlaps_object
    jp c,player_crashed

check_player_ship0:
    ; The Atari hull has transparent bow/stern corners and a very narrow mast.
    ; Use its solid central hull instead of a lethal invisible 32x8 rectangle.
    ld a,24
    ld (object_collision_width),a
    ld a,(ship0_active)
    or a
    jr z,check_player_ship1
    ld a,(ship0_x)
    add a,4
    ld c,a
    ld a,(ship0_y)
    add a,3
    ld b,5
    call player_overlaps_object
    jp c,player_crashed
check_player_ship1:
    ld a,(ship1_active)
    or a
    jr z,check_player_balloon
    ld a,(ship1_x)
    add a,4
    ld c,a
    ld a,(ship1_y)
    add a,3
    ld b,5
    call player_overlaps_object
    jp c,player_crashed
check_player_balloon:
    ld a,12
    ld (object_collision_width),a
    ld a,(balloon_active)
    or a
    jr z,check_player_enemy_plane
    ld a,(balloon_x)
    add a,2
    ld c,a
    ld a,(balloon_y)
    inc a
    ld b,18
    call player_overlaps_object
    jp c,player_crashed
check_player_enemy_plane:
    ld a,12
    ld (object_collision_width),a
    ld a,(enemy_plane_active)
    or a
    jr z,check_player_helicopter
    ld a,(enemy_plane_x)
    add a,2
    ld c,a
    ld a,(enemy_plane_y)
    add a,2
    ld b,5
    call player_overlaps_object
    jp c,player_crashed
check_player_helicopter:
    ld a,(helicopter_active)
    or a
    jr z,check_player_bridge_tank
    ld a,(helicopter_x)
    add a,2
    ld c,a
    ld a,(helicopter_y)
    add a,2
    ld b,7
    call player_overlaps_object
    jp c,player_crashed
check_player_bridge_tank:
    ; The ordinary shore tank is deliberately absent here: it remains on
    ; lethal land which the bitmap test below rejects. Only its flying
    ; shell can hit a player who stays over water. A bridge tank is different,
    ; because its route may place it directly across the player's path.
    ld a,(bridge_tank_active)
    or a
    jr z,check_player_background
    ld a,12
    ld (object_collision_width),a
    ld a,(bridge_tank_x)
    add a,2
    ld c,a
    ld a,(bridge_tank_y)
    inc a
    ld b,8
    call player_overlaps_object
    jp c,player_crashed
check_player_background:
    ; All potentially resident sprite pixels have now been handled explicitly.
    ; Remaining set bits mean bank, island or an intact bridge.
    call check_player_background_pixels
    ret nc
player_crashed:
    ld a,1
    ld (crashed),a
    jp erase_current_player_for_crash

check_player_background_pixels:
    ; Resident sprites make framebuffer sampling ambiguous. Test the forgiving
    ; 6x6 player core directly against exact pixel bank bounds, islands and the
    ; intact bridge instead. This is independent of both bitmap renderers.
    ld a,(player_x)
    add a,5
    ld (player_core_left),a
    add a,6
    ld (player_core_right),a         ; exclusive
    ld a,(player_y)
    add a,4
    ld (player_core_y),a
    ld a,6
    ld (player_core_rows),a

    ld a,(bridge_active)
    or a
    jr z,player_world_prepare
    ld a,(player_core_y)
    ld b,a
    add a,6
    ld c,a                           ; player bottom exclusive
    ld a,(bridge_y)
    cp c
    jr nc,player_world_prepare
    add a,16
    cp b
    jr c,player_world_prepare
    jr z,player_world_prepare
    jr player_background_hit

player_world_prepare:
    ; The six-pixel core crosses at most one eight-line block boundary. Resolve
    ; its first block once, then carry the residue and circular index through
    ; the remaining rows instead of repeating get_block_index_for_y six times.
    ld a,(player_core_y)
    call get_block_index_for_y
    ld a,l
    ld (player_core_block_index),a
    ld a,(player_core_y)
    add a,7
    ld b,a
    ld a,(course_phase)
    ld c,a
    ld a,b
    sub c
    and 7
    ld (player_core_block_residue),a

player_world_row:
    ld a,(player_core_block_index)
    ld l,a
    ld h,HIGH(block_left_x)
    ld a,(player_core_left)
    cp (hl)
    jr c,player_background_hit
    ld h,HIGH(block_right_x)
    ld a,(player_core_right)
    cp (hl)
    jr c,player_world_check_island
    jr z,player_world_check_island
    jr player_background_hit

player_world_check_island:
    ld h,HIGH(block_island_left)
    ld a,(hl)
    cp 255
    jr z,player_world_next_row
    add a,a
    add a,a
    add a,a
    ld b,a                           ; island left
    ld h,HIGH(block_island_right)
    ld a,(hl)
    inc a
    add a,a
    add a,a
    add a,a
    ld c,a                           ; island right exclusive
    ld a,(player_core_left)
    cp c
    jr nc,player_world_next_row
    ld a,(player_core_right)
    cp b
    jr c,player_world_next_row
    jr z,player_world_next_row
    jr player_background_hit

player_world_next_row:
    ld a,(player_core_y)
    inc a
    ld (player_core_y),a
    ld a,(player_core_rows)
    dec a
    ld (player_core_rows),a
    jr z,player_world_clear
    ld a,(player_core_block_residue)
    inc a
    and 7
    ld (player_core_block_residue),a
    jr nz,player_world_row
    ld a,(player_core_block_index)
    dec a
    and 31
    ld (player_core_block_index),a
    jr player_world_row
player_world_clear:
    or a
    ret
player_background_hit:
    xor a
    cp 1
    ret

player_overlaps_object:
    ; Input A=object Y, B=height, C=object pixel X. object_collision_width is
    ; the actor's deliberately inset solid-body width. The player's forgiving
    ; 6x6 central core avoids deaths caused by transparent sprite corners.
    ld d,a
    add a,b
    ld e,a
    ld a,(player_y)
    add a,4
    ld b,a
    cp e
    jr nc,player_object_miss
    add a,6
    ld e,a
    ld a,d
    cp e
    jr nc,player_object_miss

    ld a,(player_x)
    add a,5
    ld d,a
    add a,6
    ld e,a
    ld a,c
    ld b,a
    ld a,(object_collision_width)
    add a,b
    cp d
    jr c,player_object_miss
    jr z,player_object_miss
    ld a,c
    cp e
    jr nc,player_object_miss
    xor a
    cp 1
    ret
player_object_miss:
    or a
    ret
