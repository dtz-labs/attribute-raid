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
    cp 3
    jr z,timex_paint_object_width_3
    cp 4
    jr z,timex_paint_object_width_4
    ; Five byte columns: the 32-pixel ship hull once pixel scrolling splits it.
    ld a,(object_attr_value)
    ld c,a
timex_paint_object_width_5_row:
    ld (hl),c
    inc l
    ld (hl),c
    inc l
    ld (hl),c
    inc l
    ld (hl),c
    inc l
    ld (hl),c
    dec l
    dec l
    dec l
    dec l
    call timex_advance_object_row_fast
    djnz timex_paint_object_width_5_row
    ret

timex_paint_object_width_4:
    ld a,(object_attr_value)
    ld c,a
timex_paint_object_width_4_row:
    ld (hl),c
    inc l
    ld (hl),c
    inc l
    ld (hl),c
    inc l
    ld (hl),c
    dec l
    dec l
    dec l
    call timex_advance_object_row_fast
    djnz timex_paint_object_width_4_row
    ret

timex_paint_object_width_3:
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

; ---------------------------------------------------------------------------
; Ship per-scanline hull colours
; ---------------------------------------------------------------------------
;
; The Atari kernel reloads COLUP1 on every ship line pair from ShipCol
; ($A8,$32,$00,$00 bottom-up on NTSC): black mast and superstructure, a dark
; red upper hull and a light blue waterline. The 8x1 attribute file follows
; that exactly; only the fixed Spectrum palette approximates the two Atari
; hull shades. PAPER stays the bright river blue everywhere.

ship_attr_row_colours:
    db 0x48,0x48,0x48,0x48           ; mast and superstructure: black INK
    db 0x4a,0x4a                     ; upper hull: red INK
    db 0x4d,0x4d                     ; waterline: cyan INK

prepare_timex_ship_geometry:
    ; Input B=hull pixel X, C=hull pixel Y. The 32-pixel hull covers four
    ; byte columns when aligned and five once pixel scrolling splits it.
    ; Row count is deliberately left to the caller.
    ld a,b
    and 7
    ld a,4
    jr z,timex_ship_width_ready
    inc a
timex_ship_width_ready:
    ld (object_attr_width),a
    ld a,b
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,c
    ld (object_attr_y),a
    ret

timex_paint_ship_rows:
    ; Counterpart of timex_paint_object_rows with one colour per hull
    ; scanline instead of a single value. Always paints the complete
    ; eight-row hull; clipping matches the uniform painter and skips the
    ; hidden rows' colour entries so the visible bands stay attached.
    ld b,8
    ld hl,ship_attr_row_colours
    ld a,(object_attr_y)
    cp 16
    jr nc,timex_clip_ship_bottom
    ld c,a
    ld a,16
    sub c
    ld c,a                           ; rows hidden above the playfield
    ld a,b
    cp c
    ret c
    ret z
    sub c
    ld b,a
    ld a,c                           ; hidden rows consume their colours too
    add a,l
    ld l,a
    jr nc,timex_ship_rows_from_top
    inc h
timex_ship_rows_from_top:
    ld a,16
timex_clip_ship_bottom:
    cp PLAYFIELD_BOTTOM
    ret nc
    ld c,a                           ; clipped top Y
    ld a,PLAYFIELD_BOTTOM
    sub c
    cp b
    jr nc,timex_ship_rows_clipped
    ld b,a
timex_ship_rows_clipped:
    push hl                          ; colour table survives the address maths
    ld a,c
    call timex_attribute_address
    ld a,(object_attr_col)
    add a,l
    ld l,a
    pop de                           ; DE = per-scanline colour entries
    ld a,(object_attr_width)
    cp 1
    jr z,timex_paint_ship_width_1
    cp 4
    jr z,timex_paint_ship_width_4
timex_paint_ship_width_5_row:
    ld a,(de)
    inc de
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    dec l
    dec l
    dec l
    dec l
    call timex_advance_object_row_fast
    djnz timex_paint_ship_width_5_row
    ret

timex_paint_ship_width_4:
    ld a,(de)
    inc de
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    inc l
    ld (hl),a
    dec l
    dec l
    dec l
    call timex_advance_object_row_fast
    djnz timex_paint_ship_width_4
    ret

timex_paint_ship_width_1:
    ld a,(de)
    inc de
    ld (hl),a
    call timex_advance_object_row_fast
    djnz timex_paint_ship_width_1
    ret

paint_timex_ship0_attributes:
    ; Ship 0 never patrols, so its colour bands move only with the river
    ; scroll; a static frame needs no attribute work at all. Spawn and any
    ; discontinuous move repaint the whole hull.
    ld a,(ship0_active)
    or a
    ret z
    ld a,(ship0_x)
    ld b,a
    ld a,(ship0_y)
    ld c,a
    call prepare_timex_ship_geometry
    ld a,(timex_bitmap_ship0_active)
    or a
    jp z,timex_paint_ship_rows
    ld a,(timex_bitmap_ship0_y)
    ld b,a
    ld a,(ship0_y)
    sub b
    ret z
    jp c,timex_paint_ship_rows
    cp 3
    jp nc,timex_paint_ship_rows
    jp paint_timex_ship_entering_bands

paint_timex_ship1_attributes:
    ld a,(ship1_active)
    or a
    ret z
    ld a,(ship1_x)
    ld b,a
    ld a,(ship1_y)
    ld c,a
    call prepare_timex_ship_geometry
    ld a,(timex_bitmap_ship1_active)
    or a
    jp z,timex_paint_ship_rows
    ld a,(timex_bitmap_ship1_y)
    ld b,a
    ld a,(ship1_y)
    sub b
    jr z,timex_paint_ship1_horizontal
    jp c,timex_paint_ship_rows
    cp 3
    jp nc,timex_paint_ship_rows
    call paint_timex_ship_entering_bands
