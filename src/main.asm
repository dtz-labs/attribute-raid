; Attribute Raid renderer V3 for ZX Spectrum 48K.
;
; The river is deliberately chunky like the Atari 2600 original: one course
; block is eight world scanlines high and both banks move in four-pixel steps.
; Scrolling is still pixel-smooth.  Instead of repainting all 192 scanlines,
; each frame updates only the rows which cross a block boundary (alternating
; between zero and 24 rows with the slow modifier, 24 at base speed, and 48
; at fast speed).  A fork is an optional land interval inside the river and
; is handled by the same dirty-row pass.
;
; Bitmap convention: 1 = green land/object, 0 = blue water/object cut-out.
; Normal attributes stay fixed; only the bridge's brown cells are updated.
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
    ld a,2
    ld (lives),a
    xor a
    ld (game_state),a
    call paint_life_attributes
    call paint_helicopter_attributes
    call draw_entities
    ei

main_loop:
    xor a
    out (0xfe),a
    halt

    ld a,(game_state)
    cp 1
    jp z,crash_wait_frame
    cp 2
    jp z,game_over_frame

    call read_keyboard

    ld a,(paused)
    or a
    jr nz,main_loop

    call profile_begin

    ; XOR removes the old sprites exactly. The broad bridge stays resident;
    ; update_bridge later changes only the rows entering/leaving its envelope.
    call restore_entities
    call restore_helicopter_attributes

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
    call update_entities
    ld a,(crashed)
    or a
    jr z,draw_updated_entities
    call begin_crash
    call paint_life_attributes
    call paint_helicopter_attributes
    call paint_crash_attributes
    call draw_entities
    call profile_end
    jr main_loop
draw_updated_entities:
    call paint_helicopter_attributes
    call draw_entities
    call profile_end
    jr main_loop


; ---------------------------------------------------------------------------
; Initialization
; ---------------------------------------------------------------------------

init_attributes:
    ; BRIGHT 1, PAPER blue, INK green.
    ld hl,0x5800
    ld (hl),0x4c
    ld de,0x5801
    ld bc,767
    ldir
    ret

reinitialize_demo:
    call init_attributes
    call init_course
    call full_redraw
    call init_entities
    xor a
    ld (game_state),a
    call paint_life_attributes
    call paint_helicopter_attributes
    call draw_entities
    ret

start_new_game:
    ld a,2
    ld (lives),a
    jp reinitialize_demo

paint_life_attributes:
    ; Two small HUD cells live permanently in the solid upper-left bank.
    ; A remaining life is a black plane cut out of a white 8x8 cell.
    ld hl,0x5800
    ld a,(lives)
    or a
    jr z,no_life_attributes
    ld (hl),0x47
    inc hl
    dec a
    jr z,one_life_attribute
    ld (hl),0x47
    ret
one_life_attribute:
    ld (hl),0x4c
    ret
no_life_attributes:
    ld (hl),0x4c
    inc hl
    ld (hl),0x4c
    ret

paint_helicopter_attributes:
    ; The Atari sprite changes colour by scanline. Spectrum attributes cannot
    ; follow a freely moving 10-pixel object that closely, so use a crisp white
    ; INK on the existing blue PAPER without introducing an opaque rectangle.
    ld a,0x4f
    jr prepare_helicopter_attributes

restore_helicopter_attributes:
    ; Water objects are kept away from the brown bridge, so the normal river
    ; attribute is always the correct value underneath the old helicopter.
    ld a,0x4c
prepare_helicopter_attributes:
    ld (object_attr_value),a
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

paint_crash_attributes:
    ; A yellow 24x24 attribute envelope makes the small XOR explosion read as
    ; fire. It need not be restored: the next life redraws the whole course.
    ld a,0x4e
    ld (object_attr_value),a
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
paint_object_attribute_row:
    ld a,(object_attr_row)
    cp 24
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
    jr nz,paint_object_attribute_row
    ret


; ---------------------------------------------------------------------------
; One-time sprite shift cache
; ---------------------------------------------------------------------------
;
; Rotating every sprite row at runtime made the cost depend heavily on X & 7:
; a frame where several objects happened to sit at shift seven could miss the
; 50 Hz budget.  Build all eight three-byte variants once at startup instead.

