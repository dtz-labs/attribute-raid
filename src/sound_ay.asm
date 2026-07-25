; ---------------------------------------------------------------------------
; AY-3-8912 sound (128K Spectrum or a 48K machine with an AY interface)
; ---------------------------------------------------------------------------

init_ay_sound:
    ; Channel A is noise-only for the jet engine. Channel B is tone-only for
    ; the missile sweep. Channel C provides a brief tone/noise impact burst.
    ; Standard AY writes are harmless on a stock 48K machine. In the Timex
    ; build, detect a real 2068 first so a TC2048 never receives writes through
    ; its even $F6 port while no AY is present.
    call detect_ay_output
    xor a
    ld (shot_sound_timer),a
    ld (explosion_sound_timer),a
    ld (ding_sound_timer),a
    ld a,255
    ld (ay_last_speed),a
    ld e,0x31                       ; noise A, tone B, clean tone C
    ld a,7
    call ay_write_register
    ld e,0
    ld a,8
    call ay_write_register
    ld e,0
    ld a,9
    call ay_write_register
    ld e,0
    ld a,10
    call ay_write_register
    call update_ay_engine
    ret

detect_ay_output:
#if TIMEX_HICOLOR
    jp detect_timex_2068_ay
#else
    ld a,1                         ; standard build keeps the existing AY path
    ld (timex_ay_present),a
    ret
#endif

#if TIMEX_HICOLOR
detect_timex_2068_ay:
    ; TC2068 and TS2068 HOME ROMs contain "Timex" at $113D. The TC2048 ROM
    ; does not, so this read-only test separates native-AY 2068 machines from
    ; the otherwise compatible, beeper-only TC2048 before touching $F5/$F6.
    ld hl,0x113d
    ld de,timex_rom_signature
    ld b,5
detect_timex_2068_byte:
    ld a,(de)
    cp (hl)
    jr nz,detect_timex_ay_missing
    inc de
    inc hl
    djnz detect_timex_2068_byte
    ld a,1
    ld (timex_ay_present),a
    ret
detect_timex_ay_missing:
    xor a
    ld (timex_ay_present),a
    ret
#endif

update_ay_sound:
    call update_ay_engine
    call update_ay_shot
    call update_ay_explosion
    jp update_ay_ding

update_ay_engine:
    ; requested_speed is the stable 0/1/2 control value. Using speed_pixels
    ; here would make the slow 0.5x mode alternate between two engine pitches.
    ld a,(requested_speed)
    ld b,a
    ld a,(ay_last_speed)
    cp b
    ret z
    ld a,b
    ld (ay_last_speed),a
    ld e,a
    ld d,0
    ld hl,ay_engine_noise_periods
    add hl,de
    ld e,(hl)
    ld a,6                          ; AY noise period: smaller means higher
    call ay_write_register

    ld a,(requested_speed)
    ld e,a
    ld d,0
    ld hl,ay_engine_volumes
    add hl,de
    ld e,(hl)
    ld a,8
    jp ay_write_register

update_ay_shot:
    ; Atari's missile uses a short descending frequency sweep. The AY version
    ; also fades its amplitude: tone period grows by eight each frame while
    ; volume falls from 8 to 0 over sixteen frames.
    ld a,(shot_sound_timer)
    or a
    ret z
    dec a
    ld (shot_sound_timer),a
    ld d,a

    ld a,(shot_sound_period)
    ld e,a
    ld a,2                          ; channel B tone period, low byte
    call ay_write_register
    ld e,0
    ld a,3                          ; period never exceeds 255 in this sweep
    call ay_write_register

    ld a,d
    inc a
    srl a
    ld e,a
    ld a,9                          ; channel B amplitude
    call ay_write_register

    ld a,(shot_sound_period)
    add a,8
    ld (shot_sound_period),a
    ret

start_tank_shot_sound:
    ; The gun reuses weapon channel B but starts higher and louder than the
    ; player's missile, producing a sharper, more aggressive downward sweep.
    ld a,25
    ld (shot_sound_timer),a
    ld a,12
    ld (shot_sound_period),a
    ret