timex_paint_ship1_horizontal:
    ; The hull's colour cells change horizontally only when a byte column
    ; joins the footprint, i.e. when the patrol leaves an aligned X. The
    ; fresh side column needs all eight per-scanline colours.
    ld a,(timex_bitmap_ship1_x)
    ld b,a
    ld a,(ship1_x)
    cp b
    ret z
    ld a,b
    and 7
    ret nz
    ld a,(ship1_x)
    cp b
    jr c,timex_paint_ship1_new_left
    ; moved right off an aligned hull: a fifth column appears on the right
    ld a,b
    srl a
    srl a
    srl a
    add a,4
    jr timex_paint_ship1_side
timex_paint_ship1_new_left:
    ; moved left off an aligned hull: the footprint grows one column left
    ld a,(ship1_x)
    srl a
    srl a
    srl a
timex_paint_ship1_side:
    ld (object_attr_col),a
    ld a,1
    ld (object_attr_width),a
    ld a,(ship1_y)
    ld (object_attr_y),a
    jp timex_paint_ship_rows

paint_timex_ship_entering_bands:
    ; Only rows crossing a hull colour boundary while the ship scrolls down
    ; need new attributes: black top rows slide over other black rows, so
    ; just the band ends at relative rows 4, 6 and 8 acquire the next
    ; band's colour, exactly like the moving F/U/E/L letters.
    ld a,(object_attr_y)
    ld (timex_ship_base_y),a
    ld a,4
    ld c,0x48
    call paint_timex_ship_entering_band
    ld a,6
    ld c,0x4a
    call paint_timex_ship_entering_band
    ld a,8
    ld c,0x4d
    jp paint_timex_ship_entering_band

paint_timex_ship_entering_band:
    ; Input A=exclusive relative band end, C=colour. Column and width stay
    ; prepared; an active ship scrolls exactly speed_pixels rows per frame.
    ld b,a
    ld a,c
    ld (object_attr_value),a
    ld a,(speed_pixels)
    ld d,a
    ld (object_attr_rows),a
    ld a,b
    sub d
    ld b,a
    ld a,(timex_ship_base_y)
    add a,b
    ld (object_attr_y),a
    jp timex_paint_object_rows

cleanup_timex_saved_ship0_attributes:
    ; Clear only the part of the old hull no longer covered by the new one;
    ; object_attr_value already holds the river attribute.
    ld a,(timex_bitmap_ship0_active)
    or a
    ret z
    ld a,8
    ld (object_attr_rows),a
    ld a,(ship0_active)
    or a
    jr z,cleanup_timex_ship0_rect
    ld a,(ship0_y)
    ld b,a
    ld a,(timex_bitmap_ship0_y)
    ld c,a
    ld a,b
    sub c
    ret z
    jr c,cleanup_timex_ship0_full_height
    cp 8
    jr nc,cleanup_timex_ship0_full_height
    ld (object_attr_rows),a
    jr cleanup_timex_ship0_rect
cleanup_timex_ship0_full_height:
    ld a,8
    ld (object_attr_rows),a
cleanup_timex_ship0_rect:
    ld a,(timex_bitmap_ship0_x)
    ld b,a
    ld a,(timex_bitmap_ship0_y)
    ld c,a
    call prepare_timex_ship_geometry
    jp timex_paint_object_rows

cleanup_timex_saved_ship1_attributes:
    ld a,(timex_bitmap_ship1_active)
    or a
    ret z
    ld a,(ship1_active)
    or a
    jr z,cleanup_timex_ship1_gone
    ld a,(ship1_y)
    ld b,a
    ld a,(timex_bitmap_ship1_y)
    ld c,a
    ld a,b
    sub c
    jr z,cleanup_timex_ship1_horizontal
    jr c,cleanup_timex_ship1_gone
    cp 8
    jr nc,cleanup_timex_ship1_gone
    ld (object_attr_rows),a
    call cleanup_timex_ship1_old_rect
    jr cleanup_timex_ship1_horizontal
cleanup_timex_ship1_gone:
    ; Despawn or a discontinuous move: the complete old hull reverts to the
    ; river attribute. A repositioned ship was already repainted in full.
    ld a,8
    ld (object_attr_rows),a
cleanup_timex_ship1_old_rect:
    ld a,(timex_bitmap_ship1_x)
    ld b,a
    ld a,(timex_bitmap_ship1_y)
    ld c,a
    call prepare_timex_ship_geometry
    jp timex_paint_object_rows

cleanup_timex_ship1_horizontal:
    ; A column leaves the footprint only when the hull just became aligned.
    ld a,(timex_bitmap_ship1_x)
    ld b,a
    ld a,(ship1_x)
    cp b
    ret z
    and 7
    ret nz
    ld a,(ship1_x)
    srl a
    srl a
    srl a
    ld c,a                           ; new leftmost column of the hull
    ld a,(ship1_x)
    cp b
    jr c,cleanup_timex_ship1_right_spill
    ; moved right: the departed column sits just left of the new hull
    ld a,c
    dec a
    jr cleanup_timex_ship1_side
cleanup_timex_ship1_right_spill:
    ; moved left: the old fifth column just right of the new hull departs
    ld a,c
    add a,4
cleanup_timex_ship1_side:
    ld (object_attr_col),a
    ld a,1
    ld (object_attr_width),a
    ld a,(timex_bitmap_ship1_y)
    ld (object_attr_y),a
    ld a,8
    ld (object_attr_rows),a
    jp timex_paint_object_rows