init_shifted_sprites:
    ld hl,player_jet_sprite
    ld de,player_shift_data
    ld b,13
    call build_shifted_sprite
    ld hl,bullet_sprite
    ld de,bullet_shift_data
    ld b,4
    call build_shifted_sprite
    ld hl,atari_ship_sprite
    ld de,ship_shift_data
    ld b,8
    call build_shifted_sprite
    ld hl,enemy_plane_sprite
    ld de,enemy_plane_shift_data
    ld b,8
    call build_shifted_sprite
    ld hl,atari_helicopter_sprite
    ld de,helicopter_shift_data
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
    ld a,32
    ld (gen_center_q),a
    ld a,19
    ld (gen_half_q),a
    xor a
    ld (center_step),a
    ld (half_step),a
    ld (motion_timer),a
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

    ld a,(gen_center_q)
    ld b,a
    ld a,(center_step)
    add a,b
    cp 25
    jr nc,center_q_not_low
    ld a,25
    ld b,1
    ld a,b
    ld (center_step),a
    ld a,25
    jr center_q_ready
center_q_not_low:
    cp 40
    jr c,center_q_ready
    ld a,39
    ld b,255
    ld a,b
    ld (center_step),a
    ld a,39
center_q_ready:
    ld (gen_center_q),a

    ld a,(gen_half_q)
    ld b,a
    ld a,(half_step)
    add a,b
    cp 17
    jr nc,half_q_not_low
    ld a,17
    ld (gen_half_q),a
    ld a,1
    ld (half_step),a
    jr half_q_ready
half_q_not_low:
    cp 22
    jr c,store_half_q
    ld a,21
    ld (gen_half_q),a
    ld a,255
    ld (half_step),a
    jr half_q_ready
store_half_q:
    ld (gen_half_q),a
half_q_ready:

    call update_course_feature

    ; Convert four-pixel units to byte columns and one of two edge masks.
    ld a,(course_block_head)
    ld e,a
    ld a,(gen_center_q)
    ld b,a
    ld a,(gen_half_q)
    ld c,a

    ld a,b
    sub c
    ld d,a
    srl a
    ld h,HIGH(block_left_col)
    ld l,e
    ld (hl),a
    ld a,d
    and 1
    jr z,generated_left_on_byte
    ld a,0xf0
    jr store_generated_left_mask
generated_left_on_byte:
    xor a
store_generated_left_mask:
    ld h,HIGH(block_left_mask)
    ld l,e
    ld (hl),a

    ld a,b
    add a,c
    ld d,a
    srl a
    ld h,HIGH(block_right_col)
    ld l,e
    ld (hl),a
    ld a,d
    and 1
    jr z,generated_right_on_byte
    ld a,0x0f
    jr store_generated_right_mask
generated_right_on_byte:
    ld a,255
store_generated_right_mask:
    ld h,HIGH(block_right_mask)
    ld l,e
    ld (hl),a

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
    ; Atari-style course runs: one descriptor normally remains active for
    ; 5..12 blocks (40..96 scanlines), so long straights and diagonals are
    ; much more common than nervous, constantly changing banks.
    and 7
    add a,4
    ld (motion_timer),a
    ld a,b
    and 15
    add a,a
    ld e,a
    ld d,0
    ld hl,block_motion_table
    add hl,de
    ld a,(hl)
    ld (center_step),a
    inc hl
    ld a,(hl)
    ld (half_step),a
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
    ld a,1
    ld (next_feature),a
    ld (fork_step),a
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
    ld a,(gen_center_q)
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
; Full redraw (startup and R only)
; ---------------------------------------------------------------------------

full_redraw:
    ld hl,0x4000
    xor a
    ld (hl),a
    ld de,0x4001
    ld bc,6143
    ldir

    xor a
    ld (redraw_y),a
full_redraw_row:
    ld a,(redraw_y)
    call calc_screen_line_addr
    ld (row_screen_addr),hl
    ld a,(redraw_y)
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
    call draw_current_island_full
    ld a,(redraw_y)
    inc a
    ld (redraw_y),a
    cp 192
    jr nz,full_redraw_row
    ret

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
; The matching residues are enumerated directly.  No 192-line scan is needed.

render_dirty_rows:
    ld a,(course_phase)
    ld (dirty_first_y),a
    ld a,(speed_pixels)
    ld (dirty_residues),a
