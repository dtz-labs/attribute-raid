; Attribute Raid river renderer proof of concept for ZX Spectrum 48K.
; Entry point: 32768.  Normal frames never scroll or copy the bitmap.

org 32768

start:
    di
    call init_attributes
    call init_river
    call init_video_buffers
    ei

main_loop:
    xor a
    out (0xfe),a
    halt
    call read_keyboard

    ld a,(paused)
    or a
    jr nz,main_loop

    ld a,(start_lo)
    ld (old_start_lo),a
    ld a,(start_page)
    ld (old_start_page),a

    ld a,(speed_samples)
    cp 2
    jr z,scroll_four_pixels

scroll_two_pixels:
    call dec_start_index
    jr generation_done

scroll_four_pixels:
    call dec_start_index
    call dec_start_index

generation_done:
    call prepare_frame_buffer
    call render_dirty
    call update_and_draw_sprites
    call present_frame
    jr main_loop

dec_start_index:
    ld a,(start_lo)
    dec a
    ld (start_lo),a
    cp 255
    ret nz
    ld a,(start_page)
    dec a
    and 3
    ld (start_page),a
    ret

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

    ld hl,0x7800
    ld bc,768
    ld d,0x4c
init_attr2_loop:
    ld (hl),d
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,init_attr2_loop
    ret

reinitialize_demo:
    call init_river
    call init_video_buffers
    ret

init_video_buffers:
    call reset_sprite_state
    xor a
    ld (screen_page_offset),a
    ld (display_page),a
    call full_redraw
    call draw_current_sprites
    call store_drawn_sprite_state

    ld a,(timex_enabled)
    or a
    ret z

    ld a,0x20
    ld (screen_page_offset),a
    call full_redraw
    call draw_current_sprites
    call store_drawn_sprite_state

    xor a
    out (0xff),a
    ld (screen_page_offset),a
    ld (display_page),a
    ld (buffer0_lo),a
    ld (buffer0_page),a
    ld (buffer1_lo),a
    ld (buffer1_page),a
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
    ld (start_lo),a
    ld (start_page),a

    ld d,0
    ld e,0
init_river_loop:
    push de
    call generate_one_at_index
    pop de
    inc e
    jr nz,init_river_loop
    inc d
    ld a,d
    cp 4
    jr nz,init_river_loop
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

    ld a,d
    add a,HIGH(left_bank)
    ld h,a
    ld l,e
    ld a,(gen_left)
    ld (hl),a

    ld a,d
    add a,HIGH(right_bank)
    ld h,a
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
    and 1
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

prepare_frame_buffer:
    ld a,(timex_enabled)
    or a
    jr nz,prepare_timex_frame
    xor a
    ld (screen_page_offset),a
    ret

prepare_timex_frame:
    ld a,(display_page)
    or a
    jr z,prepare_timex_page1

prepare_timex_page0:
    xor a
    ld (screen_page_offset),a
    ld a,(buffer0_lo)
    ld (old_start_lo),a
    ld a,(buffer0_page)
    ld (old_start_page),a
    ret

prepare_timex_page1:
    ld a,0x20
    ld (screen_page_offset),a
    ld a,(buffer1_lo)
    ld (old_start_lo),a
    ld a,(buffer1_page)
    ld (old_start_page),a
    ret

present_frame:
    ld a,(timex_enabled)
    or a
    ret z
    ld a,(screen_page_offset)
    or a
    jr nz,present_timex_page1

present_timex_page0:
    xor a
    out (0xff),a
    ld (display_page),a
    ld a,(start_lo)
    ld (buffer0_lo),a
    ld a,(start_page)
    ld (buffer0_page),a
    ret

present_timex_page1:
    ld a,1
    out (0xff),a
    ld (display_page),a
    ld a,(start_lo)
    ld (buffer1_lo),a
    ld a,(start_page)
    ld (buffer1_page),a
    ret

