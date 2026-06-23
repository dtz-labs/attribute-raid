; Attribute Raid river renderer proof of concept for ZX Spectrum 48K.
; Entry point: 32768.  Normal frames never scroll or copy the bitmap.

org 32768

start:
    di
    call init_attributes
    call init_river
    call full_redraw
    ei

main_loop:
    xor a
    out (0xfe),a
    halt
    call read_keyboard

    ld a,(paused)
    or a
    jr nz,main_loop

    ld a,(start_idx)
    ld (old_start_idx),a

    ld a,(speed_samples)
    cp 2
    jr z,scroll_four_pixels

scroll_two_pixels:
    ld a,(start_idx)
    dec a
    and 127
    ld (start_idx),a
    ld e,a
    call generate_one_at_index
    jr generation_done

scroll_four_pixels:
    ld a,(start_idx)
    dec a
    and 127
    ld e,a
    call generate_one_at_index

    ld a,(start_idx)
    dec a
    dec a
    and 127
    ld (start_idx),a
    ld e,a
    call generate_one_at_index

generation_done:
    call render_dirty
    jr main_loop

init_attributes:
    ld hl,0x5800
    ld bc,768
    ld d,0x4c
init_attr_loop:
    ld (hl),d
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,init_attr_loop
    ret

reinitialize_demo:
    call init_river
    call full_redraw
    ret

init_river:
    ld a,72
    ld (gen_left),a
    ld a,184
    ld (gen_right),a
    ld a,1
    ld (left_vel),a
    ld a,255
    ld (right_vel),a
    xor a
    ld (segment_timer),a
    ld a,0xa7
    ld (lfsr),a
    xor a
    ld (start_idx),a

    ld e,0
init_river_loop:
    push de
    call generate_one_at_index
    pop de
    inc e
    ld a,e
    cp 128
    jr nz,init_river_loop

    ld h,HIGH(left_bank)
    ld l,0
    ld a,(hl)
    ld (gen_left),a
    ld h,HIGH(right_bank)
    ld l,0
    ld a,(hl)
    ld (gen_right),a
    ret

generate_one_at_index:
    push de
    call update_velocities

    ld a,(gen_left)
    ld b,a
    ld a,(left_vel)
    add a,b
    ld (gen_left),a

    ld a,(gen_right)
    ld b,a
    ld a,(right_vel)
    add a,b
    ld (gen_right),a

    call clamp_banks
    pop de

    ld h,HIGH(left_bank)
    ld l,e
    ld a,(gen_left)
    ld (hl),a

    ld h,HIGH(right_bank)
    ld l,e
    ld a,(gen_right)
    ld (hl),a
    ret

update_velocities:
    ld a,(segment_timer)
    or a
    jr z,pick_new_motion
    dec a
    ld (segment_timer),a
    ret

pick_new_motion:
    call lfsr_next
    ld b,a
    ld a,b
    and 7
    add a,2
    ld (segment_timer),a

    ld a,b
    and 7
    add a,a
    ld e,a
    ld d,0
    ld hl,motion_table
    add hl,de
    ld a,(hl)
    ld (left_vel),a
    inc hl
    ld a,(hl)
    ld (right_vel),a
    ret

lfsr_next:
    ld a,(lfsr)
    add a,a
    jr nc,lfsr_no_xor
    xor 0x1d
lfsr_no_xor:
    or a
    jr nz,lfsr_store
    ld a,1
lfsr_store:
    ld (lfsr),a
    ret

clamp_banks:
    ld a,(gen_left)
    cp 8
    jr nc,left_min_ok
    ld a,8
    ld (gen_left),a
    ld a,1
    ld (left_vel),a
left_min_ok:
    ld a,(gen_right)
    cp 249
    jr c,right_max_ok
    ld a,248
    ld (gen_right),a
    ld a,255
    ld (right_vel),a
right_max_ok:
    ld a,(gen_right)
    ld b,a
    ld a,(gen_left)
    ld c,a
    ld a,b
    sub c
    cp 64
    jr nc,width_min_ok
    ld a,255
    ld (left_vel),a
    ld a,1
    ld (right_vel),a
    jr width_done

width_min_ok:
    cp 145
    jr c,width_done
    ld a,1
    ld (left_vel),a
    ld a,255
    ld (right_vel),a

width_done:
    ret

full_redraw:
    ld d,0
full_row_loop:
    ld e,0
full_col_loop:
    push de
    call render_cell
    pop de
    inc e
    ld a,e
    cp 32
    jr nz,full_col_loop
    inc d
    ld a,d
    cp 24
    jr nz,full_row_loop
    ret

render_dirty:
    xor a
    ld (row_var),a
    ld a,(old_start_idx)
    ld (old_row_index),a
    ld a,(start_idx)
    ld (new_row_index),a

dirty_row_loop:
    ld h,HIGH(left_bank)
    ld a,(old_row_index)
    call calc_bank_range
    ld a,b
    ld (range_min),a
    ld a,c
    ld (range_max),a

    ld h,HIGH(left_bank)
    ld a,(new_row_index)
    call calc_bank_range
    call merge_and_render_range

    ld h,HIGH(right_bank)
    ld a,(old_row_index)
    call calc_bank_range
    ld a,b
    ld (range_min),a
    ld a,c
    ld (range_max),a

    ld h,HIGH(right_bank)
    ld a,(new_row_index)
    call calc_bank_range
    call merge_and_render_range

    ld a,(old_row_index)
    add a,4
    and 127
    ld (old_row_index),a
    ld a,(new_row_index)
    add a,4
    and 127
    ld (new_row_index),a
    ld a,(row_var)
    inc a
    ld (row_var),a
    cp 24
    jr nz,dirty_row_loop
    ret