dirty_residue_loop:
    ld a,(dirty_first_y)
    ld (dirty_y),a
dirty_row_loop:
    call render_v3_row
    ld a,(dirty_y)
    add a,8
    cp 192
    jr nc,dirty_next_residue
    ld (dirty_y),a
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
    ld a,(dirty_y)
    call calc_screen_line_addr
    ld (row_screen_addr),hl
    ld a,(dirty_y)
    call get_block_index_for_y
    ld a,l
    ld (row_block_index),a

    ; Left bank: land, partial edge, water.
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
; X.  The tables below preserve that 2:1 pixel shape as 16-pixel Spectrum
; sprites.  Every moving object is erased before the river update and redrawn
; afterwards.  The player is also included so future collision/steering work
; can safely alter the background under it.

init_entities:
    ld a,170
    ld (player_y),a
    call calc_safe_river_x
    ld (player_x),a

    ld a,24
    ld (ship0_y),a
    call calc_safe_river_x
    ld (ship0_x),a

    ld a,92
    ld (ship1_y),a
    call calc_safe_river_x
    ld (ship1_x),a
    ld a,1
    ld (ship1_dir),a
    ld a,2
    ld (ship1_timer),a

    ld a,56
    ld (enemy_plane_y),a
    xor a
    ld (enemy_plane_x),a

    ld a,126
    ld (helicopter_y),a
    call calc_safe_river_x
    ld (helicopter_x),a
    ld a,1
    ld (helicopter_move),a
    ld (helicopter_dir),a

    ld a,46
    ld (tank_y),a
    xor a
    ld (tank_side),a
    ld a,1
    ld (tank_active),a
    ld a,(tank_y)
    call calc_tank_col
    ld (tank_col),a
    xor a
    ld (tank_delay),a
    ld (bridge_active),a
    ld (player_move),a
    ld (bullet_active),a
    ld (fire_pending),a
    ld (fire_down),a
    ld (crashed),a
    ld (explosion_timer),a
    ld (explosion_anim_timer),a
    ld (explosion_frame),a
    ld (slow_phase),a
    ld (joystick_state),a
    ret

restore_entities:
    jp xor_entities

draw_entities:
xor_entities:
    ld a,(game_state)
    cp 1
    jr z,xor_entities_explosion
    or a
    jr nz,xor_entities_bullet
    ld a,(player_x)
    ld c,a
    ld a,(player_y)
    ld b,13
    ld de,player_shift_table
    call xor_sprite_shifted_2xn
    jr xor_entities_bullet

xor_entities_explosion:
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
    call xor_sprite_shifted_2xn

xor_entities_bullet:
    ld a,(bullet_active)
    or a
    jr z,xor_entities_ship0
    ld a,(bullet_x)
    ld c,a
    ld a,(bullet_y)
    ld b,4
    ld de,bullet_shift_table
    call xor_sprite_shifted_2xn

xor_entities_ship0:
    ld a,(ship0_x)
    ld c,a
    ld a,(ship0_y)
    ld b,8
    ld de,ship_shift_table
    call xor_sprite_shifted_2xn

    ld a,(ship1_x)
    ld c,a
    ld a,(ship1_y)
    ld b,8
    ld de,ship_shift_table
    call xor_sprite_shifted_2xn

    ld a,(enemy_plane_x)
    ld c,a
    ld a,(enemy_plane_y)
    ld b,8
    ld de,enemy_plane_shift_table
    call xor_sprite_shifted_2xn

    ld a,(helicopter_x)
    ld c,a
    ld a,(helicopter_y)
    ld b,10
    ld de,helicopter_shift_table
    call xor_sprite_shifted_2xn

    ld a,(tank_active)
    or a
    jr z,xor_life_icons
    ld a,(tank_col)
    ld c,a
    ld a,(tank_y)
    ld b,10
    ld de,atari_tank_sprite
    call xor_sprite_2xn

xor_life_icons:
    ld a,(lives)
    or a
    ret z
    ld de,life_icon_one_sprite
    cp 2
    jr c,xor_life_icon_table_ready
    ld de,life_icon_two_sprite
xor_life_icon_table_ready:
    ld c,0
    ld a,1
    ld b,7
    jp xor_sprite_2xn

