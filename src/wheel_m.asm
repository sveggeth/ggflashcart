; wheel view helpers (in the Hex View space)
slot_ptr:                       ; HL = shadow of slot G_K
        ld a,(G_K)
        ld hl,NT_SHADOW
        ld de,448
        inc a
.l:     dec a
        ret z
        add hl,de
        jr .l

; ---- HL = (HL + A) mod count, A = -2..2 --------------------------------------
step_hl:
        ld de,(G_COUNT)
        or a
        ret z
        jp p,.fw
        neg
        ld b,a
.bk:    ld a,h
        or l
        jr nz,.b1
        ld h,d
        ld l,e
.b1:    dec hl
        djnz .bk
        ret
.fw:    ld b,a
.f1:    inc hl
        or a
        sbc hl,de
        jr z,.f2
        add hl,de
.f2:    djnz .f1
        ret

; ---- the name bar ------------------------------------------------------------
bar_row:                        ; HL = shadow of rows 2-6 of the slot below the centre (the banner area), A = row
        ld a,(W_S)
        inc a
        and 3
        ld b,a
        add a,a
        add a,a
        add a,a
        sub b
        add a,2
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,NT_SHADOW
        add hl,de
        ret

