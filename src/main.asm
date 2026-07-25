; Attribute Raid renderer V3 for ZX Spectrum 48K and Timex Hi-Color.
;
; The river is deliberately chunky like the Atari 2600 original: one course
; block is eight world scanlines high. This local experiment keeps that cadence
; but lets either bank move in one-pixel steps for an Atari 8-bit-like contour.
; Scrolling is still pixel-smooth.  Instead of repainting all 192 scanlines,
; each frame updates only the rows which cross a block boundary (alternating
; between zero and 19 rows with the slow modifier, 19 at base speed, and 38
; on the light two-pixel phases of adaptive fast mode). A fork is an optional
; land interval inside the river and is handled by the same dirty-row pass.
;
; Bitmap convention: 1 = green land/object, 0 = blue water/object cut-out.
; Normal attributes stay fixed; only the bridge's brown cells are updated.
;
; Vertical screen contract:
;   Y=0..15    immutable black upper margin
;   Y=16..167  scrolling playfield and all live actors
;   Y=168..175 LIVES/FUEL/SCORE relocated from the top
;   Y=176..183 detailed fuel indicator
;   Y=184..191 static copyright in play, scrolling between games
; The three bottom rows never belong to the world renderer.
;
; Coordinate convention: moving objects, including the tank, use pixel X.
; Bank edges use pixel X; islands and bridges remain byte-aligned. Explosions
; are the only live objects intentionally composed with XOR.
;
; Entry point: 32768 (0x8000).

org 32768

start:
    di
    ld sp,0xff00
    call init_attributes
    call init_course
    call full_redraw
    call init_shifted_sprites
    call init_entities
    call init_ay_sound
    ld a,2
    ld (lives),a
    call reset_score
    xor a
    ld (game_state),a
    ld a,7                         ; first HUD paint needs lives, score and fuel
    ld (hud_dirty),a
    call update_hud_if_dirty
    call paint_helicopter_attributes
    call paint_fuel_attributes
    call paint_balloon_attributes
    call paint_tank_attributes
    call draw_all_current_sprites_direct
    call show_ready_screen
    ei

main_loop:
    ; HALT is the only frame synchronisation point. The ROM interrupt wakes us
    ; once per 50 Hz display frame on every supported Spectrum/Timex model.
    xor a
    out (0xfe),a
    halt

    ld a,(game_state)
    ; Non-playing states own the whole frame and never fall through into river
    ; movement. This freezes the scene during an explosion and on GAME OVER.
    cp 1
    jp z,crash_wait_frame
    cp 2
    jp z,game_over_frame

    ; Profile the complete interactive frame, including input and AY work.
    ; This matters when diagnosing load that appears specifically while Q is
    ; held; the old marker started after both routines had already returned.
    call profile_begin
    call read_keyboard
    call update_ay_sound

    ld a,(paused)
    or a
    jr z,main_frame_active
    call profile_end
    jr main_loop

main_frame_active:
    call restore_frame_entities

    ld a,(speed_pixels)
    or a
    jr z,course_not_scrolled
    ld b,a
advance_frame_samples:
    push bc
    call advance_course_sample
    pop bc
    djnz advance_frame_samples

    call render_dirty_rows
course_not_scrolled:
    ; Standard entities are already absent. Timex keeps its uniform-background
    ; group resident through most movement, then clears the saved old rectangles
    ; inside update_entities before bridge writes and bitmap collision tests.
    call update_entities
    call update_hud_if_dirty
    ld a,(crashed)
    or a
    jr z,draw_updated_entities
    call begin_crash
    call update_hud_if_dirty
    call draw_crash_frame_entities
    call profile_end
    jr main_loop
draw_updated_entities:
    call draw_frame_entities
    call profile_end
    jp main_loop

restore_frame_entities:
    ; Bitmap sprites stay resident. Save the state which produced the current
    ; image, then remove only the deliberately XOR-composed impact effect.
    call snapshot_timex_object_attributes
    jp xor_current_hit_explosion

draw_frame_entities:
    ; update_entities has already transformed every resident bitmap directly.
    ; Add the new XOR explosion last, then run the hardware-specific colour
    ; engine. Bitmap composition is identical in both builds.
    call xor_current_hit_explosion
    jp update_frame_object_attributes

draw_crash_frame_entities:
    ; All ordinary sprites already hold their final direct image. Only the
    ; player explosion is additive/XOR and animates while the world is frozen.
    call xor_crash_explosion
    call update_frame_object_attributes
    jp paint_crash_attributes

update_frame_object_attributes:
    ; Bitmap work is complete before either colour engine starts.
#if TIMEX_HICOLOR
    call paint_helicopter_attributes
    call paint_fuel_attributes
    call paint_balloon_attributes
    call paint_tank_attributes
    jp cleanup_timex_saved_object_attributes
#else
    call restore_standard_saved_object_attributes
    call paint_helicopter_attributes
    call paint_fuel_attributes
    call paint_balloon_attributes
    jp paint_tank_attributes
#endif

#if not TIMEX_HICOLOR
restore_standard_saved_object_attributes:
    ; Temporarily expose the saved geometry to the proven 8x8 restorers. The
    ; live gameplay state is put back before current attributes are painted.
    ld a,(helicopter_active)
    push af
    ld a,(helicopter_x)
    push af
    ld a,(helicopter_y)
    push af
    ld a,(timex_attr_helicopter_active)
    ld (helicopter_active),a
    ld a,(timex_attr_helicopter_x)
    ld (helicopter_x),a
    ld a,(timex_attr_helicopter_y)
    ld (helicopter_y),a
    call restore_helicopter_attributes
    pop af
    ld (helicopter_y),a
    pop af
    ld (helicopter_x),a
    pop af
    ld (helicopter_active),a

    ld a,(fuel_active)
    push af
    ld a,(fuel_x)
    push af
    ld a,(fuel_y)
    push af
    ld a,(timex_attr_fuel_active)
    ld (fuel_active),a
    ld a,(timex_attr_fuel_x)
    ld (fuel_x),a
    ld a,(timex_attr_fuel_y)
    ld (fuel_y),a
    call restore_fuel_attributes
    pop af
    ld (fuel_y),a
    pop af
    ld (fuel_x),a
    pop af
    ld (fuel_active),a

    ld a,(balloon_active)
    push af
    ld a,(balloon_x)
    push af
    ld a,(balloon_y)
    push af
    ld a,(timex_attr_balloon_active)
    ld (balloon_active),a
    ld a,(timex_attr_balloon_x)
    ld (balloon_x),a
    ld a,(timex_attr_balloon_y)
    ld (balloon_y),a
    call restore_balloon_attributes
    pop af
    ld (balloon_y),a
    pop af
    ld (balloon_x),a
    pop af
    ld (balloon_active),a

    ld a,(tank_active)
    push af
    ld a,(tank_x)
    push af
    ld a,(tank_y)
    push af
    ld a,(timex_attr_tank_active)
    ld (tank_active),a
    ld a,(timex_attr_tank_x)
    ld (tank_x),a
    ld a,(timex_attr_tank_y)
    ld (tank_y),a
    call restore_tank_attributes
    pop af
    ld (tank_y),a
    pop af
    ld (tank_x),a
    pop af
    ld (tank_active),a
    ret
#endif


; ---------------------------------------------------------------------------
; Initialization
; ---------------------------------------------------------------------------

init_attributes:
#if TIMEX_HICOLOR
    jp init_timex_attributes
#else
    ; Standard ULA: two blank rows, nineteen playfield rows and three black
    ; status rows. Text uses white INK over black PAPER in rows 21..23.
    ld hl,0x5800
    ld (hl),0x4c
    ld de,0x5801
    ld bc,767
    ldir
    ld hl,0x5800
    xor a
    ld (hl),a
    ld de,0x5801
    ld bc,63
    ldir
    ld hl,0x5aa0
    ld (hl),0x47
    ld de,0x5aa1
    ld bc,95
    ldir
    ret
#endif

#if TIMEX_HICOLOR
init_timex_attributes:
    ; Timex Extended Color uses one attribute byte per 8x1 bitmap byte. Port
    ; FF mode 2 selects the second display file at 6000h..77ff as attributes.
    ld a,2
    out (0xff),a
    ld hl,0x6000
    ld (hl),0x4c
    ld de,0x6001
    ld bc,6143
    ldir

    xor a
    ld (timex_attr_y),a
    ld b,16
    ld c,0
init_timex_top_row:
    push bc
    ld a,(timex_attr_y)
    call timex_fill_attribute_scanline
    ld a,(timex_attr_y)
    inc a
    ld (timex_attr_y),a
    pop bc
    djnz init_timex_top_row

    ld a,PLAYFIELD_BOTTOM
    ld (timex_attr_y),a
    ld b,24
    ld c,0x47
init_timex_bottom_row:
    push bc
    ld a,(timex_attr_y)
    call timex_fill_attribute_scanline
    ld a,(timex_attr_y)
    inc a
    ld (timex_attr_y),a
    pop bc
    djnz init_timex_bottom_row
    ret
#endif

reinitialize_demo:
    call init_attributes
    call init_course
    call full_redraw
    call init_entities
    call init_ay_sound
    xor a
    ld (game_state),a
    ld (hud_initialized),a          ; full_redraw cleared the static labels too
    ld a,(hud_dirty)
    or 5                           ; new life restores both lives and fuel meter
    ld (hud_dirty),a
    call update_hud_if_dirty
    call paint_helicopter_attributes
    call paint_fuel_attributes
    call paint_balloon_attributes
    call paint_tank_attributes
    call draw_all_current_sprites_direct
    ret

start_new_game:
    ld a,2
    ld (lives),a
    ld a,(hud_dirty)
    or 1
    ld (hud_dirty),a
    call reset_score
    jp reinitialize_demo

reset_score:
    ld hl,score_digit_0
    ld (hl),48
    ld de,score_digit_1
    ld bc,5
    ldir
    ld a,4                         ; only the four high digits can ever change
    ld (score_redraw_count),a
    ld a,(hud_dirty)
    or 2
    ld (hud_dirty),a
    ret

update_hud_if_dirty:
    ; Bit 0 requests life, bit 1 score and bit 2 the six-cell fuel gauge. The
    ; labels and padding are copied only once; repainting the complete HUD
    ; was expensive enough to miss a 50 Hz interrupt and looked like a brief
    ; full-screen redraw even though only the HUD had actually changed.
    ld a,(hud_dirty)
    or a
    ret z
    ld (hud_update_mask),a
    xor a
    ld (hud_dirty),a
    ld a,(lives)
    add a,48
    ld (hud_life_digit),a

    ld a,(hud_initialized)
    or a
    jr nz,update_existing_hud_digits

    ld a,168
    ld (hud_clear_y),a
clear_hud_row:
    ld a,(hud_clear_y)
    call calc_screen_line_addr
    xor a
    ld (hl),a
    ld d,h
    ld e,l
    inc de
    ld bc,31
    ldir
    ld a,(hud_clear_y)
    inc a
    ld (hud_clear_y),a
    cp 192
    jr nz,clear_hud_row

    call update_fuel_meter_text
    call update_fuel_bar_text
    ld hl,hud_text
    ld b,32
    ld d,168
    ld e,0
    call draw_rom_text
    ld hl,fuel_bar_text
    ld b,32
    ld d,176
    ld e,0
    call draw_rom_text
    ld hl,footer_text
    ld b,32
    ld d,184
    ld e,0
    call draw_rom_text
    xor a
    ld (footer_index),a
    ld a,8
    ld (footer_timer),a
    ld a,1
    ld (hud_initialized),a
    xor a
    ld (score_redraw_count),a
    ret

update_existing_hud_digits:
    ld a,(hud_update_mask)
    and 1
    jr z,update_hud_score
    ld hl,hud_life_digit
    ld b,1
    ld d,168
    ld e,6
    call draw_rom_text
update_hud_score:
    ld a,(hud_update_mask)
    and 2
    jr z,update_hud_fuel
    ; Usually only the hundreds digit changed. Carry propagation enlarges the
    ; suffix to two, three or four glyphs, but unchanged digits are untouched.
    ld a,(score_redraw_count)
    or a
    jr z,update_hud_fuel
    ld b,a
    ld hl,score_digit_4             ; one byte beyond the changing suffix
    ld e,30                         ; screen column matching score_digit_4
update_score_start_column:
    dec hl
    dec e
    dec a
    jr nz,update_score_start_column
    ld d,168
    call draw_rom_text
    xor a
    ld (score_redraw_count),a
update_hud_fuel:
    ld a,(hud_update_mask)
    and 4
    ret z

    call update_fuel_meter_text
    ld hl,fuel_meter_0
    ld b,6
    ld d,168
    ld e,13
    call draw_rom_text
    call update_fuel_bar_text
    ld hl,fuel_bar_0
    ld b,24
    ld d,176
    ld e,7
    jp draw_rom_text

update_fuel_meter_text:
    ; Six ROM glyphs represent eight fuel units each. Only threshold crossings
    ; mark the HUD dirty, so normal fuel consumption never redraws every frame.
    ld a,(fuel_level)
    ld c,a
    ld hl,fuel_meter_0
    ld b,6
build_fuel_meter_cell:
    ld a,c
    cp 8
    jr c,empty_fuel_meter_cell
    sub 8
    ld c,a
    ld a,35                         ; '#': one full eighth of the tank
    jr store_fuel_meter_cell
empty_fuel_meter_cell:
    ld c,0
    ld a,46                         ; '.': depleted eighth
store_fuel_meter_cell:
    ld (hl),a
    inc hl
    djnz build_fuel_meter_cell
    ret

update_fuel_bar_text:
    ; Twenty-four cells expose two fuel units each, giving the bottom panel a
    ; much smoother indicator than the compact six-cell value in the HUD row.
    ld a,(fuel_level)
    ld c,a
    ld hl,fuel_bar_0
    ld b,24
build_fuel_bar_cell:
    ld a,c
    cp 2
    jr c,empty_fuel_bar_cell
    sub 2
    ld c,a
    ld a,35                         ; '#': two fuel units
    jr store_fuel_bar_cell
empty_fuel_bar_cell:
    ld c,0
    ld a,46                         ; '.': empty segment
store_fuel_bar_cell:
    ld (hl),a
    inc hl
    djnz build_fuel_bar_cell
    ret

update_footer_scroller:
    ; Called only by the between-games wait screen. Scroll one whole character
    ; every eight frames; active gameplay leaves the copyright row untouched.
    ; Moving the isolated footer costs 248 copied bytes plus one new glyph.
    ld a,(footer_timer)
    dec a
    ld (footer_timer),a
    ret nz
    ld a,8
    ld (footer_timer),a
    ld a,184
    ld (footer_row_y),a
    ld b,8
scroll_footer_bitmap_row:
    push bc
    ld a,(footer_row_y)
    call calc_screen_line_addr
    ld d,h
    ld e,l
    inc hl
    ld bc,31
    ldir
    ld a,(footer_row_y)
    inc a
    ld (footer_row_y),a
    pop bc
    djnz scroll_footer_bitmap_row

    ld a,(footer_index)
    ld l,a
    ld h,0
    ld de,footer_text
    add hl,de
    ld b,1
    ld d,184
    ld e,31
    call draw_rom_text
    ld a,(footer_index)
    inc a
    and 31
    ld (footer_index),a
    ret