xor_sprite_2xn:
    ; Input A=Y, C=byte column, B=height, DE=two-byte-per-row pattern.
    cp 192
    ret nc
    ld l,a
    ld a,192
    sub l
    ld h,a
    ld a,b
    cp h
    jr c,sprite_rows_ready
    jr z,sprite_rows_ready
    ld b,h
sprite_rows_ready:
    ld a,l
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,sprite_table_page_ready
    inc h
sprite_table_page_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
xor_sprite_row:
    pop hl
    ld a,l
    add a,c
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
    djnz xor_sprite_row
    ld sp,(sprite_saved_sp)
    ei
    ret

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

bridge_fill_rows:
    ; Input A=start Y, B=row count, C=byte value. The bridge is maintained as
    ; a persistent bitmap band: only rows entering or leaving its 16-line
    ; envelope are touched during scrolling.
    cp 192
    ret nc
    ld l,a
    ld a,192
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
    ; The bank renderer may rewrite the two bytes at either end of a bridge.
    ; Refresh only those four bytes, leaving its broad interior untouched.
    cp 192
    ret nc
    ld l,a
    ld a,192
    sub l
    cp 16
    jr c,bridge_refresh_count_ready
    ld a,16
bridge_refresh_count_ready:
    ld (bridge_rows_left),a
    ld a,l
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,bridge_refresh_table_ready
    inc h
bridge_refresh_table_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
bridge_refresh_row:
    pop hl
    ld a,l
    ld c,a
    ld a,(bridge_col)
    add a,c
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
    ld a,(bridge_rows_left)
    dec a
    ld (bridge_rows_left),a
    jr nz,bridge_refresh_row
    ld sp,(sprite_saved_sp)
    ei
    ret

bridge_paint_attributes:
    ; Input C=attribute value. A 16-line bridge covers two attribute rows when
    ; aligned and three while between cells. Stock Spectrum colour therefore
    ; advances in 8-line steps even though the bitmap itself moves every pixel.
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
    cp 24
    ret nc
    ld b,a
    and 7
    rrca
    rrca
    rrca
    ld l,a
    ld a,(bridge_col)
    add a,l
    ld l,a
    ld a,b
    srl a
    srl a
    srl a
    add a,0x58
    ld h,a
    ld a,(bridge_width)
    ld b,a
    ld a,c
bridge_attr_byte:
    ld (hl),a
    inc hl
    djnz bridge_attr_byte
    ld a,(bridge_attr_row)
    inc a
    ld (bridge_attr_row),a
    ld a,(bridge_attr_rows)
    dec a
    ld (bridge_attr_rows),a
    jr nz,bridge_attr_row_loop
    ret

bridge_paint_attribute_row:
    ; Input A=attribute row (0..23), C=value.  Used by the moving bridge to
    ; update only the one 8-pixel colour strip entering or leaving its range.
    cp 24
    ret nc
    ld b,a
    and 7
    rrca
    rrca
    rrca
    ld l,a
    ld a,(bridge_col)
    add a,l
    ld l,a
    ld a,b
    srl a
    srl a
    srl a
    add a,0x58
    ld h,a
    ld a,(bridge_width)
    ld b,a
    ld a,c
bridge_one_attr_byte:
    ld (hl),a
    inc hl
    djnz bridge_one_attr_byte
    ret

bridge_update_attributes:
    ; The bitmap bridge moves every pixel, but its set of 8x8 colour cells
    ; normally does not.  Compare the old and new inclusive attribute spans:
    ; at most one row leaves at the top and one arrives at the bottom.
    ; bridge_restore_y is scratch for reconstructing the departing bitmap
    ; rows and has already advanced, so recover old Y from new Y - speed.
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
    call bridge_paint_attribute_row
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
    ld c,0x0a
    jp bridge_paint_attribute_row


; ---------------------------------------------------------------------------
; Object movement
; ---------------------------------------------------------------------------

update_entities:
    call update_player
    call advance_ship0
    call advance_ship1
    call advance_enemy_plane
    call advance_helicopter
    call update_tank
    call update_bridge
    call update_bullet
    call keep_water_objects_off_bridge
    call check_player_collision
    ret

update_player:
    ld a,(player_move)
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

