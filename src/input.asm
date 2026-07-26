; ---------------------------------------------------------------------------
; Keyboard and border profiling
; ---------------------------------------------------------------------------

read_keyboard:
#if AUTOPILOT
    ; Benchmark build: permanent fast scroll, refire the moment the bullet
    ; slot frees up, and weave left/right in 32-frame halves so the full
    ; steering recomposition path is exercised too.
    ld a,(autopilot_steer_phase)
    inc a
    ld (autopilot_steer_phase),a
    and 32
    ld a,1
    jr z,autopilot_steer_ready
    ld a,255
autopilot_steer_ready:
    ld (player_move),a
    xor a
    ld (joystick_state),a
    ld (slow_phase),a
    ld a,2
    ld (requested_speed),a
    ld (speed_pixels),a
#if AUTOPILOT_NOFIRE
    ; Screenshot benches keep the plane silent so an intact bridge survives
    ; long enough to be frozen and inspected.
    ret
#endif
    ld a,(bullet_active)
    or a
    ret nz
    ld a,(fire_pending)
    or a
    ret nz
    ld a,(player_x)
    ld (bullet_x),a
    ld a,(player_y)
    sub 4
    ld (bullet_y),a
    call start_missile_sound        ; the original's descending sweep
    ld a,1
    ld (fire_pending),a
    ret
#endif
    xor a
    ld (player_move),a

    ; Base speed is 1 px/frame. Q requests fast scrolling; A requests
    ; 0.5 px by alternating zero- and one-pixel scroll frames.
    ld a,1
    ld (requested_speed),a
    ld bc,0xfbfe
    in a,(c)
    ld e,a                           ; preserve the shared Q/T/Y/U/I/O/R row
    bit 0,a
    jr nz,read_slow_key
    ld a,2
    ld (requested_speed),a
read_slow_key:
    ld bc,0xfdfe
    in a,(c)
    bit 0,a
    jr nz,read_kempston
    ld a,(requested_speed)
    cp 2
    jr z,read_kempston
    xor a
    ld (requested_speed),a

read_kempston:
    ; Kempston: bit 0 right, 1 left, 2 down, 3 up, 4 fire. A floating
    ; all-ones port is treated as no joystick rather than five held controls.
    ld bc,0x001f
    in a,(c)
    and 31
    cp 31
    jr nz,store_kempston
    xor a
store_kempston:
    ld (joystick_state),a
    bit 3,a
    jr z,kempston_not_fast
    ld a,2
    ld (requested_speed),a
    jr resolve_requested_speed
kempston_not_fast:
    bit 2,a
    jr z,resolve_requested_speed
    ld a,(requested_speed)
    cp 2
    jr z,resolve_requested_speed
    xor a
    ld (requested_speed),a

resolve_requested_speed:
    ld a,(requested_speed)
    or a
    jr z,resolve_slow_speed
    cp 2
    jr z,resolve_fast_speed

    ; Normal speed also resets the slow cadence generator.
    ld (speed_pixels),a
    xor a
    ld (slow_phase),a
    jr read_steering

resolve_fast_speed:
    ; Fast scroll is a flat 2 px/frame in every scene, so the bank pass runs
    ; its 38-scanline worst case on each fast frame.
    ld a,2
    ld (speed_pixels),a
    xor a
    ld (slow_phase),a
    jr read_steering

resolve_slow_speed:
    ld a,(slow_phase)
    ld (speed_pixels),a
    xor 1
    ld (slow_phase),a

read_steering:
    ; O/P requests a two-pixel move, applied after the old sprite is erased.
    ld bc,0xdffe
    in a,(c)
    ld d,a
    bit 1,d
    jr nz,steer_right
    ld a,255
    ld (player_move),a
    jr read_joystick_steering
steer_right:
    bit 0,d
    jr nz,read_joystick_steering
    ld a,1
    ld (player_move),a

read_joystick_steering:
    ld a,(joystick_state)
    bit 1,a
    jr z,joystick_right
    ld a,255
    ld (player_move),a
    jr read_space
joystick_right:
    bit 0,a
    jr z,read_space
    ld a,1
    ld (player_move),a

read_space:
    ld bc,0x7ffe
    in a,(c)
    bit 0,a
    jr z,fire_pressed
    ld a,(joystick_state)
    bit 4,a
    jr z,fire_released
fire_pressed:
    ld a,(fire_down)
    or a
    jr nz,read_reset_key
    ld a,1
    ld (fire_down),a
    ld a,(bullet_active)
    or a
    jr nz,read_reset_key
    ld a,(player_x)
    ld (bullet_x),a
    ld a,(player_y)
    sub 4
    ld (bullet_y),a
    call start_missile_sound        ; the original's descending sweep
    ld a,1
    ld (fire_pending),a
    jr read_reset_key
fire_released:
    xor a
    ld (fire_down),a

read_reset_key:
    ld a,e
    bit 3,a
    jr nz,reset_released
    ld a,(r_down)
    or a
    ret nz
    ld a,1
    ld (r_down),a
    call start_new_game
    ret
reset_released:
    xor a
    ld (r_down),a
    ret

profile_begin:
    ld a,(profile_enabled)
    or a
    ret z
    ld a,2
    out (0xfe),a
    ret

profile_end:
    ld a,(profile_enabled)
    or a
    ret z
    xor a
    out (0xfe),a
    ret