render_dirty:
    xor a
    ld (row_var),a
    ld a,(old_start_lo)
    ld (old_row_lo),a
    ld a,(old_start_page)
    ld (old_row_page),a
    ld a,(start_lo)
    ld (new_row_lo),a
    ld a,(start_page)
    ld (new_row_page),a

dirty_row_loop:
    ld a,HIGH(left_bank)
    call set_range_bank
    ld a,(old_row_page)
    add a,HIGH(left_bank)
    ld h,a
    ld a,(old_row_lo)
    call calc_bank_range
    ld a,b
    ld (range_min),a
    ld a,c
    ld (range_max),a

    ld a,(new_row_page)
    add a,HIGH(left_bank)
    ld h,a
    ld a,(new_row_lo)
    call calc_bank_range
    call merge_and_render_range

    ld a,HIGH(right_bank)
    call set_range_bank
    ld a,(old_row_page)
    add a,HIGH(right_bank)
    ld h,a
    ld a,(old_row_lo)
    call calc_bank_range
    ld a,b
    ld (range_min),a
    ld a,c
    ld (range_max),a

    ld a,(new_row_page)
    add a,HIGH(right_bank)
    ld h,a
    ld a,(new_row_lo)
    call calc_bank_range
    call merge_and_render_range

    ld a,(old_row_lo)
    add a,4
    ld (old_row_lo),a
    jr nc,old_row_advanced
    ld a,(old_row_page)
    inc a
    and 3
    ld (old_row_page),a
old_row_advanced:
    ld a,(new_row_lo)
    add a,4
    ld (new_row_lo),a
    jr nc,new_row_advanced
    ld a,(new_row_page)
    inc a
    and 3
    ld (new_row_page),a
new_row_advanced:
    ld a,(row_var)
    inc a
    ld (row_var),a
    cp 24
    jr z,dirty_rows_done
    jp dirty_row_loop
dirty_rows_done:
    ret

set_range_bank:
    ld (range_base_high),a
    add a,4
    ld (range_end_high),a
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
    jr nz,calc_range_no_wrap
    inc h
    ld a,(range_end_high)
    cp h
    jr nz,calc_range_no_wrap
    ld a,(range_base_high)
    ld h,a
calc_range_no_wrap:
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
    ld a,(screen_page_offset)
    add a,h
    ld h,a
    ld a,(cell_col)
    add a,l
    ld l,a
    ld (cell_addr),hl

    ld a,(cell_row)
    add a,a
    add a,a
    ld b,a
    ld a,(start_lo)
    add a,b
    ld (cell_sample_lo),a
    ld a,(start_page)
    jr nc,cell_sample_page_ready
    inc a
    and 3
cell_sample_page_ready:
    ld (cell_sample_page),a

    call render_cell_sample
    call render_cell_sample
    call render_cell_sample
    call render_cell_sample
    ret

render_cell_sample:
    call make_cell_byte
    ld hl,(cell_addr)
    ld (hl),a
    inc h
    ld (hl),a
    inc h
    ld (cell_addr),hl

    ld a,(cell_sample_lo)
    inc a
    ld (cell_sample_lo),a
    ret nz
    ld a,(cell_sample_page)
    inc a
    and 3
    ld (cell_sample_page),a
    ret

make_cell_byte:
    ld a,(cell_sample_page)
    add a,HIGH(left_bank)
    ld h,a
    ld a,(cell_sample_lo)
    ld l,a
    ld b,(hl)
    ld a,(cell_sample_page)
    add a,HIGH(right_bank)
    ld h,a
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

reset_sprite_state:
    xor a
    ld (frame_counter),a
    ld (plane_crashed),a
    ld a,16
    ld (bank0_y),a
    ld a,2
    ld (bank0_col),a
    ld a,64
    ld (bank1_y),a
    ld a,28
    ld (bank1_col),a
    ld a,112
    ld (bank2_y),a
    ld a,3
    ld (bank2_col),a
    ld a,160
    ld (bank3_y),a
    ld a,26
    ld (bank3_col),a
    ld a,15
    ld (ship_col),a
    ld a,88
    ld (ship_y),a
    ld a,1
    ld (ship_dir),a
    ld a,21
    ld (heli_col),a
    ld a,48
    ld (heli_y),a
    ld a,255
    ld (heli_dir),a
    ret

