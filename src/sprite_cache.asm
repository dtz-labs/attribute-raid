; One-time construction of eight pre-shifted variants for every 16px sprite.
; Runtime blitters consume these caches directly and never rotate sprite rows.

init_shifted_sprites:
    ld hl,player_jet_sprite
    ld de,player_shift_data
    ld b,14
    call build_shifted_sprite
    ld hl,player_jet_left_sprite
    ld de,player_left_shift_data
    ld b,14
    call build_shifted_sprite
    ld hl,player_jet_right_sprite
    ld de,player_right_shift_data
    ld b,14
    call build_shifted_sprite
    ld hl,enemy_plane_sprite
    ld de,enemy_plane_shift_data
    ld b,8
    call build_shifted_sprite
    ld hl,atari_helicopter_sprite
    ld de,helicopter_shift_data
    ld b,10
    call build_shifted_sprite
    ld hl,atari_helicopter_sprite_alt
    ld de,helicopter_alt_shift_data
    ld b,10
    call build_shifted_sprite
    ld hl,atari_helicopter_sprite_left
    ld de,helicopter_left_shift_data
    ld b,10
    call build_shifted_sprite
    ld hl,atari_helicopter_sprite_left_alt
    ld de,helicopter_left_alt_shift_data
    ld b,10
    call build_shifted_sprite
    ld hl,tank_facing_right_sprite
    ld de,tank_right_shift_data
    ld b,10
    call build_shifted_sprite
    ld hl,tank_facing_left_sprite
    ld de,tank_left_shift_data
    ld b,10
    call build_shifted_sprite
    ld hl,explosion_sprite_0
    ld de,explosion_0_shift_data
    ld b,13
    call build_shifted_sprite
    ld hl,explosion_sprite_1
    ld de,explosion_1_shift_data
    ld b,13
    call build_shifted_sprite
    ld hl,explosion_sprite_2
    ld de,explosion_2_shift_data
    ld b,13
    jp build_shifted_sprite

build_shifted_sprite:
    ; Input HL=two-byte source, DE=cache destination, B=height. The output is
    ; eight variants, each containing three bytes per scanline.
    ld (precompute_source),hl
    ld (precompute_dest),de
    ld a,b
    ld (precompute_height),a
    xor a
    ld (precompute_shift),a
build_shift_variant:
    ld hl,(precompute_source)
    ld (precompute_cursor),hl
    ld a,(precompute_height)
    ld (precompute_rows),a
build_shift_row:
    ld hl,(precompute_cursor)
    ld b,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld (precompute_cursor),hl
    ld d,0
    ld a,(precompute_shift)
    or a
    jr z,build_shift_store
build_shift_bits:
    srl b
    rr c
    rr d
    dec a
    jr nz,build_shift_bits
build_shift_store:
    ld hl,(precompute_dest)
    ld (hl),b
    inc hl
    ld (hl),c
    inc hl
    ld (hl),d
    inc hl
    ld (precompute_dest),hl
    ld a,(precompute_rows)
    dec a
    ld (precompute_rows),a
    jr nz,build_shift_row
    ld a,(precompute_shift)
    inc a
    ld (precompute_shift),a
    cp 8
    jr nz,build_shift_variant
    ret