advance_ship0:
    ld a,(speed_pixels)
    ld b,a
    ld a,(ship0_y)
    add a,b
    cp 192
    jr c,store_ship0_y
    xor a
    ld (ship0_y),a
    call calc_safe_river_x
    ld (ship0_x),a
    ret
store_ship0_y:
    ld (ship0_y),a
    ret

advance_ship1:
    ld a,(speed_pixels)
    ld b,a
    ld a,(ship1_y)
    add a,b
    cp 192
    jr c,store_ship1_y
    xor a
    ld (ship1_y),a
    call calc_safe_river_x
    ld (ship1_x),a
    jr patrol_ship1
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
    ; started instead of being pinned to the monitor.
    ld a,(speed_pixels)
    ld b,a
    ld a,(enemy_plane_y)
    add a,b
    cp 192
    jr c,store_enemy_plane_y
    xor a
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

advance_helicopter:
    ld a,(speed_pixels)
    ld b,a
    ld a,(helicopter_y)
    add a,b
    cp 192
    jr c,store_helicopter_y
    xor a
    ld (helicopter_y),a
    call calc_safe_river_x
    ld (helicopter_x),a
    ld a,(helicopter_move)
    xor 1
    ld (helicopter_move),a
    ld a,1
    ld (helicopter_dir),a
    jr patrol_helicopter
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

update_tank:
    ld a,(tank_active)
    or a
    jr z,wait_for_tank
    ld a,(speed_pixels)
    ld b,a
    ld a,(tank_y)
    add a,b
    cp 192
    jr c,store_tank_y
    xor a
    ld (tank_active),a
    ld a,72
    ld (tank_delay),a
    ret
store_tank_y:
    ld (tank_y),a
    ret
wait_for_tank:
    ld a,(tank_delay)
    or a
    jr z,spawn_tank
    dec a
    ld (tank_delay),a
    ret
spawn_tank:
    ld a,1
    ld (tank_active),a
    xor a
    ld (tank_y),a
    ld a,(tank_side)
    xor 1
    ld (tank_side),a
    xor a
    call calc_tank_col
    ld (tank_col),a
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
    ld a,(bridge_spawn_pending)
    or a
    jr z,advance_active_bridge
    xor a
    ld (bridge_spawn_pending),a
    ld a,1
    ld (bridge_active),a
    xor a
    ld (bridge_y),a
    call get_bounds_for_y
    ld a,d
    ld (bridge_col),a
    ld b,a
    ld a,e
    sub b
    inc a
    ld (bridge_width),a
    ld b,16
    ld c,255
    xor a
    call bridge_fill_rows
    ld c,0x0a
    call bridge_paint_attributes
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
    cp 192
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
    cp 192
    jr c,store_bridge_y
    ; No new bridge span remains on screen, so clear its last colour cells.
    ld c,0x4c
    call bridge_paint_attributes
    xor a
    ld (bridge_active),a
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
    call bridge_update_attributes
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
    cp 6
    jr nc,move_bullet_up
    xor a
    ld (bullet_active),a
    ret
move_bullet_up:
    sub 6
    ld (bullet_y),a

    ; Only the bridge is destructible in this renderer pass.
    ld a,(bridge_active)
    or a
    ret z
    ld a,(bullet_y)
    add a,4
    ld b,a
    ld a,(bridge_y)
    cp b
    ret nc
    add a,16
    ld b,a
    ld a,(bullet_y)
    cp b
    ret nc

    ld a,(bridge_col)
    add a,a
    add a,a
    add a,a
    ld b,a
    ld a,(bullet_x)
    add a,8
    cp b
    ret c
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
    ret nc

    call destroy_bridge
    xor a
    ld (bullet_active),a
    ret

destroy_bridge:
    ld c,0x4c
    call bridge_paint_attributes
    ld a,(bridge_y)
    ld (bridge_restore_y),a
    ld a,16
    ld (bridge_restore_rows),a
    ld b,a
    ld c,0
    ld a,(bridge_y)
    call bridge_fill_rows
destroy_bridge_restore:
    ld a,(bridge_restore_rows)
    or a
    jr z,destroy_bridge_done
    ld a,(bridge_restore_y)
    cp 192
    jr nc,destroy_bridge_done
    ld (dirty_y),a
    call render_v3_row
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
    ret

