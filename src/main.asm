; Attribute Raid renderer V3 for ZX Spectrum 48K and Timex Hi-Color.
;
; The river is deliberately chunky like the Atari 2600 original: one course
; block is eight world scanlines high. This local experiment keeps that cadence
; but lets either bank move in one-pixel steps for an Atari 8-bit-like contour.
; Scrolling is still pixel-smooth.  Instead of repainting all 192 scanlines,
; each frame updates only the rows which cross a block boundary (alternating
; between zero and 19 rows with the slow modifier, 19 at base speed, and 38
; at fast speed). A fork is an optional
; land interval inside the river and is handled by the same dirty-row pass.
;
; Bitmap convention: 1 = green land/object, 0 = blue water/object cut-out.
; Normal attributes stay fixed; only the bridge's brown cells are updated.
;
; Vertical screen contract:
;   Y=0..15    immutable black upper margin
;   Y=16..167  scrolling playfield and all live actors
;   Y=168..175 immutable black separator
;   Y=176..183 LIVES/FUEL/SCORE status line
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
    call paint_ship_attributes
    call draw_all_current_sprites_direct
    call show_ready_screen
    ei

main_loop:
    ; HALT is the only frame synchronisation point. The ROM interrupt wakes us
    ; once per 50 Hz display frame on every supported Spectrum/Timex model.
#if PROFILE_BORDER
    xor a
    out (0xfe),a
#endif
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
#if PROFILE_BORDER
    call profile_begin
#endif
    call read_keyboard
    call update_ay_sound

    ld a,(paused)
    or a
    jr z,main_frame_active
#if PROFILE_BORDER
    call profile_end
#endif
    jr main_loop

main_frame_active:
    call restore_frame_entities

    ld a,(speed_pixels)
    or a
    jr z,course_not_scrolled
    cp 2
    jr z,advance_frame_two_samples
    call advance_course_sample
    jr frame_samples_ready
advance_frame_two_samples:
    call advance_course_sample
    call advance_course_sample
frame_samples_ready:

    call render_dirty_rows
course_not_scrolled:
    ; Both builds keep their bitmap sprites resident. update_entities first
    ; advances the world/bridge layer and then replaces only the exposed edges
    ; plus the new final sprite bytes; there is no visible erase/redraw phase.
    call update_entities
    call update_hud_if_dirty
    ld a,(crashed)
    or a
    jr z,draw_updated_entities
    call begin_crash
    call update_hud_if_dirty
    call draw_crash_frame_entities
#if PROFILE_BORDER
    call profile_end
#endif
    jr main_loop
draw_updated_entities:
    call draw_frame_entities
#if PROFILE_BORDER
    call profile_end
#endif
    jp main_loop

restore_frame_entities:
    ; Bitmap sprites stay resident. Save the state which produced the current
    ; image, then remove only the deliberately XOR-composed impact effect.
    call snapshot_resident_sprite_state
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
    call paint_ship_attributes
    jp cleanup_timex_saved_object_attributes
#else
    jp update_standard_object_attributes
#endif

#macro STANDARD_ATTR_CHANGED active,old_active,x,old_x,y,old_y,right,bottom,y_mask,handler
    ld a,({old_active})
    ld b,a
    ld a,({active})
    cp b
    jr z,%%active_unchanged
    call {handler}
    jr %%done
%%active_unchanged:
    or a
    jr z,%%done
    ld a,({old_x})
    and 0xf8
    ld b,a
    ld a,({x})
    and 0xf8
    cp b
    jr z,%%left_unchanged
    call {handler}
    jr %%done
%%left_unchanged:
    ld a,({old_x})
    add a,{right}
    and 0xf8
    ld b,a
    ld a,({x})
    add a,{right}
    and 0xf8
    cp b
    jr z,%%right_unchanged
    call {handler}
    jr %%done
%%right_unchanged:
    ld a,({old_y})
    and {y_mask}
    ld b,a
    ld a,({y})
    and {y_mask}
    cp b
    jr z,%%top_unchanged
    call {handler}
    jr %%done
%%top_unchanged:
    ld a,({old_y})
    add a,{bottom}
    and 0xf8
    ld b,a
    ld a,({y})
    add a,{bottom}
    and 0xf8
    cp b
    jr z,%%done
    call {handler}
%%done:
#endmacro

