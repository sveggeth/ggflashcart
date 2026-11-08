; ---- jump to the next entry starting with a letter --------------------------
letter_jump:
        ld hl,(ENT_COUNT)
        ld a,h
        or l
        ret z
        ld a,1
        ld (G_STPREV),a
        ld a,(G_LETTER)
        cp 27
        jr c,.draw
        xor a
        ld (G_LETTER),a
.draw:  call CLEAR_NT
        xor a
        ld (G_ATTR),a
        ld de,s_q_letter
        ld bc,$0301
        ld a,20
        call print
        ld b,0
.sym:   push bc
        ld a,(G_LETTER)
        cp b
        ld a,0
        jr nz,.at
        ld a,$08
.at:    ld (G_ATTR),a
        ld a,b
        cp 26
        ld a,'#'
        jr z,.ch
        ld a,b
        add a,'A'
.ch:    ld (G_STR),a
        xor a
        ld (G_STR+1),a
        ld a,b                  ; 9 per row: column 1 + 2x, row 5 + 2y
        ld c,0
.dv:    cp 9
        jr c,.dd
        sub 9
        inc c
        jr .dv
.dd:    add a,a
        inc a
        ld b,a
        ld a,c
        add a,a
        add a,5
        ld c,a
        ld de,G_STR
        ld a,1
        call print
        pop bc
        inc b
        ld a,b
        cp 27
        jr nz,.sym
        call FLUSH_NT
        call grid_wait
        bit 7,a
        ret nz
        bit 5,a
        ret nz
        bit 4,a
        jr nz,.go
        ld b,a
        ld hl,G_LETTER
        bit 2,b
        jr z,.nl
        ld a,(hl)
        or a
        jr z,.nl
        dec (hl)
.nl:    bit 3,b
        jr z,.nr
        ld a,(hl)
        cp 26
        jr nc,.nr
        inc (hl)
.nr:    bit 0,b
        jr z,.nu
        ld a,(hl)
        cp 9
        jr c,.nu
        sub 9
        ld (hl),a
.nu:    bit 1,b
        jp z,.draw
        ld a,(hl)
        add a,9
        cp 27
        jp nc,.draw
        ld (hl),a
        jp .draw
.go:    ld a,(G_LETTER)         ; 0 = '#' (anything that doesn't start with a letter)
        cp 26
        ld a,0
        jr z,.hash
        ld a,(G_LETTER)
        add a,'A'
.hash:  ld (G_CH),a
        xor a
        ld (G_ATTR),a
        ld de,s_search
        ld bc,$040D
        ld a,20
        call print
        call FLUSH_NT
        ld hl,$00E5
        call alloc_hl
        ld (G_LREC),hl
        ld l,(ix+B_SEL_LO)
        ld h,(ix+B_SEL_HI)
        ld (G_I),hl
        ld hl,(ENT_COUNT)
        ld (G_N),hl
.next:  ld hl,(G_N)
        ld a,h
        or l
        jr z,.done
        dec hl
        ld (G_N),hl
        ld hl,(G_I)             ; idx = (idx + 1) mod count, starting after the selection
        inc hl
        ld de,(ENT_COUNT)
        or a
        sbc hl,de
        add hl,de
        jr c,.w
        ld hl,0
.w:     ld (G_I),hl
        add hl,hl
        add hl,hl
        ld de,(ENT_TABLE)
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        ld hl,(G_LREC)
        push hl
        push bc
        push de
        call READ_ENTRY
        pop af
        pop af
        pop af
        ld a,l
        or a
        jr nz,.next
        ld hl,(G_LREC)
        ld a,(hl)
        cp 'a'
        jr c,.up
        cp 'z'+1
        jr nc,.up
        sub 32
.up:    ld b,a
        ld a,(G_CH)
        or a
        jr z,.other
        cp b
        jr nz,.next
        jr .found
.other: ld a,b
        cp 'A'
        jr c,.found
        cp 'Z'+1
        jr nc,.found
        jr .next
.found: ld hl,(G_I)
        ld (ix+B_SEL_LO),l
        ld (ix+B_SEL_HI),h
.done:  ld hl,$00E5
        jp free_hl