object_overlaps_bridge:
    ; Input A=object Y, B=height. Return A=1 when vertical intervals overlap.
    ld c,a
    add a,b
    ld d,a
    ld a,(bridge_y)
    cp d
    jr nc,object_misses_bridge
    add a,16
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
    ld a,(ship0_y)
    ld b,8
    call object_overlaps_bridge
    or a
    jr z,check_ship1_bridge
    call relocate_ship0
check_ship1_bridge:
    ld a,(ship1_y)
    ld b,8
    call object_overlaps_bridge
    or a
    jr z,check_helicopter_bridge
    call relocate_ship1
check_helicopter_bridge:
    ld a,(helicopter_y)
    ld b,10
    call object_overlaps_bridge
    or a
    ret z
    call relocate_helicopter
    ret

relocate_ship0:
    ld a,(bridge_y)
    cp 8
    jr c,ship0_below_bridge
    xor a
    jr store_relocated_ship0_y
ship0_below_bridge:
    add a,16
store_relocated_ship0_y:
    ld (ship0_y),a
    call calc_safe_river_x
    ld (ship0_x),a
    ret

relocate_ship1:
    ld a,(bridge_y)
    cp 8
    jr c,ship1_below_bridge
    xor a
    jr store_relocated_ship1_y
ship1_below_bridge:
    add a,16
store_relocated_ship1_y:
    ld (ship1_y),a
    call calc_safe_river_x
    ld (ship1_x),a
    ret

relocate_helicopter:
    ld a,(bridge_y)
    cp 10
    jr c,helicopter_below_bridge
    xor a
    jr store_relocated_helicopter_y
helicopter_below_bridge:
    add a,16
store_relocated_helicopter_y:
    ld (helicopter_y),a
    call calc_safe_river_x
    ld (helicopter_x),a
    ret

check_player_collision:
    ; Test the actual opaque player pixels against the current bitmap. At this
    ; point all XOR sprites have been removed, so set background bits mean
    ; bank, island or an intact bridge and zero bits mean navigable water.
    call check_player_background_pixels
    jr c,player_crashed

    ld a,(ship0_x)
    ld c,a
    ld a,(ship0_y)
    ld b,8
    call player_overlaps_object
    jr c,player_crashed
    ld a,(ship1_x)
    ld c,a
    ld a,(ship1_y)
    ld b,8
    call player_overlaps_object
    jr c,player_crashed
    ld a,(enemy_plane_x)
    ld c,a
    ld a,(enemy_plane_y)
    ld b,8
    call player_overlaps_object
    jr c,player_crashed
    ld a,(helicopter_x)
    ld c,a
    ld a,(helicopter_y)
    ld b,10
    call player_overlaps_object
    jr c,player_crashed
    ld a,(tank_active)
    or a
    ret z
    ld a,(tank_col)
    add a,a
    add a,a
    add a,a
    ld c,a
    ld a,(tank_y)
    ld b,10
    call player_overlaps_object
    ret nc
player_crashed:
    ld a,1
    ld (crashed),a
    ret

check_player_background_pixels:
    ; Return carry when any bit of the shifted 16x13 player mask overlaps a
    ; set background bit. Transparent corners cannot cause an early crash.
    ld a,(player_x)
    ld c,a
    and 7
    add a,a
    ld l,a
    ld h,0
    ld de,player_shift_table
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,c
    srl a
    srl a
    srl a
    ld c,a

    ld a,(player_y)
    add a,a
    ld l,a
    ld h,HIGH(screen_line_table)
    jr nc,player_collision_table_ready
    inc h
player_collision_table_ready:
    di
    ld (sprite_saved_sp),sp
    ld sp,hl
    ld b,13
player_collision_row:
    pop hl
    ld a,c
    add a,l
    ld l,a
    ld a,(de)
    and (hl)
    jr nz,player_background_hit
    inc de
    inc l
    ld a,(de)
    and (hl)
    jr nz,player_background_hit
    inc de
    inc l
    ld a,(de)
    and (hl)
    jr nz,player_background_hit
    inc de
    djnz player_collision_row
    ld sp,(sprite_saved_sp)
    ei
    or a
    ret
player_background_hit:
    ld sp,(sprite_saved_sp)
    ei
    xor a
    cp 1
    ret

