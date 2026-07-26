; ---------------------------------------------------------------------------
; Eight-scanline course blocks
; ---------------------------------------------------------------------------
;
; course_block_head points at the block containing screen line zero.
; course_phase is that top sample's 0..7 offset inside the block.  Advancing
; phase by one scrolls every block boundary down by one physical pixel.
;
; Page-aligned arrays hold 32 circular blocks: exact left/right pixel bounds,
; their byte columns and masks, plus optional island byte bounds (255 = none).
; A materialized 32-byte row and its predecessor delta are cached separately.

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
    ld (bridge_spawn_next),a
    ld (bridge_width_mode),a
    ld (bridge_straight_blocks),a
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
    ; A scheduled bridge spawns three blocks late and lands on a block
    ; boundary: the 16-line board covers the second and third flat blocks,
    ; and the flat block generated at the decision sits directly BELOW the
    ; band. The road's 8x8 attribute cells straddle up to seven scanlines
    ; past either band edge while scrolling, and every straddled row must
    ; be latched-flat terrain or the cells colour meandering water.
    ld a,(bridge_spawn_next)
    or a
    jr z,generate_block_no_handoff
    dec a
    ld (bridge_spawn_next),a
    jr nz,generate_block_no_handoff
    ld a,1
    ld (bridge_spawn_pending),a
generate_block_no_handoff:
    call update_course_motion

    ; Blocks of the bridge board and the few above it skip applying the
    ; motion steps (they are preserved, not zeroed - zeroing once left
    ; half_step dead after a narrow bridge and no later feature could ever
    ; trigger again). Once the counter runs out the river resumes bending
    ; even while the board is still on screen.
    ld a,(bridge_straight_blocks)
    or a
    jr z,generate_block_banks_move
    dec a
    ld (bridge_straight_blocks),a
    jp generate_block_banks_frozen
generate_block_banks_move:
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
generate_block_banks_frozen:

    call update_course_feature
    call course_bridge_flat_banks
    ld (course_flat_banks),a

    ; Convert exact pixel edges to a byte column and one of eight masks. The
    ; old half-byte-only representation was what made every bend look boxed.
    ; In the bridge's flat zone both edges snap outward to byte boundaries,
    ; so the road always meets a straight bank exactly flush with its ends -
    ; while the span stands and after it is destroyed.
    ld a,(gen_center_x)
    ld b,a
    ld a,(gen_half_x)
    ld c,a

    ld a,b
    sub c
    ld d,a
    ld a,(course_flat_banks)
    or a
    ld a,d
    jr z,course_left_x_ready
    ld a,(flat_left_x)
    ld d,a
course_left_x_ready:
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
    ld a,(course_flat_banks)
    or a
    ld a,d
    jr z,course_right_x_ready
    ld a,(flat_right_x)
    ld d,a
course_right_x_ready:
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
    jp rebuild_block_bitmap_row

rebuild_block_bitmap_row:
    ; Materialize the complete 32-byte world row for the newly generated
    ; course block. Its geometry is five contiguous runs, so emit those runs
    ; directly instead of asking get_course_background_byte_indexed thirty-two
    ; times. Runtime mixed-terrain sprite composition still sees the identical
    ; materialized row.
    ld a,(course_block_head)
    ld (block_bitmap_build_index),a
    ld c,0
    call block_bitmap_address
    ld (block_bitmap_build_ptr),hl

    ; Fetch the four edge values once. B starts as the left-land length, D/E
    ; retain the two partial edge masks across the short fill calls.
    ld a,(block_bitmap_build_index)
    ld l,a
    ld h,HIGH(block_left_col)
    ld b,(hl)
    ld h,HIGH(block_right_col)
    ld a,(hl)
    ld (block_delta_build_col),a     ; right column, temporary until delta pass
    sub b
    dec a
    ld (block_bitmap_build_col),a    ; number of all-water interior bytes
    ld h,HIGH(block_left_mask)
    ld d,(hl)
    ld h,HIGH(block_right_mask)
    ld e,(hl)

    ld hl,(block_bitmap_build_ptr)
    ld c,255
    call block_bitmap_fill_run       ; solid left land, possibly zero bytes
    ld a,d
    ld (hl),a                        ; partial left edge
    inc hl
    ld a,(block_bitmap_build_col)
    ld b,a
    ld c,0
    call block_bitmap_fill_run       ; river interior
    ld a,e
    ld (hl),a                        ; partial right edge
    inc hl
    ld a,(block_delta_build_col)
    ld b,a
    ld a,31
    sub b
    ld b,a
    ld c,255
    call block_bitmap_fill_run       ; solid right land, possibly zero bytes

    ; An island is the sole optional overwrite inside the water run.
    ld a,(block_bitmap_build_index)
    ld l,a
    ld h,HIGH(block_island_left)
    ld a,(hl)
    cp 255
    jr z,rebuild_block_bitmap_done
    ld c,a
    ld h,HIGH(block_island_right)
    ld a,(hl)
    sub c
    inc a
    ld b,a
    ld hl,(block_bitmap_build_ptr)
    ld a,c
    add a,l
    ld l,a
    ld c,255
    call block_bitmap_fill_run
