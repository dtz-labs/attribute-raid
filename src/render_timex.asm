; Timex 8x1 attribute primitives and multicolour object painters.
; Included by main.asm after the shared Spectrum attribute routines.

timex_attribute_address:
    ; Input A=screen Y. The Timex attribute has exactly the same interleaved
    ; address as its bitmap byte, with address bit 13 set.
    call calc_screen_line_addr
    ld de,0x2000
    add hl,de
    ret

timex_fill_attribute_scanline:
    ; Input A=screen Y, C=attribute. Used by mode setup and GAME OVER too, so
    ; this deliberately accepts all 192 physical scanlines.
    call timex_attribute_address
    ld b,32
    ld a,c
timex_fill_attribute_byte:
    ld (hl),a
    inc hl
    djnz timex_fill_attribute_byte
    ret

timex_paint_object_rows:
    ; Exact 8x1 counterpart of paint_object_attribute_cells. Geometry uses a
    ; pixel Y and a bitmap-byte X/width. Clip once, then keep row count, colour
    ; and the interleaved address in registers for the complete rectangle.
    ld a,(object_attr_rows)
    or a
    ret z
    ld b,a
    ld a,(object_attr_y)
    cp 16
    jr nc,timex_clip_object_bottom
    ld c,a
    ld a,16
    sub c
    ld d,a                           ; rows hidden above the playfield
    ld a,b
    cp d
    ret c
    ret z
    sub d
    ld b,a
    ld a,16
timex_clip_object_bottom:
    cp PLAYFIELD_BOTTOM
    ret nc
    ld d,a                           ; clipped top Y
    ld a,PLAYFIELD_BOTTOM
    sub d
    cp b
    jr nc,timex_object_rows_clipped
    ld b,a
timex_object_rows_clipped:
    ld a,d
    call timex_attribute_address
    ld a,(object_attr_col)
    add a,l
    ld l,a
    ld a,(object_attr_width)
    cp 1
    jr z,timex_paint_object_width_1
    cp 2
    jr z,timex_paint_object_width_2
    ld a,(object_attr_value)
    ld c,a
timex_paint_object_width_3_row:
    ld (hl),c
    inc l
    ld (hl),c
    inc l
    ld (hl),c
    dec l
    dec l
    call timex_advance_object_row_fast
    djnz timex_paint_object_width_3_row
    ret

timex_paint_object_width_2:
    ld a,(object_attr_value)
    ld c,a
timex_paint_object_width_2_row:
    ld (hl),c
    inc l
    ld (hl),c
    dec l
    call timex_advance_object_row_fast
    djnz timex_paint_object_width_2_row
    ret

timex_paint_object_width_1:
    ld a,(object_attr_value)
    ld c,a
timex_paint_object_width_1_row:
    ld (hl),c
    call timex_advance_object_row_fast
    djnz timex_paint_object_width_1_row
    ret

timex_advance_object_row_fast:
    ; Keep the same byte column while following the Spectrum display-file
    ; interleave. This helper touches neither B nor C, which remain the row
    ; counter and colour in the caller's tight loop.
    ld a,h
    and 7
    cp 7
    jr z,timex_advance_object_band_fast
    inc h
    ret
timex_advance_object_band_fast:
    ld a,l
    add a,32
    ld l,a
    jr c,timex_advance_object_third_fast
    ld a,h
    sub 7
    ld h,a
    ret
timex_advance_object_third_fast:
    inc h
    ret

timex_next_attribute_row:
    ; Input/output HL=the same byte column on adjacent Timex attribute lines.
    ; Spectrum display memory advances H inside an 8-line character band;
    ; crossing its last line advances L by 32 and folds H to the next band.
    ld a,h
    and 7
    cp 7
    jr z,timex_next_attribute_band
    inc h
    ret
timex_next_attribute_band:
    ld a,l
    add a,32
    ld l,a
    jr c,timex_next_attribute_third
    ld a,h
    sub 7
    ld h,a
    ret
timex_next_attribute_third:
    inc h
    ret