player_overlaps_object:
    ; Input A=object Y, B=height, C=object pixel X. Use a forgiving 6x6 core
    ; inside the player silhouette for sprite-to-sprite collisions.
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
    add a,16
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
    ld a,75
    ld (explosion_timer),a
    ld a,5
    ld (explosion_anim_timer),a
    xor a
    ld (explosion_frame),a
    ld (bullet_active),a
    ld (fire_pending),a
    ld a,(lives)
    or a
    ret z
    dec a
    ld (lives),a
    ret

crash_wait_frame:
    ; Freeze the river and all enemies for 75 display frames (1.5 seconds).
    ; Only the three-frame explosion continues to animate.
    call profile_begin
    call restore_entities
    call restore_helicopter_attributes

    ld a,(explosion_timer)
    dec a
    ld (explosion_timer),a
    jr z,crash_wait_finished

    ld a,(explosion_anim_timer)
    dec a
    ld (explosion_anim_timer),a
    jr nz,draw_crash_wait_frame
    ld a,5
    ld (explosion_anim_timer),a
    ld a,(explosion_frame)
    inc a
    cp 3
    jr c,store_explosion_frame
    xor a
store_explosion_frame:
    ld (explosion_frame),a

draw_crash_wait_frame:
    call paint_helicopter_attributes
    call paint_crash_attributes
    call draw_entities
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

show_game_over:
    ; Independent black screen; ROM glyphs are copied directly to the bitmap,
    ; so this works without BASIC channels or system-variable assumptions.
    xor a
    out (0xfe),a
    ld hl,0x4000
    ld (hl),a
    ld de,0x4001
    ld bc,6143
    ldir
    ld hl,0x5800
    ld (hl),0x47
    ld de,0x5801
    ld bc,767
    ldir

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

    ld a,2
    ld (game_state),a
    ld a,1
    ld (fire_down),a
    ret

game_over_frame:
    ; Require a release after entering this screen, then accept SPACE or the
    ; Kempston FIRE button as a clean edge for starting a new two-life game.
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
; Keyboard and optional border profiling
; ---------------------------------------------------------------------------

read_keyboard:
    xor a
    ld (player_move),a

    ; Base speed is 1 px/frame. Q requests 2 px only while held; A requests
    ; 0.5 px by alternating zero- and one-pixel scroll frames.
    ld a,1
    ld (requested_speed),a
    ld bc,0xfbfe
    in a,(c)
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
    ld a,1
    ld (fire_pending),a
    jr read_reset_key
fire_released:
    xor a
    ld (fire_down),a

read_reset_key:
    ld bc,0xfbfe
    in a,(c)
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

block_motion_table:
    ; centre step, half-width step in four-pixel units per eight-line block.
    ; Six stationary entries, four slopes each way, and two rare width runs.
    db 0,0, 0,0, 0,0, 0,0, 0,0, 0,0
    db 1,0, 1,0, 1,0, 1,0
    db 255,0, 255,0, 255,0, 255,0
    db 0,1, 0,255

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

bullet_sprite:
    db 0x01,0x80, 0x01,0x80, 0x01,0x80, 0x01,0x80

atari_ship_sprite:
    db 0x03,0x00, 0x03,0x00, 0x0f,0x00, 0x3f,0xc0
    db 0xff,0xff, 0xff,0xfc, 0xff,0xf0, 0x3f,0xf0

enemy_plane_sprite:
    ; The old table accidentally swapped each pair of rows after the first.
    db 0xc0,0x00, 0x00,0x00, 0xf0,0x3c, 0xff,0xff
    db 0x30,0xff, 0x0f,0xc0, 0x0f,0x00, 0x00,0x00

atari_helicopter_sprite:
    ; Exact ten scanlines read from the Atari 2600 black-and-white capture:
    ; three rotor/mast rows followed by the cabin, tail and landing gear.
    db 0x03,0xf0, 0x00,0x3f, 0x00,0x30, 0x00,0xfc, 0xc3,0xff
    db 0xff,0xff, 0xff,0xff, 0xc0,0xfc, 0x00,0x30, 0x00,0xfc

; New tank, built with the same eight-bit-wide/double-X constraints.
atari_tank_sprite:
    db 0x03,0xc0, 0x03,0xc0, 0x0f,0xf0, 0x3f,0xfc, 0xff,0xff
    db 0xcf,0xf3, 0xff,0xff, 0xff,0xff, 0xcc,0x33, 0xff,0xff

