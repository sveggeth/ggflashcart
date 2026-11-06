; ============================================================================
; Wheel view (build 5): a vertical strip of wheel art, centre one framed
;
; The 32x28 name table holds exactly four 7-row slots, so the strip wraps in
; hardware: slot k = rows 7k..7k+6, tiles THUMB_TILE+56k (the grid's cells).
; The centre slot sits at screen y 44-99 and the VDP's vertical scroll moves
; 56 px per step, eased over 10 frames. The slot that is off screen is loaded
; while you look at the others, in the direction you last moved.
; The frame is four sprites (sprites don't scroll); the name bar is drawn
; straight into VRAM over the top row of the slot below the centre.
; ============================================================================

W_S         EQU $DB50   ; slot of the centre game (0-3)
W_VS        EQU $DB51   ; vertical scroll now
W_PAL       EQU $DB52   ; pack palette already written
W_DIR       EQU $DB53   ; +1 / -1
W_SLOT      EQU $DB58   ; [4] u16 entry shown in each slot ($FFFF = none)
W_TMP       EQU $DE00   ; title buffer (64 bytes; the stack stays above $DF00)
WHEEL_MAGIC EQU $A5
VBLANK      EQU $0739
WROW_OFS    EQU $3800 - NT_SHADOW       ; shadow address -> VRAM address

; ---- one step up or down --------------------------------------------------------
move:                           ; A = +1 / -1
        ld (W_DIR),a
        add a,a
        call ensure_rel         ; the slot coming into view (normally preloaded)
        call bar_row
        ld bc,320
        call row_flush          ; take the banner off
        ld hl,ease
        ld b,10
        ld a,(W_FAST)
        or a
        jr z,.a
        ld hl,ease_f            ; held down: a quick 4-frame step
        ld b,4
.a:     push bc
        push hl
        ld c,(hl)
        ld a,(W_DIR)
        or a
        ld a,(W_VS)
        jp m,.up
        add a,c
        cp 224
        jr c,.st
        sub 224
        jr .st
.up:    sub c
        jr nc,.st
        add a,224
.st:    ld (W_VS),a
        call VBLANK
        ld a,(W_VS)
        call out_vs
        pop hl
        inc hl
        pop bc
        djnz .a
        ld a,(W_DIR)
        ld hl,W_S
        add a,(hl)
        and 3
        ld (hl),a
        ld hl,(G_SEL)
        ld a,(W_DIR)
        call step_hl
        ld (G_SEL),hl
        ld a,(W_FAST)
        or a
        ret nz                  ; held down: no banner, nothing preloaded
        call bar_on
        ld a,(W_DIR)            ; preload the next one the same way
        add a,a
        ; fall through

; ---- make sure slot (centre + A) shows entry (selection + A) -----------------
ensure_rel:
        push af
        ld hl,W_S
        add a,(hl)
        and 3
        ld (G_K),a
        pop af
        ld hl,(G_SEL)
        call step_hl
        ld (G_IDX),hl
        ex de,hl
        ld a,(W_FAST)           ; a slot filled while scrolling fast (names only)
        or d                    ; is marked with bit 15, so it gets its art later
        ld d,a
        ld a,(G_K)
        add a,a
        add a,W_SLOT & $FF
        ld l,a
        ld h,W_SLOT >> 8
        ld a,(hl)
        cp e
        jr nz,.ld
        inc hl
        ld a,(hl)
        cp d
        ret z
        dec hl
.ld:    ld (hl),e
        inc hl
        ld (hl),d
        ; fall through

load_slot:                      ; entry G_IDX into slot G_K
        ld hl,G_VALID           ; G_VALID, G_ISDIR, G_HAVE = 0
        ld b,12
.z:     ld (hl),0
        inc hl
        djnz .z
        ld a,1
        ld hl,G_VALID
        call put_k
        ld a,(G_K)
        call name_ptr
        ld (hl),0
        call slot_ptr
        ld d,h
        ld e,l
        inc de
        ld (hl),0
        ld bc,447
        ldir
        ld hl,W_DIRS
        xor a
        call put_k
        call box_default
        call fetch_entry
        or a
        jr nz,.inv
        ld hl,G_ISDIR
        call get_k
        ld hl,W_DIRS
        call put_k
        ld hl,G_ISDIR
        call get_k
        or a
        jr nz,.txt
        ld a,(W_FAST)
        or a
        jr nz,.txt              ; scrolling fast: the name only
        call load_header
        ld a,(G_PACKOK)
        or a
        call nz,load_thumbs
        jr .txt
.inv:   xor a
        ld hl,G_VALID
        call put_k
.txt:   ld hl,G_VALID
        call get_k
        or a
        jr z,.fl
        ld hl,G_HAVE
        call get_k
        or a
        jr nz,.fl
        ld a,(G_K)
        call cell_origin
        call wheel_textbox
.fl:    call slot_ptr
        ld bc,448
        ; fall through
row_flush:                      ; HL = shadow address, BC = bytes -> VRAM
        push hl
        ld de,WROW_OFS
        add hl,de
        ex de,hl
        pop hl
        jp vram_copy


ease:       DB 2,4,6,8,8,8,8,6,4,2
ease_f:     DB 14,14,14,14
W_FAST      EQU $DB57   ; $80 while Up/Down is held (fast scrolling)

match_list:                     ; HL = B bytes, DE = list of B-byte names, 0 ends -> Z if found
.n:     ld a,(de)
        or a
        jr z,.none
        push hl
        push bc
        ld c,0
.c:     ld a,(de)
        cp (hl)
        jr z,.s
        inc c
.s:     inc de
        inc hl
        djnz .c
        ld a,c
        pop bc
        pop hl
        or a
        ret z
        jr .n
.none:  or 1
        ret

