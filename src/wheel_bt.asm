; banner helpers (in the padding after the EDOS header)

wrap1:                          ; HL = text -> B = characters on this line (at most 18),
        push hl                 ; HL = where the next line starts
        ld b,0
.n:     ld a,(hl)
        or a
        jr z,.fit
        inc hl
        inc b
        ld a,b
        cp W_TITLE_MAX+1
        jr nz,.n
        pop hl                  ; too long: back to the last space in the first 19
        push hl
        ld de,W_TITLE_MAX
        add hl,de
        ld b,W_TITLE_MAX
.sp:    ld a,(hl)
        cp ' '
        jr z,.got
        dec hl
        djnz .sp
        pop hl                  ; no space at all: cut at 18
        ld de,W_TITLE_MAX
        add hl,de
        ld b,W_TITLE_MAX
        ret
.got:   inc hl
.fit:   pop de
        ret

bar_cells:                      ; HL = shadow row; tiles B (left), B+1 x18, B+2 (right); HL -> next row
        push hl
        ld de,12
        add hl,de
        call .c
        inc b
        ld e,18
.m:     call .c
        dec e
        jr nz,.m
        inc b
        call .c
        pop hl
        ld de,64
        add hl,de
        ret
.c:     ld (hl),b               ; palette 1: colour 1 = yellow
        inc hl
        ld (hl),$08
        inc hl
        ret