update_and_draw_sprites:
    call restore_moving_sprites
    call update_moving_sprites
    call draw_current_sprites
    call store_drawn_sprite_state
    ret

draw_current_sprites:
    call draw_bank_objects
    call draw_ship
    call draw_helicopter
    call draw_plane
    ret

restore_moving_sprites:
    call restore_bank_objects

    call load_drawn_ship_y
    ld (sprite_y),a
    call set_sprite_row_phase_from_y
    call load_drawn_ship_col
    ld (sprite_col),a
    call restore_shifted_sprite_cell

    call load_drawn_heli_y
    ld (sprite_y),a
    call set_sprite_row_phase_from_y
    call load_drawn_heli_col
    ld (sprite_col),a
    call restore_shifted_sprite_cell
    ret

update_moving_sprites:
    ld a,(frame_counter)
    inc a
    ld (frame_counter),a
    ld b,a
    push bc
    call advance_scrolling_sprites
    pop bc

    and 7
    jr nz,ship_update_done
    ld a,(ship_dir)
    cp 1
    jr z,ship_move_right
ship_move_left:
    ld a,(ship_col)
    dec a
    ld (ship_col),a
    cp 11
    jr nc,ship_update_done
    ld a,11
    ld (ship_col),a
    ld a,1
    ld (ship_dir),a
    jr ship_update_done
ship_move_right:
    ld a,(ship_col)
    inc a
    ld (ship_col),a
    cp 21
    jr c,ship_update_done
    ld a,20
    ld (ship_col),a
    ld a,255
    ld (ship_dir),a
ship_update_done:

    ld a,b
    and 3
    ret nz
    ld a,(heli_dir)
    cp 1
    jr z,heli_move_right
heli_move_left:
    ld a,(heli_col)
    dec a
    ld (heli_col),a
    cp 9
    ret nc
    ld a,9
    ld (heli_col),a
    ld a,1
    ld (heli_dir),a
    ret
heli_move_right:
    ld a,(heli_col)
    inc a
    ld (heli_col),a
    cp 23
    ret c
    ld a,22
    ld (heli_col),a
    ld a,255
    ld (heli_dir),a
    ret

advance_scrolling_sprites:
    ld a,(speed_samples)
    add a,a
    ld c,a
    ld a,(bank0_y)
    call advance_sprite_y
    ld (bank0_y),a
    ld a,(bank1_y)
    call advance_sprite_y
    ld (bank1_y),a
    ld a,(bank2_y)
    call advance_sprite_y
    ld (bank2_y),a
    ld a,(bank3_y)
    call advance_sprite_y
    ld (bank3_y),a
    ld a,(ship_y)
    call advance_sprite_y
    ld (ship_y),a
    ld a,(heli_y)
    call advance_sprite_y
    ld (heli_y),a
    ret

advance_sprite_y:
    add a,c
    cp 184
    ret c
    xor a
    ret

restore_bank_objects:
    ld a,(screen_page_offset)
    or a
    jr nz,restore_bank_objects_page1

restore_bank_objects_page0:
    ld a,(buffer0_bank0_col)
    ld c,a
    ld a,(buffer0_bank0_y)
    call restore_bank_object

    ld a,(buffer0_bank1_col)
    ld c,a
    ld a,(buffer0_bank1_y)
    call restore_bank_object

    ld a,(buffer0_bank2_col)
    ld c,a
    ld a,(buffer0_bank2_y)
    call restore_bank_object

    ld a,(buffer0_bank3_col)
    ld c,a
    ld a,(buffer0_bank3_y)
    call restore_bank_object
    ret