#if not TIMEX_HICOLOR
update_standard_object_attributes:
    ; Attributes need work only when a saved/current footprint differs. The
    ; top Y comparison uses four-pixel bands so FUEL and balloon colour choices
    ; still change near their mid-cell thresholds without a per-frame repaint.
    @STANDARD_ATTR_CHANGED helicopter_active,timex_attr_helicopter_active,helicopter_x,timex_attr_helicopter_x,helicopter_y,timex_attr_helicopter_y,15,9,0xf8,standard_helicopter_attributes_dirty
    @STANDARD_ATTR_CHANGED fuel_active,timex_attr_fuel_active,fuel_x,timex_attr_fuel_x,fuel_y,timex_attr_fuel_y,7,31,0xfc,standard_fuel_attributes_dirty
    @STANDARD_ATTR_CHANGED balloon_active,timex_attr_balloon_active,balloon_x,timex_attr_balloon_x,balloon_y,timex_attr_balloon_y,15,19,0xfc,standard_balloon_attributes_dirty
    @STANDARD_ATTR_CHANGED tank_active,timex_attr_tank_active,tank_x,timex_attr_tank_x,tank_y,timex_attr_tank_y,15,9,0xf8,standard_tank_attributes_dirty
    ret

standard_helicopter_attributes_dirty:
    call restore_standard_saved_helicopter_attributes
    jp paint_helicopter_attributes

restore_standard_saved_helicopter_attributes:
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
    ret

standard_fuel_attributes_dirty:
    call restore_standard_saved_fuel_attributes
    jp paint_fuel_attributes

restore_standard_saved_fuel_attributes:
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
    ret

standard_balloon_attributes_dirty:
    call restore_standard_saved_balloon_attributes
    jp paint_balloon_attributes

restore_standard_saved_balloon_attributes:
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
    ret

standard_tank_attributes_dirty:
    call restore_standard_saved_tank_attributes
    jp paint_tank_attributes

restore_standard_saved_tank_attributes:
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
    call paint_ship_attributes
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
    ld hl,hud_text
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
    ld d,176
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
    ld d,176
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
    ld d,176
    ld e,13
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
#if TIMEX_HICOLOR
    jp prepare_timex_helicopter_attributes
#else
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
#endif

#if TIMEX_HICOLOR
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
    ld a,(timex_attr_helicopter_active)
    or a
    jp z,timex_paint_object_rows   ; first frame must create the whole colour

    ; White is uniform through the ten scanlines. During ordinary scrolling
    ; the overlap already has the right value, so colour only the new bottom
    ; strip. A discontinuous move is rare and deliberately falls back to the
    ; full rectangle.
    ld a,(timex_attr_helicopter_y)
    ld b,a
    ld a,(helicopter_y)
    sub b
    jr c,timex_paint_helicopter_full
    cp 3
    jr nc,timex_paint_helicopter_full
    or a
    jr z,timex_paint_helicopter_horizontal
    ld (object_attr_rows),a
    ld b,a
    ld a,(helicopter_y)
    add a,10
    sub b
    ld (object_attr_y),a
    call timex_paint_object_rows

timex_paint_helicopter_horizontal:
    ; A one-pixel patrol exposes a complete attribute column only on the two
    ; byte-boundary cases. All other horizontal movement stays inside the
    ; already-white footprint.
    ld a,(timex_attr_helicopter_x)
    ld b,a
    ld a,(helicopter_x)
    cp b
    ret z
    jr c,timex_paint_helicopter_new_left
    and 7
    cp 1
    ret nz
    ld a,(helicopter_x)
    srl a
    srl a
    srl a
    add a,2                         ; newly exposed rightmost byte column
    jr timex_paint_helicopter_side
timex_paint_helicopter_new_left:
    and 7
    cp 7
    ret nz
    ld a,(helicopter_x)
    srl a
    srl a
    srl a                           ; newly exposed leftmost byte column
timex_paint_helicopter_side:
    ld (object_attr_col),a
    ld a,1
    ld (object_attr_width),a
    ld a,(helicopter_y)
    ld (object_attr_y),a
    ld a,10
    ld (object_attr_rows),a
    jp timex_paint_object_rows
timex_paint_helicopter_full:
    ld a,(helicopter_y)
    ld (object_attr_y),a
    ld a,10
    ld (object_attr_rows),a
    jp timex_paint_object_rows
#endif

paint_ship_attributes:
    ; The two wide ships copy the Atari hull's per-scanline colours, which
    ; only the Timex 8x1 attribute file can follow. Standard 8x8 cells were
    ; tried and rejected: the cell-boundary split flickers and reads mostly
    ; red, so that build leaves the river attribute alone and the hulls keep
    ; their single-ink look.
#if TIMEX_HICOLOR
    call paint_timex_ship0_attributes
    jp paint_timex_ship1_attributes
#else
    ret
#endif

paint_fuel_attributes:
    ld a,(fuel_active)
    or a
    ret z
#if TIMEX_HICOLOR
    jp paint_timex_fuel_attributes
#else
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
#endif

