; ============================================================================
; Wheel view: the name banner
;   The slot below the centre is fully on screen, down to the bottom edge.
;   The banner takes its bottom 2 + n rows for n lines of name (n = 1-3,
;   word-wrapped at 18 characters), so it always ends at the screen's edge.
; Yellow 1-pixel border out to the screen edges with rounded corners, white
; name. Drawn straight into VRAM; the shadow keeps the art, so taking the
; banner off is just a copy of the shadow rows (rows 2-6 of that slot).
; ============================================================================

W_TITLE_MAX EQU 18

bar_on:
        call frame_set
        ld a,(W_S)
        call name_ptr
        call make_title         ; -> W_TMP
        ld hl,W_TMP             ; split into up to 3 lines: (ptr, length) x 3 in G_ENT
        ld de,G_ENT
        ld (G_LBUF),de
        ld c,0
.wl:    push hl
        push bc
        call wrap1              ; B = length, HL = next line
        ld a,b
        pop bc
        ex (sp),hl              ; HL = this line, (sp) = next
        ld de,(G_LBUF)
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (hl),a
        inc hl
        ld (G_LBUF),hl
        pop hl
        inc c
        ld a,c
        cp 3
        jr z,.wd
        ld a,(hl)
        or a
        jr nz,.wl
.wd:    call bar_row            ; HL = shadow of row 2 of the slot below, A = row
        push hl
        push af
        push bc
        ld de,(G_BUF)           ; keep the art rows (2-6)
        ld bc,320
        ldir
        pop bc
        pop af
        pop hl
        push hl
        ld b,a                  ; skip 3 - lines rows
        ld a,3
        sub c
        jr z,.s0
.sk:    ld de,64
        add hl,de
        inc b
        dec a
        jr nz,.sk
.s0:    ld a,b
        ld (G_N),a              ; first banner row
        push bc
        ld b,5                  ; top border
        call bar_cells
.mid:   ld b,8                  ; sides
        call bar_cells
        dec c
        jr nz,.mid
        ld b,11                 ; bottom border
        call bar_cells
        pop bc
        xor a
        ld (G_ATTR),a           ; white text
        ld a,(G_N)
        sub 2                   ; first text row, as a window row
        ld b,c
        ld c,a
        ld hl,G_ENT
.pl:    push bc
        push hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        call bar_text
        pop hl
        inc hl
        inc hl
        inc hl
        pop bc
        inc c
        djnz .pl
        pop hl
        push hl
        ld bc,320
        call row_flush
        pop de
        ld hl,(G_BUF)
        ld bc,320
        ldir
        ret

bar_text:                       ; DE = text, A = length, C = window row: centred
        push af
        ld b,a
        ld a,W_TITLE_MAX+2
        sub b
        srl a
        ld b,a
        pop af
        or a
        ret z
        jp print