rebuild_block_bitmap_done:
    jp rebuild_block_delta

block_bitmap_fill_run:
    ; Input HL=destination, B=count, C=value. Output HL=first byte after run.
    ld a,b
    or a
    ret z
    ld a,c
block_bitmap_fill_byte:
    ld (hl),a
    inc hl
    djnz block_bitmap_fill_byte
    ret

rebuild_block_delta:
    ; Compare the newly materialized block with its predecessor once. The hot
    ; dirty-row pass later replays only changed (column,value) pairs. Keep all
    ; three streaming pointers in registers: HL=new, DE=old, BC=delta output.
    ld a,(course_block_head)
    ld (block_delta_build_index),a
    ld c,0
    call block_bitmap_address
    push hl                           ; save new row while resolving old/output
    ld a,(course_block_head)
    dec a
    and 31
    ld c,0
    call block_bitmap_address
    ex de,hl                          ; DE = predecessor row
    ld a,(course_block_head)
    ld c,0
    call block_delta_address
    ld b,h
    ld c,l                            ; BC = output record
    pop hl                            ; HL = new row
    xor a
    ld (block_delta_build_col),a
    ld (block_delta_build_count),a
rebuild_block_delta_byte:
    ld a,(de)
    cp (hl)
    jr z,rebuild_block_delta_next
    ld a,(block_delta_build_count)
    cp 16
    jr nc,rebuild_block_delta_overflow
    ld a,(block_delta_build_col)
    ld (bc),a
    inc bc
    ld a,(hl)
    ld (bc),a
    inc bc
    ld a,(block_delta_build_count)
    inc a
    ld (block_delta_build_count),a
rebuild_block_delta_next:
    inc de
    inc hl
    ld a,(block_delta_build_col)
    inc a
    ld (block_delta_build_col),a
    cp 32
    jr nz,rebuild_block_delta_byte
    jr store_block_delta_count
rebuild_block_delta_overflow:
    ld a,255                         ; rare complex block uses old renderer
    ld (block_delta_build_count),a
store_block_delta_count:
    ; The count page holds 32 live entries mirrored eight times, so the dirty
    ; pass can step to the circular predecessor with a bare DEC L and the
    ; 0 -> 31 wrap costs nothing.
    ld a,(block_delta_build_index)
    ld l,a
    ld h,HIGH(block_delta_count)
    ld a,(block_delta_build_count)
    ld c,a
    ld b,8
store_block_delta_mirror:
    ld (hl),c
    ld a,l
    add a,32
    ld l,a
    djnz store_block_delta_mirror
    ret

get_course_background_byte_indexed:
    ; Input A=byte column, L=course block index. Output A=world byte.
    ld b,a
    ld h,HIGH(block_left_col)
    cp (hl)
    jr c,indexed_background_land
    jr nz,indexed_background_check_right
    ld h,HIGH(block_left_mask)
    ld a,(hl)
    ret
indexed_background_check_right:
    ld a,b
    ld h,HIGH(block_right_col)
    cp (hl)
    jr c,indexed_background_check_island
    jr nz,indexed_background_land
    ld h,HIGH(block_right_mask)
    ld a,(hl)
    ret
indexed_background_check_island:
    ld h,HIGH(block_island_left)
    ld a,(hl)
    cp 255
    jr z,indexed_background_water
    ld c,a
    ld a,b
    cp c
    jr c,indexed_background_water
    ld h,HIGH(block_island_right)
    cp (hl)
    jr c,indexed_background_land
    jr z,indexed_background_land
indexed_background_water:
    xor a
    ret
indexed_background_land:
    ld a,255
    ret

block_bitmap_address:
    ; Input A=block index 0..31, C=column 0..31. The 1KB cache is four
    ; consecutive aligned pages, eight complete course rows per page.
    ld b,a
    and 7
    rrca
    rrca
    rrca
    add a,c
    ld l,a
    ld a,b
    srl a
    srl a
    srl a
    add a,HIGH(block_bitmap_rows)
    ld h,a
    ret

block_delta_address:
    ; Input A=block index, C=zero. Each block owns sixteen two-byte operations.
    ld b,a
    and 7
    rrca
    rrca
    rrca
    add a,c
    ld l,a
    ld a,b
    srl a
    srl a
    srl a
    add a,HIGH(block_delta_ops)
    ld h,a
    ret

update_course_motion:
    ld a,(motion_timer)
    or a
    jr z,pick_course_motion
    dec a
    ld (motion_timer),a
    ret