start_ay_explosion:
    ; A fresh actor hit restarts a short, low impact envelope on channel C.
    ; Its tone falls while the shared noise generator supplies the initial
    ; crackle. The engine's noise period is restored when the burst finishes.
    ld a,16
    ld (explosion_sound_timer),a
    ld hl,384
    ld (explosion_sound_period),hl
    jr start_noisy_channel_c

start_ay_splash:
    ; A water landing is softer, shorter and lower than a sprite explosion.
    ld a,8
    ld (explosion_sound_timer),a
    ld hl,768
    ld (explosion_sound_period),hl
start_noisy_channel_c:
    xor a
    ld (ding_sound_timer),a
    ld e,0x11                       ; add noise to channel C during impact
    ld a,7
    jp ay_write_register

start_fuel_ding:
    ; Atari distinguishes ordinary refuelling from contact with an already
    ; full tank. Keep one stable pitch throughout filling, then jump exactly
    ; one octave for the repeating full-tank confirmation ping.
    ld a,(explosion_sound_timer)
    or a
    ret nz                          ; explosions have priority on channel C
    ld a,(fuel_level)
    cp 48
    ld a,160                        ; normal refuelling ping
    jr c,store_fuel_ding_period
    ld a,80                         ; full tank: one octave higher
store_fuel_ding_period:
    ld (ding_sound_period),a
    ld a,4
    ld (ding_sound_timer),a
    ld e,0x31                       ; clean tone C, without explosion noise
    ld a,7
    jp ay_write_register

update_ay_ding:
    ld a,(ding_sound_timer)
    or a
    ret z
    dec a
    ld (ding_sound_timer),a
    push af
    ld a,(ding_sound_period)
    ld e,a
    ld a,4
    call ay_write_register
    ld e,0
    ld a,5
    call ay_write_register
    pop af
    add a,a
    add a,a                        ; amplitudes 12, 8, 4, 0
    ld e,a
    ld a,10
    jp ay_write_register

update_ay_explosion:
    ld a,(explosion_sound_timer)
    or a
    ret z
    dec a
    ld (explosion_sound_timer),a

    ld hl,(explosion_sound_period)
    ld e,l
    ld a,4                          ; channel C tone period low byte
    call ay_write_register
    ld hl,(explosion_sound_period)
    ld e,h
    ld a,5                          ; channel C tone period high nibble
    call ay_write_register
    ld e,31                         ; coarse low noise during the impact
    ld a,6
    call ay_write_register

    ld a,(explosion_sound_timer)
    ld e,a                          ; linear 15..0 amplitude decay
    ld a,10
    call ay_write_register

    ld hl,(explosion_sound_period)
    ld de,64                        ; increasing period = rapidly falling tone
    add hl,de
    ld (explosion_sound_period),hl
    ld a,(explosion_sound_timer)
    or a
    ret nz
    ld e,0x31                       ; return C from noisy burst to clean tone
    ld a,7
    call ay_write_register
    ld a,(game_state)
    or a
    ret nz                          ; player-crash pause keeps engine silent
    ld a,255                        ; force channel A noise-period restoration
    ld (ay_last_speed),a
    jp update_ay_engine

silence_ay:
    ld e,0
    ld a,8
    call ay_write_register
    ld e,0
    ld a,9
    call ay_write_register
    ld e,0
    ld a,10
    call ay_write_register
    xor a
    ld (shot_sound_timer),a
    ld (explosion_sound_timer),a
    ld (ding_sound_timer),a
                                    ; callers may rely on a cleared accumulator
    ret

ay_write_register:
    ; Input A=register, E=value. TC2068/TS2068 expose their AY through the exact
    ; 16-bit ports $00F5/$00F6; Spectrum 128K retains $FFFD/$BFFD.
    push af
#if TIMEX_HICOLOR
    ld a,(timex_ay_present)
    or a
    jr z,skip_timex_ay_write
    pop af
    ld bc,0x00f5
    out (c),a
    ld a,e
    inc c                            ; BC=$00F6, AY data port
    out (c),a
    ret
skip_timex_ay_write:
    pop af
    ret
#else
    pop af
    ld bc,0xfffd
    out (c),a
    ld b,0xbf
    ld a,e
    out (c),a
    ret
#endif