restore_bank_objects_page1:
    ld a,(buffer1_bank0_col)
    ld c,a
    ld a,(buffer1_bank0_y)
    call restore_bank_object

    ld a,(buffer1_bank1_col)
    ld c,a
    ld a,(buffer1_bank1_y)
    call restore_bank_object

    ld a,(buffer1_bank2_col)
    ld c,a
    ld a,(buffer1_bank2_y)
    call restore_bank_object

    ld a,(buffer1_bank3_col)
    ld c,a
    ld a,(buffer1_bank3_y)
    call restore_bank_object
    ret

restore_bank_object:
    ld (sprite_y),a
    call set_sprite_row_phase_from_y
    ld a,c
    ld (sprite_col),a
    call restore_shifted_sprite_cell
    ret

draw_bank_objects:
    ld a,(bank0_y)
    ld (sprite_y),a
    call set_sprite_row_phase_from_y
    call set_left_bank_sprite_col
    ld a,(sprite_col)
    ld (bank0_col),a
    ld hl,tree_sprite
    ld (sprite_pattern),hl
    ld a,0x20
    ld (sprite_attr),a
    call draw_shifted_sprite

    ld a,(bank1_y)
    ld (sprite_y),a
    call set_sprite_row_phase_from_y
    call set_right_bank_sprite_col
    ld a,(sprite_col)
    ld (bank1_col),a
    ld hl,tank_sprite
    ld (sprite_pattern),hl
    ld a,0x20
    ld (sprite_attr),a
    call draw_shifted_sprite

    ld a,(bank2_y)
    ld (sprite_y),a
    call set_sprite_row_phase_from_y
    call set_left_bank_sprite_col
    ld a,(sprite_col)
    ld (bank2_col),a
    ld hl,tank_sprite
    ld (sprite_pattern),hl
    ld a,0x20
    ld (sprite_attr),a
    call draw_shifted_sprite

    ld a,(bank3_y)
    ld (sprite_y),a
    call set_sprite_row_phase_from_y
    call set_right_bank_sprite_col
    ld a,(sprite_col)
    ld (bank3_col),a
    ld hl,tree_sprite
    ld (sprite_pattern),hl
    ld a,0x20
    ld (sprite_attr),a
    call draw_shifted_sprite
    ret

store_drawn_sprite_state:
    ld a,(screen_page_offset)
    or a
    jr nz,store_drawn_sprite_state_page1

store_drawn_sprite_state_page0:
    ld a,(bank0_y)
    ld (buffer0_bank0_y),a
    ld a,(bank0_col)
    ld (buffer0_bank0_col),a
    ld a,(bank1_y)
    ld (buffer0_bank1_y),a
    ld a,(bank1_col)
    ld (buffer0_bank1_col),a
    ld a,(bank2_y)
    ld (buffer0_bank2_y),a
    ld a,(bank2_col)
    ld (buffer0_bank2_col),a
    ld a,(bank3_y)
    ld (buffer0_bank3_y),a
    ld a,(bank3_col)
    ld (buffer0_bank3_col),a
    ld a,(ship_col)
    ld (buffer0_ship_col),a
    ld a,(ship_y)
    ld (buffer0_ship_y),a
    ld a,(heli_col)
    ld (buffer0_heli_col),a
    ld a,(heli_y)
    ld (buffer0_heli_y),a
    ret

store_drawn_sprite_state_page1:
    ld a,(bank0_y)
    ld (buffer1_bank0_y),a
    ld a,(bank0_col)
    ld (buffer1_bank0_col),a
    ld a,(bank1_y)
    ld (buffer1_bank1_y),a
    ld a,(bank1_col)
    ld (buffer1_bank1_col),a
    ld a,(bank2_y)
    ld (buffer1_bank2_y),a
    ld a,(bank2_col)
    ld (buffer1_bank2_col),a
    ld a,(bank3_y)
    ld (buffer1_bank3_y),a
    ld a,(bank3_col)
    ld (buffer1_bank3_col),a
    ld a,(ship_col)
    ld (buffer1_ship_col),a
    ld a,(ship_y)
    ld (buffer1_ship_y),a
    ld a,(heli_col)
    ld (buffer1_heli_col),a
    ld a,(heli_y)
    ld (buffer1_heli_y),a
    ret

