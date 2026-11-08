; wheel view: entry, main loop, helpers
wheel_enter:                    ; Wheel View from the quick menu
        ld a,(G_MAGIC)
        cp LIST_MAGIC
        jr nz,.go               ; already the wheel's folder contents
        ld a,WHEEL_MAGIC
        ld (G_MAGIC),a
        call reload_folder      ; again, with the wheel's hiding rules
        ld hl,(ENT_COUNT)       ; the selection may point past the end now
        ld e,(ix+B_SEL_LO)
        ld d,(ix+B_SEL_HI)
        ex de,hl
        or a
        sbc hl,de
        jr c,.go
        ld (ix+B_SEL_LO),0
        ld (ix+B_SEL_HI),0
.go:    ld hl,(ENT_COUNT)
        ld a,h
        or l
        jr nz,wheel_main
        ld (ix+B_REDRAW),1      ; nothing left to show: the (empty) list
        ld (KEYS),a
        ret
wheel_main:
        call view_setup
        ld a,(W_SPL)            ; just switched on: the start-up picture first
        or a
        call nz,splash
        xor a
        ld (W_SRC),a
        call root_fav           ; the root gets a Favourites entry
wheel_start:
        call display_off
        call CLEAR_NT
        ld hl,NT_SHADOW
        ld bc,$0700
        call row_flush          ; whole name table, all 28 rows
        ld hl,W_SLOT
        ld b,8
.ff:    ld (hl),$FF
        inc hl
        djnz .ff
        ld a,(G_SEL)
        and 3
        ld (W_S),a
        ld a,(W_S)              ; scroll for the centre slot: 56*s - 56 (mod 224)
        ld e,a
        ld d,0
        ld hl,vs_tab
        add hl,de
        ld a,(hl)
        call out_vs
        ld hl,corner_pat        ; frame: 4 sprite tiles, plane 0 only (video_init sets R6 = 0)
        ld de,$0020              ; tiles 1-4 (blank; the font loader clears them on exit)
        call vaddr
        ld b,104                ; tiles 1-4 frame corners, 5-13 the banner
.t:     ld a,(hl)
        out ($BE),a
        inc hl
        xor a
        out ($BE),a
        out ($BE),a
        out ($BE),a
        djnz .t
        ld hl,sat_y
        ld de,$3F00
        ld bc,5
        call vram_copy
        ld hl,sat_xt
        ld de,$3F80
        ld bc,8
        call vram_copy
        call display_on         ; the frame shows at once, then the games come in
        xor a
        ld (W_HID),a
        ld (W_FAST),a
        inc a
        ld (W_DIR),a
        call wheel_fill
.loop:  call grid_wait
        ld b,a
        bit 7,b
        jr nz,.start
        ld a,1
        bit 4,b
        jr nz,.res
        inc a
        bit 5,b
        jr nz,.res
        ld a,1
        bit 1,b
        jr nz,.mv
        ld a,-1
        bit 0,b
        jr z,.loop
.mv:    call move
        call held
        jr z,.loop              ; a tap: one step
        ld a,$80                ; still held after a whole step: speed up,
        ld (W_FAST),a           ; names only, until it's let go
.fast:  ld a,(W_DIR)
        call move
        call held
        jr nz,.fast
        xor a
        ld (W_FAST),a
        call wheel_fill         ; let go: the art for what's on screen
        jr .loop
.start: ld a,1                  ; Start: back to the list with the quick menu
        ld (W_QM),a
        xor a
.res:   ld (G_RES),a
        jp fav_res

; ---- VDP -----------------------------------------------------------------------
out_vs:                         ; A -> vertical scroll register
        ld (W_VS),a
        out ($BF),a
        ld a,$89
        out ($BF),a
        ret

vaddr:                          ; DE = VRAM address to write
        ld a,e
        out ($BF),a
        ld a,d
        or $40
        out ($BF),a
        ret

vs_tab:     DB 168,0,56,112          ; centre art at screen y 32-87, banner y 120-143
sat_y:      DB 55,55,103,103,$D0
sat_xt:     DB 96,1, 152,2, 96,3, 152,4
corner_pat: DB $FF,$FF,$C0,$C0,$C0,$C0,$C0,$C0
            DB $FF,$FF,$03,$03,$03,$03,$03,$03
            DB $C0,$C0,$C0,$C0,$C0,$C0,$FF,$FF
            DB $03,$03,$03,$03,$03,$03,$FF,$FF
banner_pat: DB $00,$00,$1F,$20,$40,$80,$80,$80     ; 5  top left (rounded)
            DB $00,$00,$FF,$00,$00,$00,$00,$00     ; 6  top
            DB $00,$00,$F8,$04,$02,$01,$01,$01     ; 7  top right
            DB $80,$80,$80,$80,$80,$80,$80,$80     ; 8  left edge
            DB $00,$00,$00,$00,$00,$00,$00,$00     ; 9  inside
            DB $01,$01,$01,$01,$01,$01,$01,$01     ; 10 right edge
            DB $80,$80,$80,$40,$20,$1F,$00,$00     ; 11 bottom left
            DB $00,$00,$00,$00,$00,$FF,$00,$00     ; 12 bottom
            DB $01,$01,$01,$02,$04,$F8,$00,$00     ; 13 bottom right
s_q_wheel:  DB "Wheel View",0