calc_bank_range:
    ; Four 2-pixel samples make one 8-pixel tile row.
    ld l,a
    ld a,(hl)
    call x_to_column
    ld b,a
    ld c,a
    ld d,3
calc_range_loop:
    inc l
    ld a,l
    and 127
    ld l,a
    ld a,(hl)
    call x_to_column
    cp b
    jr nc,range_min_ok
    ld b,a
range_min_ok:
    cp c
    jr c,range_max_ok
    ld c,a
range_max_ok:
    dec d
    jr nz,calc_range_loop
    ret

x_to_column:
    srl a
    srl a
    srl a
    ret

merge_and_render_range:
    ld a,(range_min)
    cp b
    jr c,merge_min_ok
    ld a,b
    ld (range_min),a
merge_min_ok:
    ld a,(range_max)
    cp c
    jr nc,merge_max_ok
    ld a,c
    ld (range_max),a
merge_max_ok:
    ld a,(range_min)
    ld b,a
    ld a,(range_max)
    ld c,a
    call render_range
    ret

render_range:
render_range_loop:
    push bc
    ld a,(row_var)
    ld d,a
    ld e,b
    call render_cell
    pop bc
    ld a,b
    cp c
    ret z
    inc b
    jr render_range_loop

render_cell:
    ld a,d
    ld (cell_row),a
    ld a,e
    ld (cell_col),a

    ld a,(cell_row)
    add a,a
    ld e,a
    ld d,0
    ld hl,screen_row_table
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl
    ld a,(cell_col)
    add a,l
    ld l,a
    ld (cell_addr),hl

    ld a,(cell_row)
    add a,a
    add a,a
    ld b,a
    ld a,(start_idx)
    add a,b
    and 127
    ld (cell_sample),a

    call render_cell_sample
    call render_cell_sample
    call render_cell_sample
    call render_cell_sample
    ret

render_cell_sample:
    ld a,(cell_sample)
    call make_cell_byte
    ld hl,(cell_addr)
    ld (hl),a
    inc h
    ld (hl),a
    inc h
    ld (cell_addr),hl

    ld a,(cell_sample)
    inc a
    and 127
    ld (cell_sample),a
    ret

make_cell_byte:
    ld l,a
    ld h,HIGH(left_bank)
    ld b,(hl)
    ld h,HIGH(right_bank)
    ld c,(hl)

    ld a,(cell_col)
    add a,a
    add a,a
    add a,a
    ld d,a

    ld a,b
    sub d
    jr c,make_left_none
    cp 8
    jr c,make_left_partial
    ld e,255
    jr make_left_done

make_left_none:
    ld e,0
    jr make_left_done

make_left_partial:
    ld l,a
    ld h,HIGH(prefix_mask)
    ld e,(hl)

make_left_done:
    ld a,c
    sub d
    jr c,make_right_full
    jr z,make_right_full
    cp 8
    jr c,make_right_partial
    ld a,e
    ret

make_right_partial:
    ld b,a
    ld a,8
    sub b
    ld l,a
    ld h,HIGH(suffix_mask)
    ld a,(hl)
    or e
    ret

make_right_full:
    ld a,255
    or e
    ret

read_keyboard:
    ld bc,0xf7fe
    in a,(c)
    bit 0,a
    jr nz,key_one_up
    ld a,1
    ld (speed_samples),a
key_one_up:
    ld bc,0xf7fe
    in a,(c)
    bit 1,a
    jr nz,key_two_up
    ld a,2
    ld (speed_samples),a
key_two_up:
    ld bc,0x7ffe
    in a,(c)
    bit 0,a
    jr nz,space_not_pressed
    ld a,(space_down)
    or a
    jr nz,read_r_key
    ld a,1
    ld (space_down),a
    ld a,(paused)
    xor 1
    ld (paused),a
    jr read_r_key

space_not_pressed:
    xor a
    ld (space_down),a

read_r_key:
    ld bc,0xfbfe
    in a,(c)
    bit 3,a
    jr nz,r_not_pressed
    ld a,(r_down)
    or a
    ret nz
    ld a,1
    ld (r_down),a
    call reinitialize_demo
    ret

r_not_pressed:
    xor a
    ld (r_down),a
    ret

screen_row_table:
    dw 0x4000,0x4020,0x4040,0x4060,0x4080,0x40a0,0x40c0,0x40e0
    dw 0x4800,0x4820,0x4840,0x4860,0x4880,0x48a0,0x48c0,0x48e0
    dw 0x5000,0x5020,0x5040,0x5060,0x5080,0x50a0,0x50c0,0x50e0

motion_table:
    ; Signed bank velocities for short jagged segments.  One-sided moves
    ; roughen either edge while shared/opposite moves bend or narrow the river.
    db 255,0
    db 1,0
    db 0,255
    db 0,1
    db 255,1
    db 1,255
    db 255,255
    db 1,1

start_idx:
    db 0
old_start_idx:
    db 0
speed_samples:
    db 1
paused:
    db 0
space_down:
    db 0
r_down:
    db 0

gen_left:
    db 72
gen_right:
    db 184
left_vel:
    db 1
right_vel:
    db 255
segment_timer:
    db 0
lfsr:
    db 0xa7

row_var:
    db 0
old_row_index:
    db 0
new_row_index:
    db 0
range_min:
    db 0
range_max:
    db 0
cell_row:
    db 0
cell_col:
    db 0
cell_sample:
    db 0
cell_addr:
    dw 0

align 256
prefix_mask:
    db 0x00,0x80,0xc0,0xe0,0xf0,0xf8,0xfc,0xfe,0xff

align 256
suffix_mask:
    db 0x00,0x01,0x03,0x07,0x0f,0x1f,0x3f,0x7f,0xff

align 256
left_bank:
    ds 128,0

align 256
right_bank:
    ds 128,0