paint_helicopter_attributes:
    ; The Atari sprite changes colour by scanline. Spectrum attributes cannot
    ; follow a freely moving 10-pixel object that closely, so use a crisp white
    ; INK on the existing blue PAPER without introducing an opaque rectangle.
    ld a,(helicopter_active)
    or a
    ret z
    ld a,0x4f
    jr prepare_helicopter_attributes

restore_helicopter_attributes:
    ; Water objects are kept away from the brown bridge, so the normal river
    ; attribute is always the correct value underneath the old helicopter.
    ld a,(helicopter_active)
    or a
    ret z
    ld a,0x4c
prepare_helicopter_attributes:
    ld (object_attr_value),a
    ld a,TIMEX_HICOLOR
    or a
    jp nz,prepare_timex_helicopter_attributes
    ld a,(helicopter_x)
    and 7
    ld a,2
    jr z,helicopter_attr_width_ready
    inc a
helicopter_attr_width_ready:
    ld (object_attr_width),a
    ld a,(helicopter_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a

    ld a,(helicopter_y)
    ld b,a
    srl a
    srl a
    srl a
    ld (object_attr_row),a
    ld a,b
    and 7
    ld a,2
    jr nz,helicopter_attr_rows_maybe_three
    jr helicopter_attr_rows_ready
helicopter_attr_rows_maybe_three:
    ld a,b
    and 7
    cp 7
    ld a,2
    jr nz,helicopter_attr_rows_ready
    inc a
helicopter_attr_rows_ready:
    ld (object_attr_rows),a
    jp paint_object_attribute_cells

prepare_timex_helicopter_attributes:
    ld a,(helicopter_x)
    and 7
    ld a,2
    jr z,timex_helicopter_width_ready
    inc a
timex_helicopter_width_ready:
    ld (object_attr_width),a
    ld a,(helicopter_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(helicopter_y)
    ld (object_attr_y),a
    ld a,10
    ld (object_attr_rows),a
    jp timex_paint_object_rows

paint_fuel_attributes:
    ld a,(fuel_active)
    or a
    ret z
    ld a,TIMEX_HICOLOR
    or a
    jp nz,paint_timex_fuel_attributes
    call prepare_fuel_attribute_geometry
    xor a
    ld (fuel_attr_phase),a          ; F/U/E/L bands start at magenta index zero
    ld a,(fuel_y)
    and 7
    cp 4
    ld a,0
    jr c,store_fuel_attr_repeat
    inc a                           ; favour the preceding letter after midpoint
store_fuel_attr_repeat:
    ld (fuel_attr_repeat),a

    ; F/U/E/L changes colour by character row, but all letters share one column.
    ; Compute that column once and then walk the linear attribute map by +32.
    ld a,(object_attr_row)
    ld b,a
    and 7
    rrca
    rrca
    rrca
    ld l,a
    ld a,(object_attr_col)
    add a,l
    ld l,a
    ld a,b
    srl a
    srl a
    srl a
    add a,0x58
    ld h,a
    ld de,32
paint_next_fuel_attribute:
    ld a,(object_attr_row)
    cp 21
    ret nc
    ld a,(fuel_attr_phase)
    and 1
    jr z,fuel_attribute_magenta
    ld a,0x4f                       ; U/L: BRIGHT white over blue cut-outs
    jr fuel_attribute_value_ready
fuel_attribute_magenta:
    ld a,0x4b                       ; F/E: BRIGHT magenta over blue cut-outs
fuel_attribute_value_ready:
    ld (hl),a
    add hl,de
    ld a,(object_attr_row)
    inc a
    ld (object_attr_row),a
    ld a,(fuel_attr_rows_remaining)
    dec a
    ld (fuel_attr_rows_remaining),a
    ret z
    ld a,(fuel_attr_repeat)
    or a
    jr z,advance_fuel_attr_phase
    xor a                           ; repeat F colour across a late boundary
    ld (fuel_attr_repeat),a
    jr paint_next_fuel_attribute
advance_fuel_attr_phase:
    ld a,(fuel_attr_phase)
    inc a
    and 3                           ; magenta, white, magenta, white
    ld (fuel_attr_phase),a
    jr paint_next_fuel_attribute

restore_fuel_attributes:
    ld a,(fuel_active)
    or a
    ret z
    ld a,TIMEX_HICOLOR
    or a
    jp nz,restore_timex_fuel_attributes
    call prepare_fuel_attribute_geometry
    ld a,0x4c                       ; ordinary green land / blue water cells
    ld (object_attr_value),a
    ld a,(fuel_attr_rows_remaining)
    ld (object_attr_rows),a
    jp paint_object_attribute_cells

paint_balloon_attributes:
    ; The Atari balloon is striped by scanline. Standard Spectrum attributes
    ; approximate the canopy with yellow/cyan cells and the lower envelope/
    ; basket with magenta, always retaining the same blue PAPER as the river.
    ld a,(balloon_active)
    or a
    ret z
    ld a,TIMEX_HICOLOR
    or a
    jp nz,paint_timex_balloon_attributes
    call prepare_balloon_attribute_geometry
paint_balloon_attribute_row:
    ld a,(object_attr_row)
    cp 21
    ret nc
    ld b,a
    and 7
    rrca
    rrca
    rrca
    ld l,a
    ld a,(object_attr_col)
    add a,l
    ld l,a
    ld a,b
    srl a
    srl a
    srl a
    add a,0x58
    ld h,a

    ld a,(object_attr_row)
    add a,a
    add a,a
    add a,a
    add a,4                         ; colour by the cell's vertical midpoint
    ld b,a
    ld a,(balloon_y)
    ld c,a
    ld a,b
    sub c
    jr c,balloon_attribute_yellow
    cp 4
    jr c,balloon_attribute_yellow
    cp 9
    jr c,balloon_attribute_cyan
    ld a,0x4b                       ; BRIGHT magenta over blue
    jr balloon_attribute_ready
balloon_attribute_yellow:
    ld a,0x4e                       ; BRIGHT yellow over blue
    jr balloon_attribute_ready
balloon_attribute_cyan:
    ld a,0x4d                       ; BRIGHT cyan over blue
balloon_attribute_ready:
    ld (hl),a
    inc l
    ld (hl),a
    ld a,(object_attr_row)
    inc a
    ld (object_attr_row),a
    ld a,(object_attr_rows)
    dec a
    ld (object_attr_rows),a
    jr nz,paint_balloon_attribute_row
    ret

restore_balloon_attributes:
    ld a,(balloon_active)
    or a
    ret z
    ld a,TIMEX_HICOLOR
    or a
    jp nz,restore_timex_balloon_attributes
    call prepare_balloon_attribute_geometry
    ld a,0x4c                       ; ordinary green land / blue water cells
    ld (object_attr_value),a
    jp paint_object_attribute_cells

prepare_balloon_attribute_geometry:
    ld a,2                          ; byte-aligned 16-pixel balloon
    ld (object_attr_width),a
    ld a,(balloon_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(balloon_y)
    ld b,a
    srl a
    srl a
    srl a
    ld (object_attr_row),a
    ld a,b
    and 7
    cp 5                            ; 20px uses three cells until offset five
    ld a,3
    jr c,balloon_attr_rows_ready
    inc a
balloon_attr_rows_ready:
    ld (object_attr_rows),a
    ret

paint_tank_attributes:
    ; The shore tank is XORed over set land pixels, so its silhouette consists
    ; of zero bits. Give those cut-outs black PAPER instead of ordinary blue;
    ; otherwise the tank looks like corruption in the bank geometry.
    ld a,(tank_active)
    or a
    ret z
    call tank_attributes_overlap_road
    ret nz
    ld a,0x44                       ; BRIGHT green land over black tank cut-out
    jr prepare_tank_attributes

restore_tank_attributes:
    ld a,(tank_active)
    or a
    ret z
    call tank_attributes_overlap_road
    ret nz
    ld a,0x4c                       ; ordinary green land / blue water cells
prepare_tank_attributes:
    ld (object_attr_value),a
    ld a,TIMEX_HICOLOR
    or a
    jp nz,prepare_timex_tank_attributes
    ld a,2                          ; byte-aligned 16-pixel tank
    ld (object_attr_width),a
    ld a,(tank_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a

    ld a,(tank_y)
    ld b,a
    srl a
    srl a
    srl a
    ld (object_attr_row),a
    ld a,b
    and 7
    cp 7                            ; ten rows need a third cell at offset seven
    ld a,2
    jr nz,tank_attr_rows_ready
    inc a
tank_attr_rows_ready:
    ld (object_attr_rows),a
    jp paint_object_attribute_cells

prepare_timex_tank_attributes:
    ld a,2
    ld (object_attr_width),a
    ld a,(tank_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(tank_y)
    ld (object_attr_y),a
    ld a,10
    ld (object_attr_rows),a
    jp timex_paint_object_rows

tank_attributes_overlap_road:
    ; Road attributes already use black PAPER. Leave them under a shore tank
    ; and, most importantly, never restore a road cell to the river palette.
    ld a,(bridge_active)
    ld b,a
    ld a,(destroyed_road_active)
    or b
    ret z
    ld a,(tank_y)
    ld b,10
    jp object_overlaps_bridge

prepare_fuel_attribute_geometry:
    ; The bitmap scrolls every pixel, but standard Spectrum colour remains on
    ; the 8-line attribute grid. Pick the dominant letter in a split cell so
    ; the four stable bands track F/U/E/L as closely as that hardware permits.
    ld a,1                          ; one attribute column: vertical 8px depot
    ld (object_attr_width),a
    ld a,(fuel_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(fuel_y)
    ld b,a
    srl a
    srl a
    srl a
    ld (object_attr_row),a
    ld a,b
    and 7
    ld a,4                          ; aligned 32px object occupies four cells
    jr z,fuel_attr_rows_ready
    inc a                           ; pixel scrolling can extend it into a fifth
fuel_attr_rows_ready:
    ld (fuel_attr_rows_remaining),a
    ret

paint_crash_attributes:
    ; A yellow 24x24 attribute envelope makes the small XOR explosion read as
    ; fire. It need not be restored: the next life redraws the whole course.
    ld a,0x4e
    ld (object_attr_value),a
    ld a,TIMEX_HICOLOR
    or a
    jr z,prepare_standard_crash_attributes
    ld a,3
    ld (object_attr_width),a
    ld a,(player_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(player_y)
    ld (object_attr_y),a
    ld a,13
    ld (object_attr_rows),a
    jp timex_paint_object_rows
prepare_standard_crash_attributes:
    ld a,3
    ld (object_attr_width),a
    ld (object_attr_rows),a
    ld a,(player_x)
    srl a
    srl a
    srl a
    ld (object_attr_col),a
    ld a,(player_y)
    srl a
    srl a
    srl a
    ld (object_attr_row),a

paint_object_attribute_cells:
    ld a,(object_attr_rows)
    or a
    ret z
clip_object_attribute_top:
    ld a,(object_attr_row)
    cp 2
    jr nc,prepare_object_attribute_address
    inc a
    ld (object_attr_row),a
    ld a,(object_attr_rows)
    dec a
    ld (object_attr_rows),a
    ret z
    jr clip_object_attribute_top

prepare_object_attribute_address:
    cp 21
    ret nc
    ld b,a
    and 7
    rrca
    rrca
    rrca
    ld l,a
    ld a,(object_attr_col)
    add a,l
    ld l,a
    ld a,b
    srl a
    srl a
    srl a
    add a,0x58
    ld h,a

    ; HL now points at the first cell. After each short horizontal run, add the
    ; remaining part of the 32-byte attribute-row stride instead of rebuilding
    ; the Spectrum attribute address from scratch for every row.
    ld a,(object_attr_width)
    ld e,a
    ld a,32
    sub e
    ld e,a
    ld d,0
paint_object_attribute_row:
    ld a,(object_attr_width)
    ld b,a
    ld a,(object_attr_value)
paint_object_attribute_byte:
    ld (hl),a
    inc hl
    djnz paint_object_attribute_byte
    ld a,(object_attr_row)
    inc a
    ld (object_attr_row),a
    ld a,(object_attr_rows)
    dec a
    ld (object_attr_rows),a
    ret z
    ld a,(object_attr_row)
    cp 21
    ret nc
    add hl,de
    jr paint_object_attribute_row


; ---------------------------------------------------------------------------
; Timex 8x1 attribute helpers
; ---------------------------------------------------------------------------

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
    ; pixel Y and a bitmap-byte X/width, so no vertical rounding is involved.
    ; Calculate the interleaved address once, then advance it directly instead
    ; of consulting screen_line_table again for every scanline.
    ld a,(object_attr_rows)
    or a
    ret z
timex_clip_object_top:
    ld a,(object_attr_y)
    cp 16
    jr nc,timex_prepare_object_address
    inc a
    ld (object_attr_y),a
    ld a,(object_attr_rows)
    dec a
    ld (object_attr_rows),a
    ret z
    jr timex_clip_object_top
timex_prepare_object_address:
    cp PLAYFIELD_BOTTOM
    ret nc
    call timex_attribute_address
    ld a,(object_attr_col)
    add a,l
    ld l,a
timex_paint_object_row:
    ld a,(object_attr_width)
    ld b,a
    ld c,a
    ld a,(object_attr_value)
timex_paint_object_byte:
    ld (hl),a
    inc l
    djnz timex_paint_object_byte
    ld a,l
    sub c
    ld l,a
timex_advance_object_row:
    ld a,(object_attr_y)
    inc a
    ld (object_attr_y),a
    ld a,(object_attr_rows)
    dec a
    ld (object_attr_rows),a
    ret z
    ld a,(object_attr_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    call timex_next_attribute_row
    jr timex_paint_object_row

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
    xor a
    ld (fuel_attr_phase),a
    ld a,8
    ld (fuel_attr_repeat),a
    ld a,(object_attr_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    call timex_attribute_address
    ld a,(object_attr_col)
    add a,l
    ld l,a
paint_timex_fuel_row:
    ld a,(fuel_attr_phase)
    and 1
    ld a,0x4f                       ; U/L white
    jr nz,timex_fuel_color_ready
    ld a,0x4b                       ; F/E magenta
timex_fuel_color_ready:
    ld (hl),a
    ld a,(object_attr_y)
    inc a
    ld (object_attr_y),a
    ld a,(object_attr_rows)
    dec a
    ld (object_attr_rows),a
    ret z
    ld a,(object_attr_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    call timex_next_attribute_row
    ld a,(fuel_attr_repeat)
    dec a
    ld (fuel_attr_repeat),a
    jr nz,paint_timex_fuel_row
    ld a,8
    ld (fuel_attr_repeat),a
    ld a,(fuel_attr_phase)
    inc a
    and 3
    ld (fuel_attr_phase),a
    jr paint_timex_fuel_row

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
    xor a
    ld (timex_color_phase),a
    ld a,(object_attr_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    call timex_attribute_address
    ld a,(object_attr_col)
    add a,l
    ld l,a
paint_timex_balloon_row:
    ld a,(timex_color_phase)
    cp 4
    ld a,0x4e                       ; yellow crown
    jr c,timex_balloon_color_ready
    ld a,(timex_color_phase)
    cp 9
    ld a,0x4d                       ; cyan middle stripe
    jr c,timex_balloon_color_ready
    ld a,0x4b                       ; magenta lower canopy, ropes and basket
timex_balloon_color_ready:
    ld (hl),a
    inc l
    ld (hl),a
    dec l
    ld a,(timex_color_phase)
    inc a
    ld (timex_color_phase),a
    ld a,(object_attr_y)
    inc a
    ld (object_attr_y),a
    ld a,(object_attr_rows)
    dec a
    ld (object_attr_rows),a
    ret z
    ld a,(object_attr_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    call timex_next_attribute_row
    jr paint_timex_balloon_row


; ---------------------------------------------------------------------------
; One-time sprite shift cache
; ---------------------------------------------------------------------------
;
; Rotating every sprite row at runtime made the cost depend heavily on X & 7:
; a frame where several objects happened to sit at shift seven could miss the
; 50 Hz budget. Build all eight three-byte variants once at startup instead.
; The wider ship has a separate five-byte table emitted with the source because
; its 32-bit expansion would make this compact 16-bit cache builder slower and
; more complicated for a transformation that never changes. Two-pixel
; projectiles use a smaller direct mask table and are not built here.

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
    ; Input HL=two-byte source, DE=cache destination, B=height.  The output is
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


; ---------------------------------------------------------------------------
; Eight-scanline course blocks
; ---------------------------------------------------------------------------
;
; course_block_head points at the block containing screen line zero.
; course_phase is that top sample's 0..7 offset inside the block.  Advancing
; phase by one scrolls every block boundary down by one physical pixel.
;
; Six page-aligned arrays hold 32 circular blocks:
;   outer left  column/mask
;   outer right column/mask
;   optional island left/right byte columns (255 = no island)

init_course:
    ld a,128
    ld (gen_center_x),a
    ld a,76
    ld (gen_half_x),a
    xor a
    ld (center_step),a
    ld (motion_timer),a
    ld a,254                        ; begin by narrowing two pixels per block
    ld (half_step),a
    ld a,0xa7
    ld (lfsr),a

    ld a,40
    ld (feature_countdown),a
    xor a
    ld (fork_step),a
    ld (next_feature),a
    ld (bridge_spawn_pending),a
    ld a,255
    ld (generated_island_left),a
    ld (generated_island_right),a

    ld a,255
    ld (course_block_head),a
    ld a,7
    ld (course_phase),a

    ld b,32
init_course_blocks:
    push bc
    call generate_next_block
    pop bc
    djnz init_course_blocks
    ret

advance_course_sample:
    ld a,(course_phase)
    inc a
    and 7
    ld (course_phase),a
    ret nz
    call generate_next_block
    ret

generate_next_block:
    ld a,(course_block_head)
    inc a
    and 31
    ld (course_block_head),a
    call generate_block
    ret

generate_block:
    call update_course_motion

    ld a,(gen_center_x)
    ld b,a
    ld a,(center_step)
    add a,b
    ld (gen_center_x),a

    ld a,(gen_half_x)
    ld b,a
    ld a,(half_step)
    add a,b
    cp 36
    jr nc,half_x_not_low
    ; The ordinary river may briefly narrow to 72 pixels. Fork generation
    ; waits for more room, so both lanes can still accept the wide ship.
    ld a,36
    ld (gen_half_x),a
    ld a,2
    ld (half_step),a
    jr half_x_ready
half_x_not_low:
    cp 113
    jr c,store_half_x
    ; At 224 pixels of water only a 16-pixel bank remains on either side:
    ; visibly near-full-screen, but still wide enough to hold a shore tank.
    ld a,112
    ld (gen_half_x),a
    ld a,254
    ld (half_step),a
    jr half_x_ready
store_half_x:
    ld (gen_half_x),a
half_x_ready:

    ; Wide water has less horizontal room to meander. Clamp the centre from
    ; the current half-width so neither edge can leave the 16-pixel land guard.
    ld a,(gen_half_x)
    add a,16
    ld c,a                          ; minimum centre = half-width + 16
    ld a,(gen_center_x)
    cp c
    jr nc,center_x_not_low
    ld a,c
    ld (gen_center_x),a
    ld a,1
    ld (center_step),a
center_x_not_low:
    ld a,(gen_half_x)
    ld b,a
    ld a,240
    sub b
    ld c,a                          ; maximum centre = 240 - half-width
    ld a,(gen_center_x)
    cp c
    jr c,center_x_ready
    jr z,center_x_ready
    ld a,c
    ld (gen_center_x),a
    ld a,255
    ld (center_step),a
center_x_ready:

    call update_course_feature

    ; Convert exact pixel edges to a byte column and one of eight masks. The
    ; old half-byte-only representation was what made every bend look boxed.
    ld a,(gen_center_x)
    ld b,a
    ld a,(gen_half_x)
    ld c,a

    ld a,b
    sub c
    ld d,a
    push af
    ld a,(course_block_head)
    ld l,a
    ld h,HIGH(block_left_x)
    pop af
    ld (hl),a
    ld d,a
    srl a
    srl a
    srl a
    ld b,a
    ld a,(course_block_head)
    ld l,a
    ld h,HIGH(block_left_col)
    ld (hl),b
    ld a,d
    and 7
    ld e,a
    ld d,0
    ld hl,left_edge_masks
    add hl,de
    ld b,(hl)
    ld a,(course_block_head)
    ld l,a
    ld h,HIGH(block_left_mask)
    ld a,b
    ld (hl),a

    ld a,(gen_center_x)
    ld b,a
    ld a,(gen_half_x)
    ld c,a
    ld a,b
    add a,c
    ld d,a
    push af
    ld a,(course_block_head)
    ld l,a
    ld h,HIGH(block_right_x)
    pop af
    ld (hl),a
    ld d,a
    srl a
    srl a
    srl a
    ld b,a
    ld a,(course_block_head)
    ld l,a
    ld h,HIGH(block_right_col)
    ld (hl),b
    ld a,d
    and 7
    ld e,a
    ld d,0
    ld hl,right_edge_masks
    add hl,de
    ld b,(hl)
    ld a,(course_block_head)
    ld l,a
    ld h,HIGH(block_right_mask)
    ld a,b
    ld (hl),a

    ld a,(course_block_head)
    ld e,a
    ld a,(generated_island_left)
    ld h,HIGH(block_island_left)
    ld l,e
    ld (hl),a
    ld a,(generated_island_right)
    ld h,HIGH(block_island_right)
    ld l,e
    ld (hl),a
    ret

update_course_motion:
    ld a,(motion_timer)
    or a
    jr z,pick_course_motion
    dec a
    ld (motion_timer),a
    ret
pick_course_motion:
    call lfsr_next
    ld b,a
    ; Keep a bend for 4..7 blocks (32..56 scanlines): less nervous than the
    ; first jagged experiment, but with much more shape than long near-lines.
    and 3
    add a,3
    ld (motion_timer),a
    ld a,b
    and 15
    ld e,a
    ld d,0
    ld hl,center_motion_table
    add hl,de
    ld a,(hl)
    ld (center_step),a
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

update_course_feature:
    ld a,255
    ld (generated_island_left),a
    ld (generated_island_right),a

    ld a,(fork_step)
    or a
    jr nz,generate_fork_block

    ld a,(feature_countdown)
    dec a
    ld (feature_countdown),a
    ret nz

    ld a,(next_feature)
    or a
    jr nz,generate_bridge_feature
    ld a,(gen_half_x)
    cp 56
    jr nc,generate_fork_feature
    ld a,4                          ; retry once the narrowing phase has turned
    ld (feature_countdown),a
    ret
generate_fork_feature:
    ld a,1
    ld (next_feature),a
    ld (fork_step),a
    ld a,2                          ; a fork always opens into safe wide lanes
    ld (half_step),a
    jr generate_fork_block

generate_bridge_feature:
    xor a
    ld (next_feature),a
    ld a,1
    ld (bridge_spawn_pending),a
    ld a,24
    ld (feature_countdown),a
    ret

generate_fork_block:
    ; The island grows 1,2,3,4 bytes, stays broad, then tapers symmetrically.
    ld a,(gen_center_x)
    srl a
    srl a
    srl a
    ld b,a
    ld a,(fork_step)
    dec a
    ld e,a
    ld d,0
    ld hl,fork_left_offsets
    add hl,de
    ld a,b
    add a,(hl)
    ld (generated_island_left),a
    ld b,a
    ld hl,fork_widths
    add hl,de
    ld a,(hl)
    dec a
    add a,b
    ld (generated_island_right),a

    ld a,(fork_step)
    inc a
    cp 11
    jr c,store_fork_step
    xor a
    ld (fork_step),a
    ld a,24
    ld (feature_countdown),a
    ret
store_fork_step:
    ld (fork_step),a
    ret


; ---------------------------------------------------------------------------
; Full-row reconstruction (whole screen at startup; isolated road repairs)
; ---------------------------------------------------------------------------

full_redraw:
    ; Clear everything first, including stale sprites and text from a previous
    ; life. The loop below deliberately reconstructs only playfield Y=16..167;
    ; rows 0..15 stay black and update_hud_if_dirty owns Y=168..191.
    ld hl,0x4000
    xor a
    ld (hl),a
    ld de,0x4001
    ld bc,6143
    ldir

    ld a,16                      ; first scanline below the upper black margin
    ld (redraw_y),a
full_redraw_row:
    ld a,(redraw_y)
    call render_full_world_row
    ld a,(redraw_y)
    inc a
    ld (redraw_y),a
    cp PLAYFIELD_BOTTOM                       ; first scanline of the lower margin
    jr nz,full_redraw_row
    ret

render_full_world_row:
    ; Input A=one playfield scanline. Unlike render_v3_row, this writes every
    ; byte of both banks and the complete island. It is intentionally reserved
    ; for startup and rows which a road/bridge operation cleared completely.
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    ld (dirty_y),a
    call calc_screen_line_addr
    ld (row_screen_addr),hl
    ld a,(dirty_y)
    call get_block_index_for_y
    ld a,l
    ld (row_block_index),a

    ; Full land to the left edge.
    ld h,HIGH(block_left_col)
    ld a,(hl)
    ld b,a
    ld hl,(row_screen_addr)
    ld a,b
    or a
    jr z,full_left_mask
    ld a,255
full_left_land:
    ld (hl),a
    inc l
    djnz full_left_land
full_left_mask:
    ld a,(row_block_index)
    ld l,a
    ld h,HIGH(block_left_mask)
    ld a,(hl)
    ld hl,(row_screen_addr)
    ld d,a
    ld a,(row_block_index)
    ld l,a
    ld h,HIGH(block_left_col)
    ld a,(hl)
    ld hl,(row_screen_addr)
    add a,l
    ld l,a
    ld (hl),d

    ; Right edge and complete land through column 31.
    ld a,(row_block_index)
    ld l,a
    ld h,HIGH(block_right_col)
    ld a,(hl)
    ld c,a
    ld hl,(row_screen_addr)
    add a,l
    ld l,a
    ld a,(row_block_index)
    ld e,a
    ld h,HIGH(block_right_mask)
    ld l,e
    ld a,(hl)
    ld d,a
    ld hl,(row_screen_addr)
    ld a,c
    add a,l
    ld l,a
    ld (hl),d
    ld a,31
    sub c
    jr z,full_draw_island
    ld b,a
    inc l
    ld a,255
full_right_land:
    ld (hl),a
    inc l
    djnz full_right_land

full_draw_island:
    jp draw_current_island_full

draw_current_island_full:
    ld a,(row_block_index)
    ld l,a
    ld h,HIGH(block_island_left)
    ld a,(hl)
    cp 255
    ret z
    ld c,a
    ld h,HIGH(block_island_right)
    ld a,(hl)
    sub c
    inc a
    ld b,a
    ld hl,(row_screen_addr)
    ld a,c
    add a,l
    ld l,a
    ld a,255
full_island_bytes:
    ld (hl),a
    inc l
    djnz full_island_bytes
    ret


; ---------------------------------------------------------------------------
; V3 dirty-row renderer
; ---------------------------------------------------------------------------
;
; If speed is s, a row changes block precisely when:
;
;     (course_phase - y) & 7 < s
;
; The matching residues are enumerated directly. Upper margin and status-panel
; rows are excluded, so no full-screen scan is needed.

render_dirty_rows:
    ; One residue class modulo eight changes for each scrolled pixel. At fast
    ; speed two residue classes are visited; no per-line change test is needed.
    ld a,(course_phase)
    ld (dirty_first_y),a
    ld a,(speed_pixels)
    ld (dirty_residues),a
dirty_residue_loop:
    ld a,(dirty_first_y)
    add a,16                       ; skip the two protected top character rows
    ld (dirty_y),a
    call get_block_index_for_y
    ld a,l
    ld (row_block_index),a
dirty_row_loop:
    call render_v3_row_indexed
    ld a,(dirty_y)
    add a,8
    cp PLAYFIELD_BOTTOM
    jr nc,dirty_next_residue
    ld (dirty_y),a
    ld a,(row_block_index)
    dec a
    and 31
    ld (row_block_index),a
    jr dirty_row_loop
dirty_next_residue:
    ld a,(dirty_first_y)
    dec a
    and 7
    ld (dirty_first_y),a
    ld a,(dirty_residues)
    dec a
    ld (dirty_residues),a
    jr nz,dirty_residue_loop
    ret

render_v3_row:
    ; Bridge repair and the dirty pass share this entry, so enforce upper-margin
    ; and bottom-panel ownership here as a final safety net.
    ld a,(dirty_y)
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    ld a,(dirty_y)
    call get_block_index_for_y
    ld a,l
    ld (row_block_index),a

render_v3_row_indexed:
    ; Dirty rows advance by exactly eight scanlines, so their circular block
    ; index is maintained by the caller. Bridge repair still enters above and
    ; calculates the first index normally.
    ld a,(dirty_y)
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    call calc_screen_line_addr
    ld (row_screen_addr),hl

    ; Left bank: land, partial edge, water.
    ; calc_screen_line_addr clobbers L, so reload the circular block index.
    ; The right-bank path already does this explicitly below.
    ld a,(row_block_index)
    ld l,a
    ld h,HIGH(block_left_col)
    ld d,(hl)
    ld h,HIGH(block_left_mask)
    ld a,(hl)
    ex af,af'
    ld hl,(row_screen_addr)
    ld a,l
    add a,d
    ld l,a
    dec l
    ld (hl),255
    inc l
    ex af,af'
    ld (hl),a
    inc l
    xor a
    ld (hl),a

    ; Right bank: water, partial edge, land.
    ld a,(row_block_index)
    ld l,a
    ld h,HIGH(block_right_col)
    ld d,(hl)
    ld h,HIGH(block_right_mask)
    ld a,(hl)
    ex af,af'
    ld hl,(row_screen_addr)
    ld a,l
    add a,d
    ld l,a
    dec l
    xor a
    ld (hl),a
    inc l
    ex af,af'
    ld (hl),a
    inc l
    ld (hl),255

    ; Compare the old and new island intervals.  Unchanged plateaus cost no
    ; writes; changing tapers touch only bytes exposed at either edge instead
    ; of clearing and repainting the whole overlapping island.
    ld a,(row_block_index)
    dec a
    and 31
    ld l,a
    ld h,HIGH(block_island_left)
    ld a,(hl)
    ld (dirty_old_island_left),a
    cp 255
    jp z,dirty_old_island_absent
    ld h,HIGH(block_island_right)
    ld a,(hl)
    ld (dirty_old_island_right),a

    ld a,(row_block_index)
    ld l,a
    ld h,HIGH(block_island_left)
    ld a,(hl)
    ld (dirty_new_island_left),a
    cp 255
    jp z,dirty_new_island_absent
    ld h,HIGH(block_island_right)
    ld a,(hl)
    ld (dirty_new_island_right),a

    ld b,a
    ld a,(dirty_old_island_right)
    cp b
    jr nz,dirty_island_changed
    ld a,(dirty_new_island_left)
    ld b,a
    ld a,(dirty_old_island_left)
    cp b
    ret z

dirty_island_changed:
    ; A one-byte sideways step is the hottest taper case. Update its two
    ; exposed edge bytes directly with one screen-address calculation each.
    ld a,(dirty_old_island_left)
    inc a
    ld b,a
    ld a,(dirty_new_island_left)
    cp b
    jr nz,dirty_check_shift_left
    ld a,(dirty_old_island_right)
    inc a
    ld b,a
    ld a,(dirty_new_island_right)
    cp b
    jr z,dirty_shift_island_right
dirty_check_shift_left:
    ld a,(dirty_new_island_left)
    inc a
    ld b,a
    ld a,(dirty_old_island_left)
    cp b
    jr nz,dirty_island_left_edges
    ld a,(dirty_new_island_right)
    inc a
    ld b,a
    ld a,(dirty_old_island_right)
    cp b
    jr z,dirty_shift_island_left

dirty_island_left_edges:
    ld a,(dirty_new_island_left)
    ld b,a
    ld a,(dirty_old_island_left)
    cp b
    jr z,dirty_island_right_edges
    jr c,dirty_clear_left_edge

    ; New island starts farther left: draw the newly covered bytes.
    sub b
    ld b,a
    ld a,(dirty_new_island_left)
    ld c,255
    call dirty_write_island_run
    jr dirty_island_right_edges

dirty_clear_left_edge:
    ; New island starts farther right: expose water at the old left edge.
    ld c,a
    ld a,b
    sub c
    ld b,a
    ld a,c
    ld c,0
    call dirty_write_island_run

dirty_island_right_edges:
    ld a,(dirty_new_island_right)
    ld b,a
    ld a,(dirty_old_island_right)
    cp b
    ret z
    jr c,dirty_draw_right_edge

    ; New island ends farther left: clear the old right-hand excess.
    sub b
    ld b,a
    ld a,(dirty_new_island_right)
    inc a
    ld c,0
    jp dirty_write_island_run

dirty_draw_right_edge:
    ; New island ends farther right: draw only the added right-hand bytes.
    ld c,a
    ld a,b
    sub c
    ld b,a
    ld a,c
    inc a
    ld c,255
    jp dirty_write_island_run

dirty_shift_island_right:
    ld hl,(row_screen_addr)
    ld a,(dirty_old_island_left)
    add a,l
    ld l,a
    xor a
    ld (hl),a
    ld hl,(row_screen_addr)
    ld a,(dirty_new_island_right)
    add a,l
    ld l,a
    ld (hl),255
    ret

dirty_shift_island_left:
    ld hl,(row_screen_addr)
    ld a,(dirty_old_island_right)
    add a,l
    ld l,a
    xor a
    ld (hl),a
    ld hl,(row_screen_addr)
    ld a,(dirty_new_island_left)
    add a,l
    ld l,a
    ld (hl),255
    ret

dirty_old_island_absent:
    ; Nothing to clear: draw the complete new interval, if one exists.
    ld a,(row_block_index)
    ld l,a
    ld h,HIGH(block_island_left)
    ld a,(hl)
    cp 255
    ret z
    ld c,a
    ld h,HIGH(block_island_right)
    ld a,(hl)
    sub c
    inc a
    ld b,a
    ld a,c
    ld c,255
    jp dirty_write_island_run

dirty_new_island_absent:
    ; The old interval disappeared: clear all of it.
    ld a,(dirty_old_island_left)
    ld c,a
    ld a,(dirty_old_island_right)
    sub c
    inc a
    ld b,a
    ld a,c
    ld c,0

dirty_write_island_run:
    ; Input A=start byte column, B=count, C=bitmap byte.
    ld hl,(row_screen_addr)
    add a,l
    ld l,a
    ld a,c
dirty_island_run_byte:
    ld (hl),a
    inc l
    djnz dirty_island_run_byte
    ret


; ---------------------------------------------------------------------------
; Course/screen address helpers
; ---------------------------------------------------------------------------

get_block_index_for_y:
    ; Input A = screen Y. Output L = circular block index 0..31.
    ld b,a
    ld a,7
    add a,b
    ld b,a
    ld a,(course_phase)
    ld c,a
    ld a,b
    sub c
    srl a
    srl a
    srl a
    ld b,a
    ld a,(course_block_head)
    sub b
    and 31
    ld l,a
    ret

get_bounds_for_y:
    ; Input A = Y. Output D = left edge column, E = right edge column.
    call get_block_index_for_y
    ld h,HIGH(block_left_col)
    ld d,(hl)
    ld h,HIGH(block_right_col)
    ld e,(hl)
    ret

calc_river_center_col:
    call get_bounds_for_y
    ld a,d
    add a,e
    srl a
    ret

get_pixel_lane_bounds:
    ; Input A=Y, C=current pixel X. Output D=min X and E=max X for the
    ; 16-pixel object's current water lane.  During a fork the island changes
    ; one river into two independent collision intervals.
    call get_block_index_for_y
    ld h,HIGH(block_left_col)
    ld a,(hl)
    inc a
    add a,a
    add a,a
    add a,a
    ld d,a

    ld h,HIGH(block_right_col)
    ld a,(hl)
    add a,a
    add a,a
    add a,a
    sub 16
    ld e,a

    ld h,HIGH(block_island_left)
    ld a,(hl)
    cp 255
    ret z
    add a,a
    add a,a
    add a,a
    ld b,a
    ld a,c
    cp b
    jr nc,pixel_lane_right_branch

    ; Left branch ends immediately before the first full island byte.
    ld a,b
    sub 16
    ld e,a
    ret

pixel_lane_right_branch:
    ; Right branch begins immediately after the final island byte.
    ld h,HIGH(block_island_right)
    ld a,(hl)
    inc a
    add a,a
    add a,a
    add a,a
    ld d,a
    ret

calc_safe_river_x:
    ; Input A=Y. Return a safe 16-pixel top-left X. If this sample contains an
    ; island, choose the left branch instead of spawning on land.
    ld c,0
    call get_pixel_lane_bounds
    ld a,e
    sub d
    srl a
    add a,d
    ret

calc_safe_river_x_wide:
    ; get_pixel_lane_bounds reserves 16 pixels. A 32-pixel ship needs another
    ; 16 pixels removed from the right-hand end before taking the midpoint.
    ld c,0
    call get_pixel_lane_bounds
    ld a,e
    sub 16
    ld e,a
    sub d
    srl a
    add a,d
    ret

calc_screen_line_addr:
    ; Input A = logical Y, output HL = Spectrum bitmap line address.
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,screen_table_page_ready
    inc h
screen_table_page_ready:
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl
    ret


; ---------------------------------------------------------------------------
; Atari-shaped XOR objects
; ---------------------------------------------------------------------------
;
; The original Atari object data is eight bits wide and displayed doubled in
; X. Most tables below preserve that 2:1 pixel shape as 16-pixel Spectrum
; sprites; the ships use a separate 32-pixel cache. The standard build erases
; every moving object before the river update. The Timex build removes actors
; which cross complex terrain first, but keeps uniform-water/land actors on
; screen until just before movement and collision; its redraw stores complete
; zero/one rows for that deferred group.

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
    ld (bridge_tank_next_mode),a
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
    ld (explosion_sound_timer),a
    ld (slow_phase),a
    ld (fast_phase),a
    ld (joystick_state),a
    ld a,1
    ld (requested_speed),a
    ld (speed_pixels),a
    ret

snapshot_timex_object_attributes:
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
    xor a
    ld (timex_deferred_cleared),a
    ld (timex_deferred_drawn),a
    ld (timex_ships_cleared),a
    ld (timex_ships_drawn),a
    ret

cleanup_timex_saved_object_attributes:
    ; Current colours have already been painted. Clear only the part of each
    ; old footprint which is no longer covered by the new rectangle; clearing
    ; the whole old rectangle here would briefly turn the moving sprite green.
    ld a,0x4c
    ld (object_attr_value),a
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
    ; A one-pixel rightward patrol crosses at most one byte boundary. The new
    ; shifted rectangle then starts one byte later, so clear that old column.
    ld a,(timex_attr_helicopter_x)
    srl a
    srl a
    srl a
    ld b,a
    ld a,(helicopter_x)
    srl a
    srl a
    srl a
    cp b
    ret c
    ret z
    sub b
    ld (object_attr_width),a
    ld a,b
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
    ld a,(timex_attr_fuel_active)
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

timex_suspend_deferred_entities:
    ; Preserve the actors which are safe to leave over the incremental terrain
    ; pass, then make the shared XOR walker skip them.
    ld a,(ship0_active)
    ld (timex_saved_ship0_active),a
    ld a,(ship1_active)
    ld (timex_saved_ship1_active),a
    ld a,(balloon_active)
    ld (timex_saved_balloon_active),a
    ld a,(fuel_active)
    ld (timex_saved_fuel_active),a
    ld a,(helicopter_active)
    ld (timex_saved_helicopter_active),a
    ld a,(tank_active)
    ld (timex_saved_tank_active),a
    xor a
    ld (ship0_active),a
    ld (ship1_active),a
    ld (balloon_active),a
    ld (fuel_active),a
    ld (helicopter_active),a
    ld (tank_active),a
    ret

timex_resume_deferred_entities:
    ld a,(timex_saved_ship0_active)
    ld (ship0_active),a
    ld a,(timex_saved_ship1_active)
    ld (ship1_active),a
    ld a,(timex_saved_balloon_active)
    ld (balloon_active),a
    ld a,(timex_saved_fuel_active)
    ld (fuel_active),a
    ld a,(timex_saved_helicopter_active)
    ld (helicopter_active),a
    ld a,(timex_saved_tank_active)
    ld (tank_active),a
    ret

timex_suspend_ships:
    ld a,(ship0_active)
    ld (timex_saved_ship0_active),a
    ld a,(ship1_active)
    ld (timex_saved_ship1_active),a
    xor a
    ld (ship0_active),a
    ld (ship1_active),a
    ret

timex_resume_ships:
    ld a,(timex_saved_ship0_active)
    ld (ship0_active),a
    ld a,(timex_saved_ship1_active)
    ld (ship1_active),a
    ret

clear_timex_deferred_entities_opaque:
    ; Restore the old uniform backgrounds directly. These writes deliberately
    ; include every zero/one in the rectangle rather than toggling sprite bits.
    ld a,(timex_bitmap_ship0_active)
    or a
    jr z,clear_timex_opaque_ship1
    ld a,(timex_bitmap_ship0_x)
    ld c,a
    and 7
    ld d,4
    jr z,clear_timex_ship0_width_ready
    inc d
clear_timex_ship0_width_ready:
    ld a,c
    srl a
    srl a
    srl a
    ld c,a
    ld a,(timex_bitmap_ship0_y)
    ld b,8
    ld e,0
    call fill_uniform_sprite_rect

clear_timex_opaque_ship1:
    ld a,(timex_bitmap_ship1_active)
    or a
    jr z,clear_timex_opaque_balloon
    ld a,(timex_bitmap_ship1_x)
    ld c,a
    and 7
    ld d,4
    jr z,clear_timex_ship1_width_ready
    inc d
clear_timex_ship1_width_ready:
    ld a,c
    srl a
    srl a
    srl a
    ld c,a
    ld a,(timex_bitmap_ship1_y)
    ld b,8
    ld e,0
    call fill_uniform_sprite_rect

clear_timex_nonship_entities_opaque:
clear_timex_opaque_balloon:
    ld a,(timex_attr_balloon_active)
    or a
    jr z,clear_timex_opaque_fuel
    ld a,(timex_attr_balloon_x)
    srl a
    srl a
    srl a
    ld c,a
    ld a,(timex_attr_balloon_y)
    ld b,20
    ld d,2
    ld e,0
    call fill_uniform_sprite_rect

clear_timex_opaque_fuel:
    ld a,(timex_attr_fuel_active)
    or a
    jr z,clear_timex_opaque_helicopter
    ld a,(timex_attr_fuel_x)
    srl a
    srl a
    srl a
    ld c,a
    ld a,(timex_attr_fuel_y)
    ld b,32
    ld d,1
    ld e,0
    call fill_uniform_sprite_rect

clear_timex_opaque_helicopter:
    ld a,(timex_attr_helicopter_active)
    or a
    jr z,clear_timex_opaque_tank
    ld a,(timex_attr_helicopter_x)
    ld c,a
    and 7
    ld d,2
    jr z,clear_timex_helicopter_width_ready
    inc d
clear_timex_helicopter_width_ready:
    ld a,c
    srl a
    srl a
    srl a
    ld c,a
    ld a,(timex_attr_helicopter_y)
    ld b,10
    ld e,0
    call fill_uniform_sprite_rect

clear_timex_opaque_tank:
    ld a,(timex_attr_tank_active)
    or a
    ret z
    ld a,(timex_attr_tank_x)
    srl a
    srl a
    srl a
    ld c,a
    ld a,(timex_attr_tank_y)
    ld b,10
    ld d,2
    ld e,255
    jp fill_uniform_sprite_rect

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

transition_timex_ships_opaque:
    ; On ordinary frames the old ships are still resident. Restore only rows
    ; and byte columns which leave their old bounding boxes, then overwrite the
    ; complete new shapes. Bridge frames already cleared them before road work.
    ld a,(timex_ships_cleared)
    or a
    jp nz,draw_timex_current_ships
    call cleanup_timex_ship0_bitmap_delta
    call cleanup_timex_ship1_bitmap_delta
    jp draw_timex_current_ships

cleanup_timex_ship0_bitmap_delta:
    ld a,(timex_bitmap_ship0_active)
    or a
    ret z
    call prepare_timex_ship0_old_rect
    ld a,(ship0_active)
    or a
    jr z,cleanup_timex_ship0_full
    ld a,(ship0_y)
    ld b,a
    ld a,(timex_bitmap_ship0_y)
    ld c,a
    ld a,b
    sub c
    ret z
    jr c,cleanup_timex_ship0_full
    cp 8
    jr nc,cleanup_timex_ship0_full
    ld b,a
    jr cleanup_timex_ship0_rows
cleanup_timex_ship0_full:
    ld b,8
cleanup_timex_ship0_rows:
    ld a,(timex_bitmap_ship0_y)
    push af
    ld a,(sprite_transition_old_col)
    ld c,a
    ld a,(sprite_transition_old_width)
    ld d,a
    pop af
    ld e,0
    jp fill_uniform_sprite_rect

prepare_timex_ship0_old_rect:
    ld a,(timex_bitmap_ship0_x)
    ld c,a
    and 7
    ld a,4
    jr z,prepare_timex_ship0_width_ready
    inc a
prepare_timex_ship0_width_ready:
    ld (sprite_transition_old_width),a
    ld a,c
    srl a
    srl a
    srl a
    ld (sprite_transition_old_col),a
    ret

cleanup_timex_ship1_bitmap_delta:
    ld a,(timex_bitmap_ship1_active)
    or a
    ret z
    call prepare_timex_ship1_old_rect
    ld a,(ship1_active)
    or a
    jr z,cleanup_timex_ship1_full
    ld a,(ship1_y)
    ld b,a
    ld a,(timex_bitmap_ship1_y)
    ld c,a
    ld a,b
    sub c
    jr c,cleanup_timex_ship1_full
    jr z,cleanup_timex_ship1_horizontal
    cp 8
    jr nc,cleanup_timex_ship1_full
    ld b,a
    ld a,(timex_bitmap_ship1_y)
    push af
    ld a,(sprite_transition_old_col)
    ld c,a
    ld a,(sprite_transition_old_width)
    ld d,a
    pop af
    ld e,0
    call fill_uniform_sprite_rect

cleanup_timex_ship1_horizontal:
    ; With one-pixel patrol movement, crossing a byte boundary to the right is
    ; the only case which exposes an old column; left movement expands the new
    ; five-byte rectangle over the complete old four-byte rectangle.
    ld a,(ship1_x)
    srl a
    srl a
    srl a
    ld b,a
    ld a,(sprite_transition_old_col)
    ld c,a
    ld a,b
    cp c
    ret c
    ret z
    sub c
    ld d,a
    ld a,(timex_bitmap_ship1_y)
    ld b,8
    ld e,0
    jp fill_uniform_sprite_rect

cleanup_timex_ship1_full:
    ld a,(timex_bitmap_ship1_y)
    ld b,8
    push af
    ld a,(sprite_transition_old_col)
    ld c,a
    ld a,(sprite_transition_old_width)
    ld d,a
    pop af
    ld e,0
    jp fill_uniform_sprite_rect

prepare_timex_ship1_old_rect:
    ld a,(timex_bitmap_ship1_x)
    ld c,a
    and 7
    ld a,4
    jr z,prepare_timex_ship1_width_ready
    inc a
prepare_timex_ship1_width_ready:
    ld (sprite_transition_old_width),a
    ld a,c
    srl a
    srl a
    srl a
    ld (sprite_transition_old_col),a
    ret

draw_timex_deferred_entities_opaque:
    ; These objects are guaranteed to occupy uniform bitmap backgrounds.
    ; Writing their complete cached rows therefore composes the new silhouette
    ; directly: zero source pixels erase, one source pixels paint.
    call draw_timex_current_ships
    jp draw_timex_opaque_nonship_entities

draw_timex_current_ships:
    ld a,(ship0_active)
    or a
    jr z,draw_timex_current_ship1
    ld a,(ship0_x)
    ld c,a
    ld a,(ship0_y)
    ld b,8
    ld de,ship_wide_shift_table
    call write_water_sprite_shifted_4xn

draw_timex_current_ship1:
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
    jr nz,timex_opaque_ship1_direction_ready
    ld de,ship_left_wide_shift_table
timex_opaque_ship1_direction_ready:
    pop af
    jp write_water_sprite_shifted_4xn

draw_timex_opaque_nonship_entities:
draw_timex_opaque_balloon:
    ld a,(balloon_active)
    or a
    jr z,draw_timex_opaque_fuel
    ld a,(balloon_x)
    srl a
    srl a
    srl a
    ld c,a
    ld a,(balloon_y)
    ld b,20
    ld de,balloon_sprite
    call write_water_sprite_2xn

draw_timex_opaque_fuel:
    ld a,(fuel_active)
    or a
    jr z,draw_timex_opaque_helicopter
    ld a,(fuel_x)
    srl a
    srl a
    srl a
    ld c,a
    ld a,(fuel_y)
    ld b,32
    ld de,fuel_vertical_sprite
    call write_water_sprite_1xn

draw_timex_opaque_helicopter:
    ld a,(helicopter_active)
    or a
    jr z,draw_timex_opaque_tank
    ld a,(helicopter_x)
    ld c,a
    ld a,(helicopter_y)
    ld b,10
    ld de,helicopter_shift_table
    push af
    ld a,(helicopter_dir)
    cp 255
    jr nz,timex_opaque_helicopter_right
    ld de,helicopter_left_shift_table
    ld a,(helicopter_frame)
    or a
    jr z,timex_opaque_helicopter_ready
    ld de,helicopter_left_alt_shift_table
    jr timex_opaque_helicopter_ready
timex_opaque_helicopter_right:
    ld a,(helicopter_frame)
    or a
    jr z,timex_opaque_helicopter_ready
    ld de,helicopter_alt_shift_table
timex_opaque_helicopter_ready:
    pop af
    call write_water_sprite_shifted_2xn

draw_timex_opaque_tank:
    ld a,(tank_active)
    or a
    ret z
    ld a,(tank_x)
    srl a
    srl a
    srl a
    ld c,a
    ld a,(tank_y)
    ld b,10
    ld de,tank_facing_right_sprite
    push af
    ld a,(tank_side)
    or a
    jr z,timex_opaque_tank_direction_ready
    ld de,tank_facing_left_sprite
timex_opaque_tank_direction_ready:
    pop af
    jp write_land_sprite_2xn

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
    ; A is the actual two-pixel left edge.
    ld c,a
    and 7
    ld a,1
    jr nz,prepare_transition_old_projectile_check
    jr prepare_transition_old_projectile_ready
prepare_transition_old_projectile_check:
    ld a,c
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
    jp write_world_sprite_shifted_2xn

draw_all_current_sprites_direct:
    call draw_current_bullet_direct
    call draw_current_shell_direct
    call draw_timex_current_ships
    call draw_current_balloon_direct
    call draw_current_fuel_direct
    call draw_current_enemy_plane_direct
    call draw_current_helicopter_direct
    call draw_current_shore_tank_direct
    call draw_current_bridge_tank_direct
    jp draw_current_player_direct

transition_player_direct:
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

transition_bullet_direct:
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
    call prepare_new_shell_geometry
    call cleanup_resident_sprite_delta
    jp draw_current_shell_direct

transition_all_resident_sprites:
    ; Common bitmap engine for Spectrum and Timex. The bridge/world layer has
    ; already finished, so every call below stores the final visible bytes.
    call transition_player_direct
    call transition_bullet_direct
    call transition_shell_direct
    call transition_ship0_direct
    call transition_ship1_direct
    call draw_timex_current_ships
    call transition_balloon_direct
    call transition_fuel_direct
    call transition_enemy_plane_direct
    call transition_helicopter_direct
    call transition_shore_tank_direct
    call transition_bridge_tank_direct
    jp draw_current_player_direct

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

xor_projectile_2xn:
    ; Input A=Y, C=actual left pixel X, B=height. Both projectiles are a solid
    ; two-pixel column. The generic 16-pixel blitter would fetch and touch
    ; three screen bytes per row; this hot path needs only two, which keeps a
    ; bridge frame with both simultaneous shots inside the 50 Hz budget.
    cp 192
    ret nc
    ld l,a
    ld a,192
    sub l
    ld h,a
    ld a,b
    cp h
    jr c,projectile_rows_ready
    jr z,projectile_rows_ready
    ld b,h
projectile_rows_ready:
    ; Preserve Y while HL indexes the two-byte mask for X&7. DE then holds the
    ; mask for every row: E is the first screen byte, D the possible spill.
    ld a,l
    ex af,af'
    ld a,c
    and 7
    add a,a
    ld e,a
    ld d,0
    ld hl,projectile_mask_table
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
    jr nc,projectile_table_page_ready
    inc h
projectile_table_page_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
projectile_sprite_row:
    pop hl
    ld a,c
    add a,l
    ld l,a
    ld a,e
    xor (hl)
    ld (hl),a
    inc l
    ld a,d
    xor (hl)
    ld (hl),a
    djnz projectile_sprite_row
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

    ; An intact bridge/road is the lower world layer. Its two centre rows use
    ; the same alternating full-byte marking as the incremental bridge writer.
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
    cp 7
    jr z,world_background_bridge_mark
    cp 8
    jr z,world_background_bridge_mark
    ld a,255
    ret
world_background_bridge_mark:
    ld a,(background_query_col)
    and 1
    jr nz,world_background_water
    ld a,255
    ret

world_background_course:
    ld a,(background_query_y)
    ld b,a
    ld a,(background_cache_y)
    cp b
    jr z,world_background_index_cached
    ld a,b
    call get_block_index_for_y
    ld a,l
    ld (background_cache_index),a
    ld a,(background_query_y)
    ld (background_cache_y),a
    jr world_background_index_ready
world_background_index_cached:
    ld a,(background_cache_index)
    ld l,a
world_background_index_ready:
    ld a,(background_query_col)
    ld b,a
    ld h,HIGH(block_left_col)
    cp (hl)
    jr c,world_background_land
    jr nz,world_background_check_right
    ld h,HIGH(block_left_mask)
    ld a,(hl)
    ret

world_background_check_right:
    ld a,b
    ld h,HIGH(block_right_col)
    cp (hl)
    jr c,world_background_check_island
    jr nz,world_background_land
    ld h,HIGH(block_right_mask)
    ld a,(hl)
    ret

world_background_check_island:
    ld h,HIGH(block_island_left)
    ld a,(hl)
    cp 255
    jr z,world_background_water
    ld c,a
    ld a,b
    cp c
    jr c,world_background_water
    ld h,HIGH(block_island_right)
    cp (hl)
    jr c,world_background_land
    jr z,world_background_land
world_background_water:
    xor a
    ret
world_background_land:
    ld a,255
    ret

reset_world_background_cache:
    ld a,255
    ld (background_cache_y),a
    ret

fill_world_background_rect:
    ; Input B=Y, C=rows, D=column, E=width. Reconstruct only exposed bytes of
    ; a sprite which may cross mixed terrain; never repaint an entire row.
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
    ld a,(transition_fill_y)
    call calc_screen_line_addr
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
    ld a,(transition_fill_y)
    inc a
    ld (transition_fill_y),a
    ld a,(transition_fill_rows)
    dec a
    ld (transition_fill_rows),a
    jr nz,fill_world_background_row
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
    ld a,(sprite_write_spill)
    or a
    jr z,write_water_shifted_2_skip_spill
    ld a,(de)
    ld (hl),a
write_water_shifted_2_skip_spill:
    inc de
    djnz write_water_shifted_2_row
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
    ld a,(sprite_write_spill)
    or a
    jr z,write_water_shifted_4_skip_spill
    ld a,(de)
    ld (hl),a
write_water_shifted_4_skip_spill:
    inc de
    djnz write_water_shifted_4_row
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
    ld (world_source_ptr),de
write_world_2_row:
    ld a,(world_write_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    ld hl,(world_source_ptr)
    ld a,(hl)
    ld (world_write_byte_0),a
    inc hl
    ld (world_source_ptr),hl
    ld a,(world_write_col)
    ld c,a
    ld a,(world_write_y)
    call get_world_background_byte
    ld b,a
    ld a,(world_write_byte_0)
    xor b
    ld (world_write_byte_0),a

    ld hl,(world_source_ptr)
    ld a,(hl)
    ld (world_write_byte_1),a
    inc hl
    ld (world_source_ptr),hl
    ld a,(world_write_col)
    inc a
    ld c,a
    ld a,(world_write_y)
    call get_world_background_byte
    ld b,a
    ld a,(world_write_byte_1)
    xor b
    ld (world_write_byte_1),a

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
    ; direct mixed-terrain compositor used by the crossing plane and bridge
    ; tank in both builds.
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
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (world_source_ptr),de
    ld a,c
    srl a
    srl a
    srl a
    ld (world_write_col),a
write_world_shifted_2_row:
    ld a,(world_write_y)
    cp PLAYFIELD_BOTTOM
    ret nc
    ld hl,(world_source_ptr)
    ld a,(hl)
    ld (world_write_byte_0),a
    inc hl
    ld (world_source_ptr),hl
    ld a,(world_write_col)
    ld c,a
    ld a,(world_write_y)
    call get_world_background_byte
    ld b,a
    ld a,(world_write_byte_0)
    xor b
    ld (world_write_byte_0),a

    ld hl,(world_source_ptr)
    ld a,(hl)
    ld (world_write_byte_1),a
    inc hl
    ld (world_source_ptr),hl
    ld a,(world_write_col)
    inc a
    ld c,a
    ld a,(world_write_y)
    call get_world_background_byte
    ld b,a
    ld a,(world_write_byte_1)
    xor b
    ld (world_write_byte_1),a

    ld hl,(world_source_ptr)
    ld a,(hl)
    ld (world_write_byte_2),a
    inc hl
    ld (world_source_ptr),hl
    ld a,(world_write_col)
    add a,2
    ld c,a
    ld a,(world_write_y)
    call get_world_background_byte
    ld b,a
    ld a,(world_write_byte_2)
    xor b
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
    jr z,write_world_shifted_2_skip_spill
    inc l
    ld a,(world_write_byte_2)
    ld (hl),a
write_world_shifted_2_skip_spill:
    ld a,(world_write_y)
    inc a
    ld (world_write_y),a
    ld a,(world_write_rows)
    dec a
    ld (world_write_rows),a
    jp nz,write_world_shifted_2_row
    ret

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
    ; between cells. White-on-black road attributes fill the land on both
    ; sides; the river span is then overwritten with the brown bridge colour.
    ld a,0x0a
    ld (bridge_center_attr),a
    jr bridge_paint_road_attribute_span

bridge_paint_destroyed_road_attributes:
    ; Broken bridge: retain both white approaches but restore blue water in
    ; the former span. The road remnant continues scrolling with the world.
    ld a,0x4c                       ; water must remain the same BRIGHT blue
    ld (bridge_center_attr),a
bridge_paint_road_attribute_span:
    ld a,TIMEX_HICOLOR
    or a
    jp nz,timex_bridge_paint_road_span
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

bridge_clear_road_attributes:
    ; Restore every attribute cell touched by the road, not merely the river
    ; span. This prevents white bank rectangles remaining after destruction.
    ld a,TIMEX_HICOLOR
    or a
    jp nz,timex_bridge_clear_road_span
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
    ld a,0x47                       ; BRIGHT white ink, black road markings
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
    ld a,0x47
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

bridge_update_attributes:
    ; The bitmap bridge moves every pixel, but its set of 8x8 colour cells
    ; normally does not.  Compare the old and new inclusive attribute spans:
    ; at most one row leaves at the top and one arrives at the bottom.
    ; bridge_restore_y is scratch for reconstructing the departing bitmap
    ; rows and has already advanced, so recover old Y from new Y - speed.
    ld a,TIMEX_HICOLOR
    or a
    jp nz,timex_bridge_update_attributes
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
    ; Input A=physical Y. Road approaches stay white/black while the centre is
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
    ld a,0x47
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
    ld a,0x47
timex_bridge_attr_right_byte:
    ld (hl),a
    inc l
    djnz timex_bridge_attr_right_byte
    ret


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
    call check_player_collision
    jp transition_all_resident_sprites

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
    and 1                           ; detailed bottom bar changes every 2 units
    ret nz
    jp mark_fuel_hud_dirty

consume_fuel:
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
    and 1
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
    ; Modes 1/2 are crossing and waiting/fire. Modes 3/4 are the corresponding
    ; states waiting above the playfield until the bridge reaches visible rows.
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
    ld a,(bridge_tank_mode)
    sub 2
    ld (bridge_tank_mode),a
    ld a,1
    ld (bridge_tank_active),a
    ld a,(bridge_y)
    add a,3
    ld (bridge_tank_y),a
    ld a,12
    ld (bridge_tank_fire_timer),a

    ld a,(bridge_tank_mode)
    cp 1
    jr nz,place_waiting_bridge_tank

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

place_waiting_bridge_tank:
    ld a,(bridge_tank_side)
    or a
    jr nz,place_waiting_tank_on_right
    ld a,(bridge_col)
    cp 2
    jr nc,bridge_tank_left_has_room
    xor a
    jr store_bridge_tank_col
bridge_tank_left_has_room:
    sub 2
    jr store_bridge_tank_col
place_waiting_tank_on_right:
    ld a,(bridge_col)
    ld b,a
    ld a,(bridge_width)
    add a,b
    cp 31
    jr c,store_bridge_tank_col
    ld a,30
store_bridge_tank_col:
    add a,a
    add a,a
    add a,a
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
    xor a
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
    call bridge_draw_initial_road_markings
    ret

setup_bridge_tank:
    ; Every bridge owns a second tank actor. Behaviours alternate so a crossing
    ; is guaranteed to be seen: pending mode 3 crosses, mode 4 waits and fires.
    xor a
    ld (bridge_tank_active),a
    ld a,(bridge_tank_side)
    xor 1
    ld (bridge_tank_side),a
    ld a,(bridge_tank_next_mode)
    or a
    jr nz,setup_waiting_bridge_tank
    ld a,3
    jr store_pending_bridge_tank_mode
setup_waiting_bridge_tank:
    ld a,4
store_pending_bridge_tank_mode:
    ld (bridge_tank_mode),a
    ld a,(bridge_tank_next_mode)
    xor 1
    ld (bridge_tank_next_mode),a
    ret
advance_active_bridge:
    ld a,(bridge_active)
    or a
    ret z
    ld a,(speed_pixels)
    or a
    ret z

    ; The dashed centre consists of two scanlines. Restore only the one or two
    ; rows that cease to be its centre before moving the bridge envelope.
    call bridge_restore_departing_road_markings

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
    call bridge_draw_entering_road_markings
    ld a,0x0a
    ld (bridge_center_attr),a
    call bridge_update_attributes
    ret

bridge_draw_initial_road_markings:
    ld a,(bridge_y)
    add a,7
    call bridge_draw_road_marking_row
    ld a,(bridge_y)
    add a,8
    jp bridge_draw_road_marking_row

update_destroyed_road:
    ; After the span is blown away, both white approaches remain part of the
    ; world and keep scrolling. Only their two dashed centre scanlines require
    ; bitmap work; the remainder is ordinary bank data under white attributes.
    ld a,(destroyed_road_active)
    or a
    ret z
    ld a,(speed_pixels)
    or a
    ret z

    ld b,a
    ld a,(bridge_y)
    add a,7
    ld (road_mark_y),a
    ld a,b
    ld (road_mark_rows),a
destroyed_road_restore_loop:
    ld a,(road_mark_y)
    cp PLAYFIELD_BOTTOM
    jr nc,destroyed_road_restore_next
    ld c,0
    call bridge_fill_full_bitmap_row
    ld a,(road_mark_y)
    call render_full_world_row
destroyed_road_restore_next:
    ld a,(road_mark_y)
    inc a
    ld (road_mark_y),a
    ld a,(road_mark_rows)
    dec a
    ld (road_mark_rows),a
    jr nz,destroyed_road_restore_loop

    ld a,(speed_pixels)
    ld b,a
    ld a,(bridge_y)
    add a,b
    ld (bridge_y),a

    call bridge_draw_entering_destroyed_road_markings
    ld a,0x4c                       ; fixed BRIGHT-blue water after destruction
    ld (bridge_center_attr),a
    call bridge_update_attributes
    ld a,(bridge_y)
    cp PLAYFIELD_BOTTOM
    ret c
    xor a
    ld (destroyed_road_active),a
    ret

bridge_draw_destroyed_road_markings:
    ld a,(bridge_y)
    add a,7
    call bridge_draw_destroyed_road_marking_row
    ld a,(bridge_y)
    add a,8
    jp bridge_draw_destroyed_road_marking_row

bridge_draw_entering_destroyed_road_markings:
    ld a,(speed_pixels)
    ld b,a
    ld a,(bridge_y)
    add a,9
    sub b
    ld (road_mark_y),a
    ld a,b
    ld (road_mark_rows),a
destroyed_road_draw_loop:
    ld a,(road_mark_y)
    call bridge_draw_destroyed_road_marking_row
    ld a,(road_mark_y)
    inc a
    ld (road_mark_y),a
    ld a,(road_mark_rows)
    dec a
    ld (road_mark_rows),a
    jr nz,destroyed_road_draw_loop
    ret

bridge_draw_destroyed_road_marking_row:
    ; Input A=Y. Draw alternating black gaps only over the two land approaches;
    ; the former bridge span stays untouched blue water.
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    call calc_screen_line_addr
    ld c,0
    ld a,(bridge_col)
    ld b,a
    call bridge_draw_road_segment

    ld a,(bridge_width)
    add a,l
    ld l,a
    ld a,(bridge_col)
    ld c,a
    ld a,(bridge_width)
    add a,c
    ld c,a
    ld b,a
    ld a,32
    sub b
    ld b,a
    jp bridge_draw_road_segment

bridge_draw_road_segment:
    ; Input HL=first byte, B=count, C=absolute byte column.
    ld a,b
    or a
    ret z
bridge_draw_road_segment_byte:
    ld a,c
    and 1
    jr z,bridge_draw_road_segment_white
    xor a
    jr bridge_store_road_segment_byte
bridge_draw_road_segment_white:
    ld a,255
bridge_store_road_segment_byte:
    ld (hl),a
    inc l
    inc c
    djnz bridge_draw_road_segment_byte
    ret

bridge_restore_departing_road_markings:
    ld a,(bridge_y)
    add a,7
    ld (road_mark_y),a
    ld a,(speed_pixels)
    ld (road_mark_rows),a
bridge_restore_road_row:
    ld a,(road_mark_y)
    call bridge_erase_road_marking_row
    ld a,(road_mark_y)
    inc a
    ld (road_mark_y),a
    ld a,(road_mark_rows)
    dec a
    ld (road_mark_rows),a
    jr nz,bridge_restore_road_row
    ret

bridge_erase_road_marking_row:
    ; Gap bytes are already 0xff. Only the sixteen former black dash bytes
    ; need restoring, halving writes on the bridge's hot scrolling path.
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    call calc_screen_line_addr
    inc l
    ld b,16
bridge_erase_road_dash:
    ld (hl),255
    inc l
    inc l
    djnz bridge_erase_road_dash
    ret

bridge_draw_entering_road_markings:
    ; New centre starts at bridge_y+9-speed: +8 at 1 px, +7 at 2 px.
    ld a,(speed_pixels)
    ld b,a
    ld a,(bridge_y)
    add a,9
    sub b
    ld (road_mark_y),a
    ld a,b
    ld (road_mark_rows),a
bridge_draw_entering_road_row:
    ld a,(road_mark_y)
    call bridge_draw_road_marking_row
    ld a,(road_mark_y)
    inc a
    ld (road_mark_y),a
    ld a,(road_mark_rows)
    dec a
    ld (road_mark_rows),a
    jr nz,bridge_draw_entering_road_row
    ret

bridge_fill_full_bitmap_row:
    ; Input A=Y, C=byte. Road rows are inside a bridge band, so land plus
    ; bridge makes the complete 256-pixel scanline solid before dash cutting.
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

bridge_draw_road_marking_row:
    ; Input A=Y. The intact bridge/road row is already solid 0xff, so write
    ; only the sixteen black dash bytes instead of redundantly storing all 32.
    cp 16
    ret c
    cp PLAYFIELD_BOTTOM
    ret nc
    call calc_screen_line_addr
    inc l
    ld b,16
bridge_road_dash_byte:
    ld (hl),0
    inc l
    inc l
    djnz bridge_road_dash_byte
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
    ; White approaches keep scrolling after the bridge span is gone. Their
    ; black dashed pixels are zero bits but not blue water, so geometry must
    ; reject a projectile there before the normal bitmap-only test.
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
    ; still contains resident sprites. Actors were tested explicitly above.
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
bullet_background_row:
    ld a,(bullet_background_y)
    cp PLAYFIELD_BOTTOM
    jr nc,bullet_background_collision
    ld a,(bullet_background_col)
    ld c,a
    ld a,(bullet_background_y)
    call get_world_background_byte
    ld b,a
    ld a,(bullet_background_mask_0)
    and b
    jr nz,bullet_background_collision
    ld a,(bullet_background_col)
    inc a
    ld c,a
    ld a,(bullet_background_y)
    call get_world_background_byte
    ld b,a
    ld a,(bullet_background_mask_1)
    and b
    jr nz,bullet_background_collision
    ld a,(bullet_background_y)
    inc a
    ld (bullet_background_y),a
    ld a,(bullet_background_rows)
    dec a
    ld (bullet_background_rows),a
    jr nz,bullet_background_row
    ret
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
    ; A waiting/firing tank belongs to the road approach and survives.
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
    ; Road dashes violate that invariant, so clear the complete scanline and
    ; use the deliberately slower full-row world reconstruction here.
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
    call preserve_road_tank_after_bridge
    call bridge_draw_destroyed_road_markings
    ret

preserve_road_tank_after_bridge:
    ; destroy_bridge_tank_bonus has already removed a mode-1 tank if it was on
    ; the span. A crossing tank still on an approach stops there and becomes a
    ; firing road tank; an existing mode-2 firing tank is left untouched.
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
    ; Modes 3/4 have not reached the visible road yet and must not materialise
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
    ; over road markings.
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
    ; The shell uses the same forgiving 6x6 player core as moving enemies,
    ; but its collision rectangle is the actual two-pixel projectile. Explicit
    ; actor checks precede the bitmap test because Timex ships deliberately
    ; remain resident while they are transformed by top/side deltas.
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
    ld a,32
    ld (object_collision_width),a
    ld a,(ship0_active)
    or a
    jr z,check_player_ship1
    ld a,(ship0_x)
    ld c,a
    ld a,(ship0_y)
    ld b,8
    call player_overlaps_object
    jp c,player_crashed
check_player_ship1:
    ld a,(ship1_active)
    or a
    jr z,check_player_balloon
    ld a,(ship1_x)
    ld c,a
    ld a,(ship1_y)
    ld b,8
    call player_overlaps_object
    jp c,player_crashed
check_player_balloon:
    ld a,16
    ld (object_collision_width),a
    ld a,(balloon_active)
    or a
    jr z,check_player_enemy_plane
    ld a,(balloon_x)
    ld c,a
    ld a,(balloon_y)
    ld b,20
    call player_overlaps_object
    jp c,player_crashed
check_player_enemy_plane:
    ld a,16
    ld (object_collision_width),a
    ld a,(enemy_plane_active)
    or a
    jr z,check_player_helicopter
    ld a,(enemy_plane_x)
    ld c,a
    ld a,(enemy_plane_y)
    ld b,8
    call player_overlaps_object
    jp c,player_crashed
check_player_helicopter:
    ld a,(helicopter_active)
    or a
    jr z,check_player_bridge_tank
    ld a,(helicopter_x)
    ld c,a
    ld a,(helicopter_y)
    ld b,10
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
    ld a,(bridge_tank_x)
    ld c,a
    ld a,(bridge_tank_y)
    ld b,10
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
    ret

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
    jr z,player_world_row
    ld a,(player_core_y)
    ld b,a
    add a,6
    ld c,a                           ; player bottom exclusive
    ld a,(bridge_y)
    cp c
    jr nc,player_world_row
    add a,16
    cp b
    jr c,player_world_row
    jr z,player_world_row
    jr player_background_hit

player_world_row:
    ld a,(player_core_y)
    call get_block_index_for_y
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
    jr nz,player_world_row
    or a
    ret
player_background_hit:
    xor a
    cp 1
    ret

player_overlaps_object:
    ; Input A=object Y, B=height, C=object pixel X. object_collision_width is
    ; 32 for ships and 16 for all other actors. The player's forgiving 6x6
    ; central core avoids deaths caused by transparent wing corners.
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


; ---------------------------------------------------------------------------
; Crash, lives and game-over state
; ---------------------------------------------------------------------------

begin_crash:
    ld a,1
    ld (game_state),a
    call silence_ay
    call start_ay_explosion
    ld a,75
    ld (explosion_timer),a
    ld a,5
    ld (explosion_anim_timer),a
    xor a
    ld (explosion_frame),a
    ld (bullet_active),a
    ld (tank_shell_active),a
    ld (fire_pending),a
    ld (hit_explosion_active),a
    ld a,(lives)
    or a
    ret z
    dec a
    ld (lives),a
    ld a,(hud_dirty)
    or 1
    ld (hud_dirty),a
    ret

crash_wait_frame:
    ; Freeze the river and all enemies for 75 display frames (1.5 seconds).
    ; Frozen actors remain resident in VRAM. Only replace the explosion on its
    ; five-frame animation boundary; the short AY burst still advances every
    ; frame independently of bitmap work.
    call update_ay_explosion
    call profile_begin

    ld a,(explosion_timer)
    dec a
    ld (explosion_timer),a
    jr z,crash_wait_finished

    ld a,(explosion_anim_timer)
    dec a
    ld (explosion_anim_timer),a
    jr nz,draw_crash_wait_frame

    ; Remove the old phase with the same XOR primitive that drew it.
    call xor_crash_explosion
    ld a,5
    ld (explosion_anim_timer),a
    ld a,(explosion_frame)
    inc a
    cp 3
    jr c,store_explosion_frame
    xor a
store_explosion_frame:
    ld (explosion_frame),a
    call xor_crash_explosion

draw_crash_wait_frame:
    call profile_end
    jp main_loop

crash_wait_finished:
    call profile_end
    ld a,(lives)
    or a
    jr z,crash_to_game_over
    call reinitialize_demo
    jp main_loop
crash_to_game_over:
    call show_game_over
    jp main_loop

show_ready_screen:
    call prepare_wait_screen
    ld hl,title_text
    ld b,14
    ld d,76
    ld e,9
    call draw_rom_text
    ld hl,start_text
    ld b,13
    ld d,100
    ld e,9
    call draw_rom_text
    jp finish_wait_screen

show_game_over:
    call prepare_wait_screen
    ld hl,game_over_text
    ld b,9
    ld d,76
    ld e,11
    call draw_rom_text
    ld hl,restart_text
    ld b,15
    ld d,100
    ld e,8
    call draw_rom_text
    jp finish_wait_screen

prepare_wait_screen:
    ; Independent black screen; ROM glyphs are copied directly to the bitmap,
    ; so this works without BASIC channels or system-variable assumptions.
    xor a
    out (0xfe),a
    call silence_ay
    ld (hud_initialized),a         ; next new game must restore erased labels
    ld hl,0x4000
    ld (hl),a
    ld de,0x4001
    ld bc,6143
    ldir
    ld a,TIMEX_HICOLOR
    or a
    jr nz,show_game_over_timex_attributes
    ld hl,0x5800
    ld (hl),0x47
    ld de,0x5801
    ld bc,767
    ldir
    jr show_game_over_attributes_ready
show_game_over_timex_attributes:
    ld hl,0x6000
    ld (hl),0x47
    ld de,0x6001
    ld bc,6143
    ldir
show_game_over_attributes_ready:
    ret

finish_wait_screen:
    ld hl,footer_text
    ld b,32
    ld d,184
    ld e,0
    call draw_rom_text
    xor a
    ld (footer_index),a
    ld a,8
    ld (footer_timer),a

    ld a,2
    ld (game_state),a
    ld a,1
    ld (fire_down),a
    ret

game_over_frame:
    ; Require a release after entering either waiting screen, then accept SPACE
    ; or Kempston FIRE as a clean edge for starting a new two-life game.
    call update_footer_scroller       ; movement is allowed only between games
    ld bc,0x7ffe
    in a,(c)
    bit 0,a
    jr z,game_over_fire_pressed
    ld bc,0x001f
    in a,(c)
    and 31
    cp 31
    jr nz,game_over_joystick_valid
    xor a
game_over_joystick_valid:
    bit 4,a
    jr nz,game_over_fire_pressed
    xor a
    ld (fire_down),a
    jp main_loop
game_over_fire_pressed:
    ld a,(fire_down)
    or a
    jp nz,main_loop
    ld a,1
    ld (fire_down),a
    call start_new_game
    jp main_loop

draw_rom_text:
    ; Input HL=ASCII text, B=length, D=pixel Y, E=byte column.
    ld (text_cursor),hl
    ld a,b
    ld (text_remaining),a
    ld a,d
    ld (text_y),a
    ld a,e
    ld (text_col),a
draw_rom_text_character:
    ld hl,(text_cursor)
    ld a,(hl)
    inc hl
    ld (text_cursor),hl
    call draw_rom_character
    ld a,(text_col)
    inc a
    ld (text_col),a
    ld a,(text_remaining)
    dec a
    ld (text_remaining),a
    jr nz,draw_rom_text_character
    ret

draw_rom_character:
    sub 32
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,0x3d00
    add hl,de
    ld (font_source),hl
    ld a,(text_y)
    ld (font_row_y),a
    ld a,8
    ld (font_rows),a
draw_rom_character_row:
    ld hl,(font_source)
    ld c,(hl)
    inc hl
    ld (font_source),hl
    ld a,(font_row_y)
    call calc_screen_line_addr
    ld a,(text_col)
    add a,l
    ld l,a
    ld (hl),c
    ld a,(font_row_y)
    inc a
    ld (font_row_y),a
    ld a,(font_rows)
    dec a
    ld (font_rows),a
    jr nz,draw_rom_character_row
    ret


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
    ld a,TIMEX_HICOLOR
    or a
    jr nz,detect_timex_2068_ay
    ld a,1                         ; standard build keeps the existing AY path
    ld (timex_ay_present),a
    ret

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
    ld a,TIMEX_HICOLOR
    or a
    jr nz,ay_write_timex_register
    pop af
    ld bc,0xfffd
    out (c),a
    ld b,0xbf
    ld a,e
    out (c),a
    ret
ay_write_timex_register:
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


; ---------------------------------------------------------------------------
; Keyboard and border profiling
; ---------------------------------------------------------------------------

read_keyboard:
    xor a
    ld (player_move),a

    ; Base speed is 1 px/frame. Q requests adaptive fast scrolling; A requests
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

    ; Normal speed also resets both fractional cadence generators.
    ld (speed_pixels),a
    xor a
    ld (slow_phase),a
    ld (fast_phase),a
    jr read_steering

resolve_fast_speed:
    ; Two-pixel scrolling doubles the bank pass from 19 to 38 scanlines. Never
    ; combine that peak with a tank, bridge/road repair or either projectile.
    ; In a light scene alternate 1/2 pixels for a 1.5 px average; a heavy scene
    ; is capped at one pixel so every frame retains enough 50 Hz headroom.
    ld a,(bridge_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(destroyed_road_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(tank_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(bridge_tank_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(enemy_plane_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(bullet_active)
    or a
    jr nz,resolve_heavy_fast_speed
    ld a,(tank_shell_active)
    or a
    jr nz,resolve_heavy_fast_speed

    ld a,(fast_phase)
    ld b,a
    xor 1
    ld (fast_phase),a
    ld a,b
    inc a                           ; phase 0/1 resolves to 1/2 pixels
    ld (speed_pixels),a
    xor a
    ld (slow_phase),a
    jr read_steering

resolve_heavy_fast_speed:
    ld a,1
    ld (speed_pixels),a
    xor a
    ld (slow_phase),a
    ld (fast_phase),a
    jr read_steering

resolve_slow_speed:
    xor a
    ld (fast_phase),a
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
    ld a,17                         ; 16 audible AY frames plus final mute
    ld (shot_sound_timer),a
    ld a,80                         ; lower initial pitch; period rises per frame
    ld (shot_sound_period),a
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


; ---------------------------------------------------------------------------
; Constant data
; ---------------------------------------------------------------------------

center_motion_table:
    ; Signed centre motion in pixels per eight-line block. Half-width follows
    ; its own long +/-2 cycle; combining both motions creates fixed-bank runs,
    ; uneven bends and breathing sections without mirrored shorelines.
    db 0,1,254,1, 2,255,0,2
    db 255,1,254,0, 1,255,2,254

left_edge_masks:
    db 0x00,0x80,0xc0,0xe0,0xf0,0xf8,0xfc,0xfe
right_edge_masks:
    db 0xff,0x7f,0x3f,0x1f,0x0f,0x07,0x03,0x01

ay_engine_noise_periods:
    ; Slow, normal, fast. AY noise frequency rises as the period falls.
    db 31,20,10
ay_engine_volumes:
    db 4,6,8

fork_left_offsets:
    db 0,255,255,254,254,254,254,255,255,0
fork_widths:
    db 1,2,3,4,4,4,4,3,2,1

; Original River Raid silhouettes reconstructed from the interlaced Atari
; object tables and doubled horizontally, like the 2600 display.
player_jet_sprite:
    db 0x00,0xc0, 0x00,0xc0, 0x00,0xc0, 0x03,0xf0
    db 0x0f,0xfc, 0x3f,0xff, 0x3f,0xff, 0x3c,0xcf
    db 0x30,0xc3, 0x00,0xc0, 0x03,0xf0, 0x0f,0xfc, 0x0c,0xcc
    db 0x00,0x00

; Exact Atari JetMove silhouette in on-screen order, doubled horizontally.
; The 2600 used REFP0 for the opposite turn; these two tables are exact mirrors.
player_jet_left_sprite:
    db 0x03,0x00, 0x03,0x00, 0x03,0x00, 0x03,0xc0
    db 0x0f,0xf0, 0x3f,0xf0, 0x3f,0xf0, 0x3f,0x30
    db 0x33,0x00, 0x03,0x00, 0x03,0xc0, 0x0f,0xf0
    db 0x3f,0x30, 0x30,0x00

player_jet_right_sprite:
    db 0x00,0xc0, 0x00,0xc0, 0x00,0xc0, 0x03,0xc0
    db 0x0f,0xf0, 0x0f,0xfc, 0x0f,0xfc, 0x0c,0xfc
    db 0x00,0xcc, 0x00,0xc0, 0x03,0xc0, 0x0f,0xf0
    db 0x0c,0xfc, 0x00,0x0c

projectile_mask_table:
    ; A two-pixel column shifted through a byte. Only shift seven spills.
    db 0xc0,0x00, 0x60,0x00, 0x30,0x00, 0x18,0x00
    db 0x0c,0x00, 0x06,0x00, 0x03,0x00, 0x01,0x80

atari_ship_sprite:
    db 0x03,0x00, 0x03,0x00, 0x0f,0x00, 0x3f,0xc0
    db 0xff,0xff, 0xff,0xfc, 0xff,0xf0, 0x3f,0xf0

enemy_plane_sprite:
    ; The old table accidentally swapped each pair of rows after the first.
    db 0xc0,0x00, 0x00,0x00, 0xf0,0x3c, 0xff,0xff
    db 0x30,0xff, 0x0f,0xc0, 0x0f,0x00, 0x00,0x00

atari_helicopter_sprite:
    ; Exact Heli0/Heli1 output reconstructed by interleaving the Atari 2600
    ; Heli*A and Heli*B kernel rows, then doubling every source pixel in X.
    ; Only the first two rotor scanlines change between animation frames.
    db 0x00,0x3f, 0x03,0xf0, 0x00,0x30, 0x00,0xfc, 0xc3,0xff
    db 0xff,0xff, 0xff,0xff, 0xc0,0xfc, 0x00,0x30, 0x00,0xfc

atari_helicopter_sprite_alt:
    db 0x03,0xf0, 0x00,0x3f, 0x00,0x30, 0x00,0xfc, 0xc3,0xff
    db 0xff,0xff, 0xff,0xff, 0xc0,0xfc, 0x00,0x30, 0x00,0xfc

atari_helicopter_sprite_left:
    ; Atari used REFP1 to mirror the whole player object. Spectrum needs the
    ; reflected bytes explicitly so a helicopter always faces its movement.
    db 0xfc,0x00, 0x0f,0xc0, 0x0c,0x00, 0x3f,0x00, 0xff,0xc3
    db 0xff,0xff, 0xff,0xff, 0x3f,0x03, 0x0c,0x00, 0x3f,0x00

atari_helicopter_sprite_left_alt:
    db 0x0f,0xc0, 0xfc,0x00, 0x0c,0x00, 0x3f,0x00, 0xff,0xc3
    db 0xff,0xff, 0xff,0xff, 0x3f,0x03, 0x0c,0x00, 0x3f,0x00

; Side-view tank: a small turret and barrel sit clearly above the rectangular
; body and broken track. Mirrored data makes the gun point toward the river.
tank_facing_right_sprite:
    db 0x07,0x80, 0x07,0x80, 0x03,0xff, 0x0f,0xf0, 0x3f,0xfc
    db 0xff,0xff, 0xff,0xff, 0xcc,0x33, 0xff,0xff, 0x3f,0xfc

tank_facing_left_sprite:
    db 0x01,0xe0, 0x01,0xe0, 0xff,0xc0, 0x0f,0xf0, 0x3f,0xfc
    db 0xff,0xff, 0xff,0xff, 0xcc,0x33, 0xff,0xff, 0x3f,0xfc

tank_splash_sprite_0:
    ; Descending ball and first two drops.
    db 0x01,0x80, 0x03,0xc0, 0x01,0x80, 0x00,0x00, 0x08,0x10, 0x03,0xc0
tank_splash_sprite_1:
    ; The ball disappears into two widening water rings.
    db 0x00,0x00, 0x08,0x10, 0x04,0x20, 0x00,0x00, 0x0f,0xf0, 0x3c,0x3c

explosion_sprite_0:
    db 0x00,0x00, 0x00,0x00, 0x01,0x80, 0x02,0x40
    db 0x09,0x90, 0x04,0x20, 0x1d,0xb8, 0x07,0xe0
    db 0x1d,0xb8, 0x04,0x20, 0x09,0x90, 0x02,0x40, 0x01,0x80

explosion_sprite_1:
    db 0x00,0x00, 0x10,0x08, 0x02,0x40, 0x49,0x92
    db 0x14,0x28, 0x03,0xc0, 0x2f,0xf4, 0x0f,0xf0
    db 0x2f,0xf4, 0x03,0xc0, 0x14,0x28, 0x49,0x92, 0x10,0x08

explosion_sprite_2:
    db 0x20,0x04, 0x08,0x10, 0x80,0x01, 0x24,0x92
    db 0x5a,0x5a, 0x0f,0xf0, 0x7f,0xfe, 0x3f,0xfc
    db 0x7f,0xfe, 0x0f,0xf0, 0x5a,0x5a, 0x24,0x92, 0x80,0x01

game_over_text:
    db 71,65,77,69,32,79,86,69,82
restart_text:
    db 70,73,82,69,32,84,79,32,82,69,83,84,65,82,84
title_text:
    db 65,84,84,82,73,66,85,84,69,32,82,65,73,68
start_text:
    db 70,73,82,69,32,84,79,32,83,84,65,82,84

hud_text:
    db 76,73,86,69,83,58
hud_life_digit:
    db 50
    db 32,70,85,69,76,58
fuel_meter_0: db 35
fuel_meter_1: db 35
fuel_meter_2: db 35
fuel_meter_3: db 35
fuel_meter_4: db 35
fuel_meter_5: db 35
    db 32,83,67,79,82,69,58
score_digit_0: db 48
score_digit_1: db 48
score_digit_2: db 48
score_digit_3: db 48
score_digit_4: db 48
score_digit_5: db 48

fuel_bar_text:
    db 70,85,69,76,58,32,91        ; "FUEL: ["
fuel_bar_0: db 35
fuel_bar_1: db 35
fuel_bar_2: db 35
fuel_bar_3: db 35
fuel_bar_4: db 35
fuel_bar_5: db 35
fuel_bar_6: db 35
fuel_bar_7: db 35
fuel_bar_8: db 35
fuel_bar_9: db 35
fuel_bar_10: db 35
fuel_bar_11: db 35
fuel_bar_12: db 35
fuel_bar_13: db 35
fuel_bar_14: db 35
fuel_bar_15: db 35
fuel_bar_16: db 35
fuel_bar_17: db 35
fuel_bar_18: db 35
fuel_bar_19: db 35
fuel_bar_20: db 35
fuel_bar_21: db 35
fuel_bar_22: db 35
fuel_bar_23: db 35
    db 93                           ; ']'

footer_text:
    db 40,67,41,32,50,48,50,54,32
    db 103,105,116,104,117,98,46,99,111,109
    db 47,100,116,122,45,108,97,98,115,32,32,32,32

timex_rom_signature:
    db 84,105,109,101,120            ; "Timex" at HOME ROM $113D on a 2068

; A byte-aligned 16x20 balloon reconstructed from the GIF reference: broad
; striped envelope, long ropes and a hanging basket. It is static in world X.
balloon_sprite:
    db 0x03,0xc0, 0x0f,0xf0, 0x3f,0xfc, 0x7f,0xfe
    db 0xff,0xff, 0xff,0xff, 0xff,0xff, 0xff,0xff
    db 0x7f,0xfe, 0x3f,0xfc, 0x0f,0xf0, 0x02,0x40
    db 0x02,0x40, 0x02,0x40, 0x02,0x40, 0x02,0x40
    db 0x07,0xe0, 0x07,0xe0, 0x07,0xe0, 0x03,0xc0

; Four compact 8x8 cells form the vertical Atari-style refuelling depot. Like
; the original FuelA/FuelB data, set pixels are the solid coloured body and the
; letters are transparent cut-outs. The attribute painter assigns stable
; magenta/white/magenta/white bands while the cut-outs show blue river water.
fuel_vertical_sprite:
    ; F
    db 0xff,0x81,0x9f,0x9f,0x83,0x9f,0x9f,0xff
    ; U
    db 0xff,0x99,0x99,0x99,0x99,0x99,0xc3,0xff
    ; E
    db 0xff,0x81,0x9f,0x9f,0x83,0x9f,0x81,0xff
    ; L
    db 0xff,0x9f,0x9f,0x9f,0x9f,0x9f,0x81,0xff

; The original 16-bit boat above is expanded once in the source to 32 pixels:
; every Atari-shaped pixel becomes two Spectrum pixels. Each X shift stores
; eight rows of five bytes (four visible bytes plus a right-hand spill byte).
ship_wide_shift_table:
    dw ship_wide_shift_data,ship_wide_shift_data+40
    dw ship_wide_shift_data+80,ship_wide_shift_data+120
    dw ship_wide_shift_data+160,ship_wide_shift_data+200
    dw ship_wide_shift_data+240,ship_wide_shift_data+280
ship_wide_shift_data:
    db 0x00,0x0f,0x00,0x00,0x00,0x00,0x0f,0x00,0x00,0x00
    db 0x00,0xff,0x00,0x00,0x00,0x0f,0xff,0xf0,0x00,0x00
    db 0xff,0xff,0xff,0xff,0x00,0xff,0xff,0xff,0xf0,0x00
    db 0xff,0xff,0xff,0x00,0x00,0x0f,0xff,0xff,0x00,0x00
    db 0x00,0x07,0x80,0x00,0x00,0x00,0x07,0x80,0x00,0x00
    db 0x00,0x7f,0x80,0x00,0x00,0x07,0xff,0xf8,0x00,0x00
    db 0x7f,0xff,0xff,0xff,0x80,0x7f,0xff,0xff,0xf8,0x00
    db 0x7f,0xff,0xff,0x80,0x00,0x07,0xff,0xff,0x80,0x00
    db 0x00,0x03,0xc0,0x00,0x00,0x00,0x03,0xc0,0x00,0x00
    db 0x00,0x3f,0xc0,0x00,0x00,0x03,0xff,0xfc,0x00,0x00
    db 0x3f,0xff,0xff,0xff,0xc0,0x3f,0xff,0xff,0xfc,0x00
    db 0x3f,0xff,0xff,0xc0,0x00,0x03,0xff,0xff,0xc0,0x00
    db 0x00,0x01,0xe0,0x00,0x00,0x00,0x01,0xe0,0x00,0x00
    db 0x00,0x1f,0xe0,0x00,0x00,0x01,0xff,0xfe,0x00,0x00
    db 0x1f,0xff,0xff,0xff,0xe0,0x1f,0xff,0xff,0xfe,0x00
    db 0x1f,0xff,0xff,0xe0,0x00,0x01,0xff,0xff,0xe0,0x00
    db 0x00,0x00,0xf0,0x00,0x00,0x00,0x00,0xf0,0x00,0x00
    db 0x00,0x0f,0xf0,0x00,0x00,0x00,0xff,0xff,0x00,0x00
    db 0x0f,0xff,0xff,0xff,0xf0,0x0f,0xff,0xff,0xff,0x00
    db 0x0f,0xff,0xff,0xf0,0x00,0x00,0xff,0xff,0xf0,0x00
    db 0x00,0x00,0x78,0x00,0x00,0x00,0x00,0x78,0x00,0x00
    db 0x00,0x07,0xf8,0x00,0x00,0x00,0x7f,0xff,0x80,0x00
    db 0x07,0xff,0xff,0xff,0xf8,0x07,0xff,0xff,0xff,0x80
    db 0x07,0xff,0xff,0xf8,0x00,0x00,0x7f,0xff,0xf8,0x00
    db 0x00,0x00,0x3c,0x00,0x00,0x00,0x00,0x3c,0x00,0x00
    db 0x00,0x03,0xfc,0x00,0x00,0x00,0x3f,0xff,0xc0,0x00
    db 0x03,0xff,0xff,0xff,0xfc,0x03,0xff,0xff,0xff,0xc0
    db 0x03,0xff,0xff,0xfc,0x00,0x00,0x3f,0xff,0xfc,0x00
    db 0x00,0x00,0x1e,0x00,0x00,0x00,0x00,0x1e,0x00,0x00
    db 0x00,0x01,0xfe,0x00,0x00,0x00,0x1f,0xff,0xe0,0x00
    db 0x01,0xff,0xff,0xff,0xfe,0x01,0xff,0xff,0xff,0xe0
    db 0x01,0xff,0xff,0xfe,0x00,0x00,0x1f,0xff,0xfe,0x00

; The patrol ship uses this horizontally reflected cache while moving left.
; It has the same 8 shifts x 8 rows x 5 bytes layout as the right-facing data,
; so direction changes add only a table selection and no per-frame mirroring.
ship_left_wide_shift_table:
    dw ship_left_wide_shift_data,ship_left_wide_shift_data+40
    dw ship_left_wide_shift_data+80,ship_left_wide_shift_data+120
    dw ship_left_wide_shift_data+160,ship_left_wide_shift_data+200
    dw ship_left_wide_shift_data+240,ship_left_wide_shift_data+280
ship_left_wide_shift_data:
    db 0x00,0x00,0xf0,0x00,0x00,0x00,0x00,0xf0,0x00,0x00
    db 0x00,0x00,0xff,0x00,0x00,0x00,0x0f,0xff,0xf0,0x00
    db 0xff,0xff,0xff,0xff,0x00,0x0f,0xff,0xff,0xff,0x00
    db 0x00,0xff,0xff,0xff,0x00,0x00,0xff,0xff,0xf0,0x00
    db 0x00,0x00,0x78,0x00,0x00,0x00,0x00,0x78,0x00,0x00
    db 0x00,0x00,0x7f,0x80,0x00,0x00,0x07,0xff,0xf8,0x00
    db 0x7f,0xff,0xff,0xff,0x80,0x07,0xff,0xff,0xff,0x80
    db 0x00,0x7f,0xff,0xff,0x80,0x00,0x7f,0xff,0xf8,0x00
    db 0x00,0x00,0x3c,0x00,0x00,0x00,0x00,0x3c,0x00,0x00
    db 0x00,0x00,0x3f,0xc0,0x00,0x00,0x03,0xff,0xfc,0x00
    db 0x3f,0xff,0xff,0xff,0xc0,0x03,0xff,0xff,0xff,0xc0
    db 0x00,0x3f,0xff,0xff,0xc0,0x00,0x3f,0xff,0xfc,0x00
    db 0x00,0x00,0x1e,0x00,0x00,0x00,0x00,0x1e,0x00,0x00
    db 0x00,0x00,0x1f,0xe0,0x00,0x00,0x01,0xff,0xfe,0x00
    db 0x1f,0xff,0xff,0xff,0xe0,0x01,0xff,0xff,0xff,0xe0
    db 0x00,0x1f,0xff,0xff,0xe0,0x00,0x1f,0xff,0xfe,0x00
    db 0x00,0x00,0x0f,0x00,0x00,0x00,0x00,0x0f,0x00,0x00
    db 0x00,0x00,0x0f,0xf0,0x00,0x00,0x00,0xff,0xff,0x00
    db 0x0f,0xff,0xff,0xff,0xf0,0x00,0xff,0xff,0xff,0xf0
    db 0x00,0x0f,0xff,0xff,0xf0,0x00,0x0f,0xff,0xff,0x00
    db 0x00,0x00,0x07,0x80,0x00,0x00,0x00,0x07,0x80,0x00
    db 0x00,0x00,0x07,0xf8,0x00,0x00,0x00,0x7f,0xff,0x80
    db 0x07,0xff,0xff,0xff,0xf8,0x00,0x7f,0xff,0xff,0xf8
    db 0x00,0x07,0xff,0xff,0xf8,0x00,0x07,0xff,0xff,0x80
    db 0x00,0x00,0x03,0xc0,0x00,0x00,0x00,0x03,0xc0,0x00
    db 0x00,0x00,0x03,0xfc,0x00,0x00,0x00,0x3f,0xff,0xc0
    db 0x03,0xff,0xff,0xff,0xfc,0x00,0x3f,0xff,0xff,0xfc
    db 0x00,0x03,0xff,0xff,0xfc,0x00,0x03,0xff,0xff,0xc0
    db 0x00,0x00,0x01,0xe0,0x00,0x00,0x00,0x01,0xe0,0x00
    db 0x00,0x00,0x01,0xfe,0x00,0x00,0x00,0x1f,0xff,0xe0
    db 0x01,0xff,0xff,0xff,0xfe,0x00,0x1f,0xff,0xff,0xfe
    db 0x00,0x01,0xff,0xff,0xfe,0x00,0x01,0xff,0xff,0xe0

align 256
screen_line_table:
    dw 0x4000,0x4100,0x4200,0x4300,0x4400,0x4500,0x4600,0x4700
    dw 0x4020,0x4120,0x4220,0x4320,0x4420,0x4520,0x4620,0x4720
    dw 0x4040,0x4140,0x4240,0x4340,0x4440,0x4540,0x4640,0x4740
    dw 0x4060,0x4160,0x4260,0x4360,0x4460,0x4560,0x4660,0x4760
    dw 0x4080,0x4180,0x4280,0x4380,0x4480,0x4580,0x4680,0x4780
    dw 0x40a0,0x41a0,0x42a0,0x43a0,0x44a0,0x45a0,0x46a0,0x47a0
    dw 0x40c0,0x41c0,0x42c0,0x43c0,0x44c0,0x45c0,0x46c0,0x47c0
    dw 0x40e0,0x41e0,0x42e0,0x43e0,0x44e0,0x45e0,0x46e0,0x47e0
    dw 0x4800,0x4900,0x4a00,0x4b00,0x4c00,0x4d00,0x4e00,0x4f00
    dw 0x4820,0x4920,0x4a20,0x4b20,0x4c20,0x4d20,0x4e20,0x4f20
    dw 0x4840,0x4940,0x4a40,0x4b40,0x4c40,0x4d40,0x4e40,0x4f40
    dw 0x4860,0x4960,0x4a60,0x4b60,0x4c60,0x4d60,0x4e60,0x4f60
    dw 0x4880,0x4980,0x4a80,0x4b80,0x4c80,0x4d80,0x4e80,0x4f80
    dw 0x48a0,0x49a0,0x4aa0,0x4ba0,0x4ca0,0x4da0,0x4ea0,0x4fa0
    dw 0x48c0,0x49c0,0x4ac0,0x4bc0,0x4cc0,0x4dc0,0x4ec0,0x4fc0
    dw 0x48e0,0x49e0,0x4ae0,0x4be0,0x4ce0,0x4de0,0x4ee0,0x4fe0
    dw 0x5000,0x5100,0x5200,0x5300,0x5400,0x5500,0x5600,0x5700
    dw 0x5020,0x5120,0x5220,0x5320,0x5420,0x5520,0x5620,0x5720
    dw 0x5040,0x5140,0x5240,0x5340,0x5440,0x5540,0x5640,0x5740
    dw 0x5060,0x5160,0x5260,0x5360,0x5460,0x5560,0x5660,0x5760
    dw 0x5080,0x5180,0x5280,0x5380,0x5480,0x5580,0x5680,0x5780
    dw 0x50a0,0x51a0,0x52a0,0x53a0,0x54a0,0x55a0,0x56a0,0x57a0
    dw 0x50c0,0x51c0,0x52c0,0x53c0,0x54c0,0x55c0,0x56c0,0x57c0
    dw 0x50e0,0x51e0,0x52e0,0x53e0,0x54e0,0x55e0,0x56e0,0x57e0


; ---------------------------------------------------------------------------
; State
; ---------------------------------------------------------------------------

; Scroll/generator state. The six 256-byte arrays below contain only 32 live
; entries, but page alignment lets a block index be installed directly in L.
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
bridge_tank_mode: db 0            ; 1=cross, 2=wait/fire, 3/4=pending
bridge_tank_next_mode: db 0       ; alternates crossing and waiting bridges
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
bridge_center_attr: db 0x0a       ; brown intact span or normal broken water
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
sprite_transition_old_col: db 0  ; resident-sprite top/side delta scratch
sprite_transition_old_width: db 0

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
player_core_left: db 0
player_core_right: db 0
player_core_y: db 0
player_core_rows: db 0
world_write_y: db 0
world_write_col: db 0
world_write_rows: db 0
world_write_spill: db 0
world_write_byte_0: db 0
world_write_byte_1: db 0
world_write_byte_2: db 0
world_source_ptr: dw 0

; Timex renderer scratch. These flags let the terrain-crossing and uniform-
; background groups be removed at different points without changing gameplay
; state observed by movement, collision or spawning code.
timex_saved_ship0_active: db 0
timex_saved_ship1_active: db 0
timex_saved_balloon_active: db 0
timex_saved_fuel_active: db 0
timex_saved_helicopter_active: db 0
timex_saved_tank_active: db 0
timex_bitmap_ship0_active: db 0
timex_bitmap_ship0_x: db 0
timex_bitmap_ship0_y: db 0
timex_bitmap_ship1_active: db 0
timex_bitmap_ship1_x: db 0
timex_bitmap_ship1_y: db 0
timex_deferred_cleared: db 0
timex_deferred_drawn: db 0
timex_ships_cleared: db 0
timex_ships_drawn: db 0
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
object_collision_width: db 16    ; temporarily 32 while testing either ship
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