life_icon_one_sprite:
    db 0x18,0x00, 0x3c,0x00, 0xff,0x00, 0x7e,0x00
    db 0x18,0x00, 0x3c,0x00, 0x66,0x00

life_icon_two_sprite:
    db 0x18,0x18, 0x3c,0x3c, 0xff,0xff, 0x7e,0x7e
    db 0x18,0x18, 0x3c,0x3c, 0x66,0x66

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

course_block_head: db 31
course_phase: db 7
speed_pixels: db 1
paused: db 0
fire_down: db 0
r_down: db 0
profile_enabled: db PROFILE_BORDER

gen_center_q: db 32
gen_half_q: db 19
center_step: db 0
half_step: db 0
motion_timer: db 0
lfsr: db 0xa7
feature_countdown: db 40
fork_step: db 0
next_feature: db 0
bridge_spawn_pending: db 0
generated_island_left: db 255
generated_island_right: db 255

dirty_first_y: db 0
dirty_y: db 0
dirty_residues: db 0
row_block_index: db 0
row_screen_addr: dw 0
redraw_y: db 0

player_y: db 170
player_x: db 120
player_move: db 0
crashed: db 0
bullet_active: db 0
fire_pending: db 0
bullet_y: db 166
bullet_x: db 120
ship0_y: db 24
ship0_x: db 96
ship1_y: db 92
ship1_x: db 136
ship1_dir: db 1
ship1_timer: db 2
enemy_plane_y: db 56
enemy_plane_x: db 0
helicopter_y: db 126
helicopter_x: db 120
helicopter_move: db 1
helicopter_dir: db 1
tank_y: db 46
tank_col: db 3
tank_side: db 0
tank_active: db 1
tank_delay: db 0
bridge_active: db 0
bridge_y: db 0
bridge_col: db 0
bridge_width: db 0
bridge_rows_left: db 0
bridge_restore_y: db 0
bridge_restore_rows: db 0
bridge_attr_row: db 0
bridge_attr_rows: db 0
dirty_old_island_left: db 255
dirty_old_island_right: db 255
dirty_new_island_left: db 255
dirty_new_island_right: db 255
sprite_saved_sp: dw 0
precompute_source: dw 0
precompute_cursor: dw 0
precompute_dest: dw 0
precompute_height: db 0
precompute_rows: db 0
precompute_shift: db 0
requested_speed: db 1
slow_phase: db 0
joystick_state: db 0
lives: db 2
game_state: db 0                 ; 0=playing, 1=explosion, 2=game over
explosion_timer: db 0
explosion_anim_timer: db 0
explosion_frame: db 0
object_attr_value: db 0
object_attr_width: db 0
object_attr_col: db 0
object_attr_row: db 0
object_attr_rows: db 0
text_cursor: dw 0
text_remaining: db 0
text_y: db 0
text_col: db 0
font_source: dw 0
font_row_y: db 0
font_rows: db 0


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
block_island_left:
    ds 256,255
align 256
block_island_right:
    ds 256,255


; Pre-shifted sprite cache.  Each table selects one contiguous variant for
; X&7; every cached row is three bytes wide, including shift zero.
player_shift_table:
    dw player_shift_data,player_shift_data+39,player_shift_data+78
    dw player_shift_data+117,player_shift_data+156,player_shift_data+195
    dw player_shift_data+234,player_shift_data+273
bullet_shift_table:
    dw bullet_shift_data,bullet_shift_data+12,bullet_shift_data+24
    dw bullet_shift_data+36,bullet_shift_data+48,bullet_shift_data+60
    dw bullet_shift_data+72,bullet_shift_data+84
ship_shift_table:
    dw ship_shift_data,ship_shift_data+24,ship_shift_data+48
    dw ship_shift_data+72,ship_shift_data+96,ship_shift_data+120
    dw ship_shift_data+144,ship_shift_data+168
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

player_shift_data: ds 312,0
bullet_shift_data: ds 96,0
ship_shift_data: ds 192,0
enemy_plane_shift_data: ds 192,0
helicopter_shift_data: ds 240,0
explosion_0_shift_data: ds 312,0
explosion_1_shift_data: ds 312,0
explosion_2_shift_data: ds 312,0