restore_fuel_attributes:
    ld a,(fuel_active)
    or a
    ret z
#if TIMEX_HICOLOR
    jp restore_timex_fuel_attributes
#else
    call prepare_fuel_attribute_geometry
    ld a,0x4c                       ; ordinary green land / blue water cells
    ld (object_attr_value),a
    ld a,(fuel_attr_rows_remaining)
    ld (object_attr_rows),a
    jp paint_object_attribute_cells
#endif

paint_balloon_attributes:
    ; The Atari balloon is striped by scanline. Standard Spectrum attributes
    ; approximate the canopy with yellow/cyan cells and the lower envelope/
    ; basket with magenta, always retaining the same blue PAPER as the river.
    ld a,(balloon_active)
    or a
    ret z
#if TIMEX_HICOLOR
    jp paint_timex_balloon_attributes
#else
    call prepare_balloon_attribute_geometry
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
    ld de,32

paint_balloon_attribute_row:
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
    dec l
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
    jr paint_balloon_attribute_row
#endif

restore_balloon_attributes:
    ld a,(balloon_active)
    or a
    ret z
#if TIMEX_HICOLOR
    jp restore_timex_balloon_attributes
#else
    call prepare_balloon_attribute_geometry
    ld a,0x4c                       ; ordinary green land / blue water cells
    ld (object_attr_value),a
    jp paint_object_attribute_cells
#endif

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
    ; The shore tank is stored as the inverse of its mask over set land pixels,
    ; so its silhouette consists of zero bits. Give those cut-outs black PAPER
    ; instead of ordinary blue, or it looks like corruption in the bank.
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
#if TIMEX_HICOLOR
    jp prepare_timex_tank_attributes
#else
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
#endif

#if TIMEX_HICOLOR
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
    ld a,(timex_attr_tank_active)
    or a
    jp z,timex_paint_object_rows

    ; The shore tank remains in one bitmap-byte column. Its black-paper
    ; silhouette is uniform vertically, so ordinary scroll frames need only
    ; the one/two newly entering bottom rows.
    ld a,(timex_attr_tank_x)
    srl a
    srl a
    srl a
    ld b,a
    ld a,(object_attr_col)
    cp b
    jr nz,timex_paint_tank_full
    ld a,(timex_attr_tank_y)
    ld b,a
    ld a,(tank_y)
    sub b
    ret z
    jr c,timex_paint_tank_full
    cp 3
    jr nc,timex_paint_tank_full
    ld (object_attr_rows),a
    ld b,a
    ld a,(tank_y)
    add a,10
    sub b
    ld (object_attr_y),a
    jp timex_paint_object_rows
timex_paint_tank_full:
    ld a,(tank_y)
    ld (object_attr_y),a
    ld a,10
    ld (object_attr_rows),a
    jp timex_paint_object_rows
#endif

tank_attributes_overlap_road:
    ; Road attributes already use green PAPER. Leave them under a shore tank
    ; so its cut-out stays green and, most importantly, never restore a road
    ; cell to the river palette.
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
#if TIMEX_HICOLOR
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
#else
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
#endif

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

#if TIMEX_HICOLOR
#include "render_timex.asm"
#endif


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

#include "sprite_cache.asm"


#include "course_renderer.asm"


#include "sprite_renderer.asm"


#include "entities.asm"


; ---------------------------------------------------------------------------
; Crash, lives and game-over state
; ---------------------------------------------------------------------------

begin_crash:
    ld a,1
    ld (game_state),a
    call silence_ay
    call start_ay_crash
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
    ; five-frame animation boundary; the AY burst and crackle still advance
    ; every frame independently of bitmap work.
    call update_ay_sound
#if PROFILE_BORDER
    call profile_begin
#endif

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
#if PROFILE_BORDER
    call profile_end
#endif
    jp main_loop

crash_wait_finished:
#if PROFILE_BORDER
    call profile_end
#endif
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
#if TIMEX_HICOLOR
    ld hl,0x6000
    ld (hl),0x47
    ld de,0x6001
    ld bc,6143
    ldir
#else
    ld hl,0x5800
    ld (hl),0x47
    ld de,0x5801
    ld bc,767
    ldir
#endif
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
#if AUTOPILOT
    ; Benchmark build: skip both waiting screens and start flying immediately.
    call start_new_game
    jp main_loop
#endif
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


#include "sound_ay.asm"
#include "input.asm"


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

fork_left_offsets:
    db 0,255,255,254,254,254,254,255,255,0
fork_widths:
    db 1,2,3,4,4,4,4,3,2,1

#include "sound_ay_data.asm"

#include "sprite_data.asm"

#include "screen_tables.asm"


#include "state.asm"