load_drawn_ship_col:
    ld a,(screen_page_offset)
    or a
    jr nz,load_drawn_ship_col_page1
    ld a,(buffer0_ship_col)
    ret
load_drawn_ship_col_page1:
    ld a,(buffer1_ship_col)
    ret

load_drawn_ship_y:
    ld a,(screen_page_offset)
    or a
    jr nz,load_drawn_ship_y_page1
    ld a,(buffer0_ship_y)
    ret
load_drawn_ship_y_page1:
    ld a,(buffer1_ship_y)
    ret

load_drawn_heli_col:
    ld a,(screen_page_offset)
    or a
    jr nz,load_drawn_heli_col_page1
    ld a,(buffer0_heli_col)
    ret
load_drawn_heli_col_page1:
    ld a,(buffer1_heli_col)
    ret

load_drawn_heli_y:
    ld a,(screen_page_offset)
    or a
    jr nz,load_drawn_heli_y_page1
    ld a,(buffer0_heli_y)
    ret
load_drawn_heli_y_page1:
    ld a,(buffer1_heli_y)
    ret

set_sprite_row_phase_from_y:
    ld b,a
    and 7
    ld (sprite_phase),a
    ld a,b
    srl a
    srl a
    srl a
    ld (sprite_row),a
    ret

set_left_bank_sprite_col:
    ld a,(sprite_y)
    srl a
    add a,2
    ld b,a
    ld a,(start_lo)
    add a,b
    ld l,a
    ld a,(start_page)
    jr nc,left_sprite_page_ready
    inc a
    and 3
left_sprite_page_ready:
    add a,HIGH(left_bank)
    ld h,a
    ld a,(hl)
    call x_to_column
    or a
    jr z,left_sprite_col_ready
    dec a
left_sprite_col_ready:
    ld (sprite_col),a
    ret

set_right_bank_sprite_col:
    ld a,(sprite_y)
    srl a
    add a,2
    ld b,a
    ld a,(start_lo)
    add a,b
    ld l,a
    ld a,(start_page)
    jr nc,right_sprite_page_ready
    inc a
    and 3
right_sprite_page_ready:
    add a,HIGH(right_bank)
    ld h,a
    ld a,(hl)
    call x_to_column
    ld (sprite_col),a
    ret

draw_ship:
    ld a,(ship_y)
    ld (sprite_y),a
    call set_sprite_row_phase_from_y
    ld a,(ship_col)
    ld (sprite_col),a
    ld hl,ship_sprite
    ld (sprite_pattern),hl
    ld a,0x4f
    ld (sprite_attr),a
    call draw_shifted_sprite
    ret

draw_helicopter:
    ld a,(heli_y)
    ld (sprite_y),a
    call set_sprite_row_phase_from_y
    ld a,(heli_col)
    ld (sprite_col),a
    ld hl,helicopter_sprite
    ld (sprite_pattern),hl
    ld a,0x4e
    ld (sprite_attr),a
    call draw_shifted_sprite
    ret

draw_plane:
    call check_plane_crash
    ld a,22
    ld (sprite_row),a
    ld a,15
    ld (sprite_col),a
    ld a,(plane_crashed)
    or a
    jr nz,draw_crash_sprite
    ld hl,plane_sprite
    ld (sprite_pattern),hl
    ld a,0x4f
    ld (sprite_attr),a
    call draw_sprite
    ret
draw_crash_sprite:
    ld hl,crash_sprite
    ld (sprite_pattern),hl
    ld a,0x4a
    ld (sprite_attr),a
    call draw_sprite
    ret

check_plane_crash:
    ld a,(start_lo)
    add a,88
    ld l,a
    ld a,(start_page)
    jr nc,plane_sample_page_ready
    inc a
    and 3
