; ============================================================================
; Wheel view: the tidied-up title
; (in the unused padding after the EDOS header, $0090-$01FF)
; ============================================================================


; ---- HL = file name -> W_TMP, B = length
;   "Simpsons, The - Bart vs. the World (World).gg"
;     -> "The Simpsons - Bart vs. the World"
; Text in ( ) and [ ] goes, double spaces close up, the extension goes (a
; dot only counts as one if no space follows it), ", The" / ", A" / ", An"
; moves to the front.
make_title:
        ld de,(G_BUF)
        inc d                   ; T1 = G_BUF + 256 (the banner backup is below)
        dec de
        ld a,' '
        ld (de),a               ; a space before T1: leading spaces are dropped
        inc de
        push de
        ld bc,0                 ; B = length, C = bracket depth
        xor a
        ld (G_CH),a             ; extension dot: offset + 1, 0 = none
.l:     ld a,(hl)
        inc hl
        or a
        jr z,.end
        cp '('
        jr z,.op
        cp '['
        jr z,.op
        cp ')'
        jr z,.cl
        cp ']'
        jr z,.cl
        inc c
        dec c
        jr nz,.l                ; inside brackets
        cp ' '
        jr nz,.pt
        xor a
        ld (G_CH),a             ; a space after a dot: it wasn't an extension
        dec de
        ld a,(de)
        inc de
        cp ' '
        jr z,.l                 ; no double spaces
        ld a,' '
        jr .wr
.pt:    cp '.'
        jr nz,.wr
        ld a,b
        inc a
        ld (G_CH),a
        ld a,'.'
.wr:    ld (de),a
        inc de
        inc b
        jr .l
.op:    inc c
        jr .l
.cl:    ld a,c
        or a
        jr z,.l
        dec c
        jr .l
.end:   ld a,(G_CH)
        or a
        jr z,.nd
        dec a
        ld b,a                  ; cut at the extension
.nd:    pop hl
        push hl
        ld e,b
        ld d,0
        add hl,de
.tr:    ld a,b                  ; trailing spaces
        or a
        jr z,.te
        dec hl
        ld a,(hl)
        cp ' '
        jr nz,.te1
        dec b
        jr .tr
.te1:   inc hl
.te:    ld (hl),0
        pop hl                  ; look for ", The" / ", An" / ", A"
        push hl
.s:     ld a,(hl)
        or a
        jr z,.plain
        inc hl
        cp ','
        jr nz,.s
        ld a,(hl)
        cp ' '
        jr nz,.s
        inc hl                  ; HL = the word after ", "
        push hl
        dec hl
        dec hl
        ld (G_N),hl             ; where the comma is
        pop hl
        ld de,s_arts
.t:     push hl
.tc:    ld a,(de)
        inc de
        or a
        jr z,.we
        cp (hl)
        inc hl
        jr z,.tc
.sk:    ld a,(de)
        inc de
        or a
        jr nz,.sk
.nx:    pop hl
        ld a,(de)
        or a
        jr nz,.t
        jr .s
.we:    ld a,(hl)               ; the name's word has to end here too
        or a
        jr z,.got
        cp ' '
        jr nz,.nx
.got:   ex de,hl                ; DE = after the article
        pop hl                  ; HL = the article
        push de
        ld de,W_TMP
.cw:    ld a,(hl)               ; "The "
        or a
        jr z,.cs
        cp ' '
        jr z,.cs
        ld (de),a
        inc hl
        inc de
        jr .cw
.cs:    ld a,' '
        ld (de),a
        inc de
        pop bc
        pop hl                  ; T1
        push bc
        ld bc,(G_N)
.c1:    ld a,l                  ; "Simpsons"
        cp c
        jr nz,.c1c
        ld a,h
        cp b
        jr z,.c1e
.c1c:   ld a,(hl)
        ld (de),a
        inc hl
        inc de
        jr .c1
.c1e:   pop hl                  ; " - Bart vs. the World"
        jr .c2
.plain: pop hl
        ld de,W_TMP
.c2:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,.c2
        ld hl,W_TMP             ; length, at most 18, no trailing spaces
        ld b,0
.ln:    ld a,(hl)
        or a
        jr z,.lz
        inc hl
        inc b
        jr .ln
.lz:    ld a,b
        cp 63
        jr c,.t2
        ld b,62
.t2:    ld a,b
        or a
        jr z,.z
        ld hl,W_TMP-1
        ld e,b
        ld d,0
        add hl,de
        ld a,(hl)
        cp ' '
        jr nz,.z
        dec b
        jr .t2
.z:     ld hl,W_TMP
        ld e,b
        ld d,0
        add hl,de
        ld (hl),0
        ret

s_arts:     DB "The",0,"An",0,"A",0,0