prepare_timex_fuel_geometry:
    ld a,1
    ld (object_attr_width),a
    ld a,(fuel_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(fuel_y)
    ld (object_attr_y),a
    ld a,32
    ld (object_attr_rows),a
    ret

restore_timex_fuel_attributes:
    call prepare_timex_fuel_geometry
    ld a,0x4c
    ld (object_attr_value),a
    jp timex_paint_object_rows

paint_timex_fuel_attributes:
    call prepare_timex_fuel_geometry
    ld a,(timex_attr_fuel_active)
    or a
    jr z,paint_timex_fuel_full_attributes
    ld a,(speed_pixels)
    or a
    ret z

    ; Colour bands move with the depot. Only speed_pixels rows immediately
    ; before each 8-line boundary acquire a different F/U/E/L colour; all
    ; other overlapping rows already contain the right attribute.
    ld a,8
    ld c,0x4b
    call paint_timex_fuel_entering_band
    ld a,16
    ld c,0x4f
    call paint_timex_fuel_entering_band
    ld a,24
    ld c,0x4b
    call paint_timex_fuel_entering_band
    ld a,32
    ld c,0x4f
    jp paint_timex_fuel_entering_band

paint_timex_fuel_entering_band:
    ; Input A=exclusive relative band end, C=colour. Width/column were prepared.
    ld b,a
    ld a,c
    ld (object_attr_value),a
    ld a,(speed_pixels)
    ld d,a
    ld (object_attr_rows),a
    ld a,b
    sub d
    ld b,a
    ld a,(fuel_y)
    add a,b
    ld (object_attr_y),a
    jp timex_paint_object_rows

paint_timex_fuel_full_attributes:
    ; Spawn is a cold path. Four clipped eight-row rectangles are slightly
    ; slower than the old monolithic loop but preserve the immutable top
    ; margin when the depot enters at Y=0.
    ld a,8
    ld (object_attr_rows),a
    ld a,(fuel_y)
    ld (object_attr_y),a
    ld a,0x4b
    ld (object_attr_value),a
    call timex_paint_object_rows
    ld a,(fuel_y)
    add a,8
    ld (object_attr_y),a
    ld a,0x4f
    ld (object_attr_value),a
    call timex_paint_object_rows
    ld a,(fuel_y)
    add a,16
    ld (object_attr_y),a
    ld a,0x4b
    ld (object_attr_value),a
    call timex_paint_object_rows
    ld a,(fuel_y)
    add a,24
    ld (object_attr_y),a
    ld a,0x4f
    ld (object_attr_value),a
    jp timex_paint_object_rows

prepare_timex_balloon_geometry:
    ld a,2
    ld (object_attr_width),a
    ld a,(balloon_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(balloon_y)
    ld (object_attr_y),a
    ld a,20
    ld (object_attr_rows),a
    ret

restore_timex_balloon_attributes:
    call prepare_timex_balloon_geometry
    ld a,0x4c
    ld (object_attr_value),a
    jp timex_paint_object_rows

paint_timex_balloon_attributes:
    call prepare_timex_balloon_geometry
    ld a,(timex_attr_balloon_active)
    or a
    jr z,paint_timex_balloon_full_attributes
    ld a,(speed_pixels)
    or a
    ret z

    ; As the 4/5/11-row colour bands move down, only rows immediately before
    ; their boundaries and the entering bottom strip need new attributes.
    ld a,4
    ld c,0x4e
    call paint_timex_balloon_entering_band
    ld a,9
    ld c,0x4d
    call paint_timex_balloon_entering_band
    ld a,20
    ld c,0x4b
    jp paint_timex_balloon_entering_band

paint_timex_balloon_entering_band:
    ; Input A=exclusive relative band end, C=colour. Width/column were prepared.
    ld b,a
    ld a,c
    ld (object_attr_value),a
    ld a,(speed_pixels)
    ld d,a
    ld (object_attr_rows),a
    ld a,b
    sub d
    ld b,a
    ld a,(balloon_y)
    add a,b
    ld (object_attr_y),a
    jp timex_paint_object_rows

paint_timex_balloon_full_attributes:
    ; The three colour strips are clipped independently, so a balloon entering
    ; above Y=16 cannot leak attributes into the protected black margin.
    ld a,4
    ld (object_attr_rows),a
    ld a,(balloon_y)
    ld (object_attr_y),a
    ld a,0x4e
    ld (object_attr_value),a
    call timex_paint_object_rows
    ld a,5
    ld (object_attr_rows),a
    ld a,(balloon_y)
    add a,4
    ld (object_attr_y),a
    ld a,0x4d
    ld (object_attr_value),a
    call timex_paint_object_rows
    ld a,11
    ld (object_attr_rows),a
    ld a,(balloon_y)
    add a,9
    ld (object_attr_y),a
    ld a,0x4b
    ld (object_attr_value),a
    jp timex_paint_object_rows