plane_sample_page_ready:
    ld b,a
    add a,HIGH(left_bank)
    ld h,a
    ld a,(hl)
    cp 112
    jr nc,plane_is_crashed
    ld a,b
    add a,HIGH(right_bank)
    ld h,a
    ld a,(hl)
    cp 136
    jr c,plane_is_crashed
    xor a
    ld (plane_crashed),a
    ret
plane_is_crashed:
    ld a,1
    ld (plane_crashed),a
    ret

restore_sprite_cell:
    ld a,(sprite_row)
    ld d,a
    ld a,(sprite_col)
    ld e,a
    call render_cell
    ld a,0x4c
    ld (sprite_attr),a
    call set_sprite_attr
    ret

restore_shifted_sprite_cell:
    call restore_sprite_cell
    ld a,(sprite_phase)
    or a
    ret z
    ld a,(sprite_row)
    cp 23
    ret z
    inc a
    ld (sprite_row),a
    call restore_sprite_cell
    ld a,(sprite_row)
    dec a
    ld (sprite_row),a
    ret

draw_sprite:
    call calc_sprite_cell_addr
    ld de,(sprite_pattern)
    ld hl,(cell_addr)
    ld b,8
draw_sprite_loop:
    ld a,(de)
    ld (hl),a
    inc de
    inc h
    djnz draw_sprite_loop
    call set_sprite_attr
    ret

draw_shifted_sprite:
    ld a,(sprite_phase)
    or a
    jr nz,draw_shifted_nonzero
    call draw_sprite
    ret

draw_shifted_nonzero:
    call calc_sprite_cell_addr
    ld hl,(cell_addr)
    ld a,(sprite_phase)
    ld b,a
draw_shifted_top_addr_loop:
    inc h
    djnz draw_shifted_top_addr_loop

    ld de,(sprite_pattern)
    ld a,(sprite_phase)
    ld b,a
    ld a,8
    sub b
    ld b,a
draw_shifted_top_loop:
    ld a,(de)
    ld (hl),a
    inc de
    inc h
    djnz draw_shifted_top_loop
    call set_sprite_attr

    ld a,(sprite_row)
    inc a
    ld (sprite_row),a
    call calc_sprite_cell_addr
    ld hl,(cell_addr)
    ld de,(sprite_pattern)
    ld a,(sprite_phase)
    ld c,a
    ld a,8
    sub c
    ld b,a
draw_shifted_skip_loop:
    inc de
    djnz draw_shifted_skip_loop

    ld a,(sprite_phase)
    ld b,a
draw_shifted_bottom_loop:
    ld a,(de)
    ld (hl),a
    inc de
    inc h
    djnz draw_shifted_bottom_loop
    call set_sprite_attr

    ld a,(sprite_row)
    dec a
    ld (sprite_row),a
    ret

calc_sprite_cell_addr:
    ld a,(sprite_row)
    add a,a
    ld e,a
    ld d,0
    ld hl,screen_row_table
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl
    ld a,(screen_page_offset)
    add a,h
    ld h,a
    ld a,(sprite_col)
    add a,l
    ld l,a
    ld (cell_addr),hl
    ret

set_sprite_attr:
    ld a,(sprite_row)
    add a,a
    ld e,a
    ld d,0
    ld hl,attr_row_table
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl
    ld a,(screen_page_offset)
    add a,h
    ld h,a
    ld a,(sprite_col)
    add a,l
    ld l,a
    ld a,(sprite_attr)
    ld (hl),a
    ret

screen_row_table:
    dw 0x4000,0x4020,0x4040,0x4060,0x4080,0x40a0,0x40c0,0x40e0
    dw 0x4800,0x4820,0x4840,0x4860,0x4880,0x48a0,0x48c0,0x48e0
    dw 0x5000,0x5020,0x5040,0x5060,0x5080,0x50a0,0x50c0,0x50e0