course_bridge_flat_banks:
    ; A=nonzero while the generated block belongs to the bridge's flat-bank
    ; zone: the decision block, the delayed spawn block, or the straight
    ; blocks entering just above the span.
    ld a,(bridge_spawn_next)
    ld b,a
    ld a,(bridge_spawn_pending)
    or b
    ld b,a
    ld a,(bridge_straight_blocks)
    or b
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
    ; Alternate a naturally timed bridge with one that deliberately waits for
    ; a narrow river. Half-width 56 means at most about 112 pixels of water.
    ld a,(bridge_width_mode)
    or a
    jr z,generate_bridge_now
    ld a,(gen_half_x)
    cp 57
    jr c,generate_bridge_now
    ld a,254                        ; keep narrowing while this feature waits
    ld (half_step),a
    ld a,4
    ld (feature_countdown),a
    ret
generate_bridge_now:
    xor a
    ld (next_feature),a
    ld a,(bridge_width_mode)
    xor 1
    ld (bridge_width_mode),a
    ld a,3
    ld (bridge_spawn_next),a
    ; Latch both edges snapped outward to byte boundaries. Every block of
    ; the flat zone reuses these exact values, so the road always meets a
    ; perfectly straight bank flush with its ends - while the span stands
    ; and after its destruction alike.
    ld a,(gen_center_x)
    ld b,a
    ld a,(gen_half_x)
    ld c,a
    ld a,b
    sub c
    and 0xf8
    ld (flat_left_x),a
    ld a,b
    add a,c
    add a,7
    and 0xf8
    ld (flat_right_x),a
    ld a,6
    ld (bridge_straight_blocks),a
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
    ; The hot loop keeps everything in registers: DE walks the scanline base,
    ; L walks the mirrored delta-count page (H stays on it), so an unchanged
    ; block costs one count read plus the Y+8 address step. dirty_y and
    ; row_block_index exist only for the rare full-renderer fallback and are
    ; reconstructed there from the loop position.
    ld a,(dirty_first_y)
    add a,16                       ; skip the two protected top character rows
    call get_block_index_for_y
    ld a,l
    ld (row_block_index),a
    ld a,(dirty_first_y)
    add a,16
    call calc_screen_line_addr
    ex de,hl                       ; keep the current scanline base in DE
    ld a,(row_block_index)
    ld l,a
    ld h,HIGH(block_delta_count)
    ld a,19                        ; every residue occurs 19 times in 152 rows
    ld (dirty_rows_remaining),a
dirty_row_loop:
    ld a,(hl)                      ; delta count of this block
    or a
    jr nz,dirty_row_changed
dirty_row_advance:
    ld a,(dirty_rows_remaining)
    dec a
    ld (dirty_rows_remaining),a
    jr z,dirty_next_residue
    dec l                          ; circular predecessor; the mirrored count
                                   ; page makes the 0 -> 31 wrap free
    ; Y+8 is an incremental Spectrum display-file step. Crossing L=0xe0
    ; enters the next 64-line third, hence the additional D+=8 on carry.
    ld a,e
    add a,32
    ld e,a
    jr nc,dirty_row_loop
    ld a,d
    add a,8
    ld d,a
    jr dirty_row_loop

dirty_row_changed:
    ; The common case is a short precomputed list of bytes which changed from
    ; block i-1 to i. A complex island transition carries count=255 and falls
    ; back to the complete edge renderer.
    cp 255
    jr z,dirty_row_fallback
    ld b,a
    push hl                        ; count-page cursor survives the replay
    ; Delta slot: block_delta_ops + index*32, four consecutive aligned pages.
    ld a,l
    and 31
    ld c,a
    and 7
    rrca
    rrca
    rrca                           ; (index & 7) * 32
    ld l,a
    ld a,c
    srl a
    srl a
    srl a
    add a,HIGH(block_delta_ops)
    ld h,a
dirty_delta_replay:
    ld a,(hl)
    inc hl
    add a,e
    ld c,e
    ld e,a
    ld a,(hl)
    ld (de),a
    inc hl
    ld e,c
    djnz dirty_delta_replay
    pop hl
    jr dirty_row_advance

dirty_row_fallback:
    ; Reconstruct the row Y and block index which the fast loop keeps
    ; implicit, then run the full edge renderer with the registers saved.
    ld a,(dirty_rows_remaining)
    ld b,a
    ld a,19
    sub b                          ; rows already completed this residue
    add a,a
    add a,a
    add a,a
    ld c,a
    ld a,(dirty_first_y)
    add a,16
    add a,c
    ld (dirty_y),a
    ld a,l
    and 31
    ld (row_block_index),a
    push de
    push hl
    call render_v3_row_indexed
    pop hl
    pop de
    jr dirty_row_advance

dirty_next_residue:
    ld a,(dirty_first_y)
    dec a
    and 7
    ld (dirty_first_y),a
    ld a,(dirty_residues)
    dec a
    ld (dirty_residues),a
    jp nz,dirty_residue_loop
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
    jp render_v3_row_indexed

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
    ; get_block_index_for_y uses C as scratch, so preserve the lane selector;
    ; losing it made every right-bank shell select the left side of an island.
    push bc
    call get_block_index_for_y
    pop bc
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