attr_row_table:
    dw 0x5800,0x5820,0x5840,0x5860,0x5880,0x58a0,0x58c0,0x58e0
    dw 0x5900,0x5920,0x5940,0x5960,0x5980,0x59a0,0x59c0,0x59e0
    dw 0x5a00,0x5a20,0x5a40,0x5a60,0x5a80,0x5aa0,0x5ac0,0x5ae0

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

plane_sprite:
    db 0x18,0x3c,0x7e,0xff,0x3c,0x3c,0x66,0x00
crash_sprite:
    db 0x81,0x42,0x24,0x18,0x18,0x24,0x42,0x81
ship_sprite:
    db 0x00,0x18,0x3c,0x7e,0xff,0x7e,0x24,0x00
helicopter_sprite:
    db 0xff,0x18,0x7e,0xdb,0x7e,0x18,0x24,0x00
tree_sprite:
    db 0x18,0x3c,0x7e,0x3c,0x18,0x18,0x3c,0x00
tank_sprite:
    db 0x00,0x18,0x7e,0xff,0x7e,0xdb,0xff,0x00

start_lo:
    db 0
start_page:
    db 0
old_start_lo:
    db 0
old_start_page:
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

timex_enabled:
    db TIMEX_DOUBLE_BUFFER
screen_page_offset:
    db 0
display_page:
    db 0
buffer0_lo:
    db 0
buffer0_page:
    db 0
buffer1_lo:
    db 0
buffer1_page:
    db 0

row_var:
    db 0
old_row_lo:
    db 0
old_row_page:
    db 0
new_row_lo:
    db 0
new_row_page:
    db 0
range_min:
    db 0
range_max:
    db 0
range_base_high:
    db 0
range_end_high:
    db 0
cell_row:
    db 0
cell_col:
    db 0
cell_sample_lo:
    db 0
cell_sample_page:
    db 0
cell_addr:
    dw 0
frame_counter:
    db 0
bank0_y:
    db 16
bank0_col:
    db 2
bank1_y:
    db 64
bank1_col:
    db 28
bank2_y:
    db 112
bank2_col:
    db 3
bank3_y:
    db 160
bank3_col:
    db 26
ship_col:
    db 15
ship_y:
    db 88
ship_dir:
    db 1
heli_col:
    db 21
heli_y:
    db 48
heli_dir:
    db 255
plane_crashed:
    db 0
sprite_row:
    db 0
sprite_y:
    db 0
sprite_phase:
    db 0
sprite_col:
    db 0
sprite_pattern:
    dw 0
sprite_attr:
    db 0

buffer0_bank0_y:
    db 16
buffer0_bank0_col:
    db 2
buffer0_bank1_y:
    db 64
buffer0_bank1_col:
    db 28
buffer0_bank2_y:
    db 112
buffer0_bank2_col:
    db 3
buffer0_bank3_y:
    db 160
buffer0_bank3_col:
    db 26
buffer0_ship_col:
    db 15
buffer0_ship_y:
    db 88
buffer0_heli_col:
    db 21
buffer0_heli_y:
    db 48

buffer1_bank0_y:
    db 16
buffer1_bank0_col:
    db 2
buffer1_bank1_y:
    db 64
buffer1_bank1_col:
    db 28
buffer1_bank2_y:
    db 112
buffer1_bank2_col:
    db 3
buffer1_bank3_y:
    db 160
buffer1_bank3_col:
    db 26
buffer1_ship_col:
    db 15
buffer1_ship_y:
    db 88
buffer1_heli_col:
    db 21
buffer1_heli_y:
    db 48

align 256
prefix_mask:
    db 0x00,0x80,0xc0,0xe0,0xf0,0xf8,0xfc,0xfe,0xff

align 256
suffix_mask:
    db 0x00,0x01,0x03,0x07,0x0f,0x1f,0x3f,0x7f,0xff

align 256
left_bank:
    ds 1024,0

align 256
right_bank:
    ds 1024,0
