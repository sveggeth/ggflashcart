; ============================================================================
; Build 4 features, part A: in the space Hex View used ($6492-$695A)
;   favourite toggle (at Hex View's old entry point), recently played,
;   the list screen, jump to letter, and the byte patches that wire them in.
;
; Lists live in SRAM bank 1 after the OS settings (offset $1000, mapped $9000):
;   $9000 "RF01", $9010 recent[8], $9110 favourites[16]
;   entry (32 bytes): u32 directory-entry position, name (27 chars + 0)
; ============================================================================

LIST_BASE   EQU $9000
LIST_SIZE   EQU $0310
REC_BASE    EQU $9010
REC_MAX     EQU 8
FAV_BASE    EQU $9110
FAV_MAX     EQU 16

G_ENT       EQU $DB10   ; 32-byte entry being built
G_LSEL      EQU $DB30
G_LCNT      EQU $DB31
G_LBUF      EQU $DB32   ; ptr
G_LBASE     EQU $DB34   ; ptr
G_LMAX      EQU $DB36
G_LTITLE    EQU $DB37   ; ptr
G_LETTER    EQU $DB39   ; 0-25 = A-Z, 26 = '#'
G_LREC      EQU $DB3A   ; ptr
G_I         EQU $DB3C   ; u16
G_CH        EQU $DB3E
G_N         EQU $DB40   ; u16
G_SATTR     EQU $DB42   ; attribute for spaces/padding (0 = black)

        ORG $6492
; ---- toggle_fav(rec*): the ROM menu's third item, where Hex View used to be --
toggle_fav:
        ld hl,2
        add hl,sp
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call make_ent
        call sram_on
        call lists_init
        ld hl,FAV_BASE
        ld b,FAV_MAX
        call ent_find
        jr nz,.add
        ld b,FAV_MAX
        call ent_remove
        call sram_off
        ld de,s_removed
        jr .msg
.add:   ld hl,FAV_BASE
        ld b,FAV_MAX
        call ent_free
        jr nz,.full
        ex de,hl
        ld hl,G_ENT
        ld bc,32
        ldir
        call sram_off
        ld de,s_added
        jr .msg
.full:  call sram_off
        ld de,s_full
.msg:   call show_msg
        ld l,0
        ret

; ---- recent_add(HL = rec): move/insert the game at the top of the list -------
recent_add:
        call make_ent
        call sram_on
        call lists_init
        ld hl,REC_BASE
        ld b,REC_MAX
        call ent_find
        jr nz,.ins
        ld b,REC_MAX
        call ent_remove
.ins:   ld hl,REC_BASE+32*(REC_MAX-1)-1
        ld de,REC_BASE+32*REC_MAX-1
        ld bc,32*(REC_MAX-1)
        lddr
        ld hl,G_ENT
        ld de,REC_BASE
        ld bc,32
        ldir
        jp sram_off

; ---- entry helpers (SRAM mapped) --------------------------------------------
make_ent:                       ; HL = rec -> G_ENT
        push hl
        ld hl,G_ENT
        ld (hl),0
        ld de,G_ENT+1
        ld bc,31
        ldir
        pop hl
        push hl
        ld de,$D4               ; the record's own directory position
        add hl,de
        ld de,G_ENT
        ld bc,4
        ldir
        pop hl
        ld de,G_ENT+4
        ld b,27
.c:     ld a,(hl)
        or a
        ret z
        ld (de),a
        inc hl
        inc de
        djnz .c
        ret

lists_init:                     ; create the lists the first time
        ld hl,LIST_BASE
        ld de,s_lmagic
        ld b,4
.c:     ld a,(de)
        cp (hl)
        jr nz,.init
        inc hl
        inc de
        djnz .c
        ret
.init:  ld hl,LIST_BASE
        ld (hl),0
        ld de,LIST_BASE+1
        ld bc,LIST_SIZE-1
        ldir
        ld hl,s_lmagic
        ld de,LIST_BASE
        ld bc,4
        ldir
        ret

ent_find:                       ; HL = list, B = slots -> Z: HL = entry, A = index
        ld c,0
.l:     push bc
        push hl
        ld de,G_ENT
        ld b,32
.cmp:   ld a,(de)
        cp (hl)
        jr nz,.ne
        inc hl
        inc de
        djnz .cmp
        pop hl
        pop bc
        ld a,c
        cp a
        ret
.ne:    pop hl
        pop bc
        ld de,32
        add hl,de
        inc c
        djnz .l
        or 1
        ret

ent_free:                       ; HL = list, B = slots -> Z: HL = first empty slot
.l:     push hl
        ld de,4
        add hl,de
        ld a,(hl)
        pop hl
        or a
        ret z
        ld de,32
        add hl,de
        djnz .l
        or 1
        ret

ent_remove:                     ; HL = entry, A = index, B = slots: close the gap
        ld c,a
        ld a,b
        sub c
        dec a                   ; entries after this one
        ld d,h
        ld e,l
        ld bc,32
        add hl,bc
        or a
        jr z,.clr
        ld b,a
.mv:    push bc
        ld bc,32
        ldir
        pop bc
        djnz .mv
.clr:   ld h,d
        ld l,e
        ld (hl),0
        inc de
        ld bc,31
        ldir
        ret

; ---- message screen ----------------------------------------------------------
show_msg:                       ; DE = text; waits for a key
        push de
        call CLEAR_NT
        xor a
        ld (G_ATTR),a
        pop de
        ld h,d
        ld l,e
        ld b,0
.ln:    ld a,(hl)
        or a
        jr z,.d
        inc hl
        inc b
        jr .ln
.d:     ld a,20
        sub b
        srl a
        ld b,a
        ld c,7
        ld a,20
        call print
        ld de,s_anykey
        ld bc,$0309
        ld a,20
        call print
        call FLUSH_NT
        jp WAIT_KEY

; ---- list screen: recently played / favourites -------------------------------
show_list:                      ; HL = list, B = slots, DE = title
        ld (G_LBASE),hl
        ld a,b
        ld (G_LMAX),a
        ld (G_LTITLE),de
        ld hl,512
        call alloc_hl
        ld (G_LBUF),hl
        ld hl,$00E5
        call alloc_hl
        ld (G_LREC),hl
        call sram_on
        call lists_init
        ld hl,(G_LBASE)
        ld de,(G_LBUF)
        ld bc,512
        ldir
        call sram_off
        ld hl,(G_LBUF)          ; count the used slots
        ld a,(G_LMAX)
        ld b,a
        ld c,0
.cnt:   push hl
        ld de,4
        add hl,de
        ld a,(hl)
        pop hl
        or a
        jr z,.cd
        ld de,32
        add hl,de
        inc c
        djnz .cnt
.cd:    ld a,c
        ld (G_LCNT),a
        or a
        jr nz,.has
        ld de,s_empty
        call show_msg
        jp .out
.has:   xor a
        ld (G_LSEL),a
        inc a
        ld (G_STPREV),a
.draw:  call CLEAR_NT
        xor a
        ld (G_ATTR),a
        ld de,(G_LTITLE)
        ld bc,$0000
        ld a,20
        call print
        ld b,0
.row:   ld a,b
        ld hl,G_LCNT
        cp (hl)
        jr nc,.shown
        push bc
        ld a,(G_LSEL)
        cp b
        ld a,0
        jr nz,.a
        ld a,$08
.a:     ld (G_ATTR),a
        ld (G_SATTR),a          ; highlighted row: a full-width bar
        ld l,b
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,(G_LBUF)
        add hl,de
        ld de,4
        add hl,de
        ex de,hl
        ld a,b
        add a,2
        ld c,a
        ld b,0
        ld a,20
        call print
        pop bc
        inc b
        jr .row
.shown: xor a
        ld (G_SATTR),a
        call FLUSH_NT
        call grid_wait
        bit 7,a
        jr nz,.out
        bit 5,a
        jr nz,.out
        bit 4,a
        jr nz,.open
        ld b,a
        ld hl,G_LSEL
        bit 0,b
        jr z,.nu
        ld a,(hl)
        or a
        jr z,.nu
        dec (hl)
.nu:    bit 1,b
        jr z,.draw
        ld a,(G_LCNT)
        dec a
        cp (hl)
        jp z,.draw
        jp c,.draw
        inc (hl)
        jp .draw
.open:  ld a,(G_LSEL)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,(G_LBUF)
        add hl,de
        push hl
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
        pop de                  ; DE = slot
        ld a,l
        or a
        jr nz,.gone
        ld hl,4                 ; still the same file?
        add hl,de
        ex de,hl
        ld hl,(G_LREC)
        ld b,27
.nc:    ld a,(de)
        cp (hl)
        jr nz,.gone
        or a
        jr z,.same
        inc hl
        inc de
        djnz .nc
.same:  ld hl,(G_LREC)          ; the usual ROM menu: Load And Start / Load Only / Favourite
        push hl
        call ROM_MENU
        pop af
        jr .out
.gone:  ld de,s_gone
        call show_msg
.out:   ld hl,$00E5
        call free_hl
        ld hl,512
        jp free_hl

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

s_added:    DB "Favourite added",0
s_removed:  DB "Favourite removed",0
s_full:     DB "Favourites are full",0
s_empty:    DB "The list is empty",0
s_gone:     DB "Game not found",0
s_anykey:   DB "Press any key",0
s_search:   DB "Searching...",0
s_lmagic:   DB "RF01"
        INCLUDE "wheel_m.asm"
feat_a_end:
        ASSERT feat_a_end <= $695B, "features_a does not fit in the Hex View space"
        DISPLAY "features A: ", /D, feat_a_end - $6492, " of 1225 bytes"

; ---- wiring --------------------------------------------------------------------
        ORG $4096               ; ROM menu item 3: "Favourite" instead of "Hex View"
        DB s_fav & $FF          ; (operands of "ld (iy),$27" at $4093 / "ld (iy+1),$41" at $4097)
        ORG $409A
        DB s_fav >> 8
        ORG $40BC               ; Load And Start -> remember in Recently Played
        call rec_hook
        ORG $40E2               ; Load Only -> the same
        call rec_hook
        ORG $41D3               ; .txt files: no viewer any more
        call ret_zero
        ORG $4CF4               ; save-file menu: drop its "Hex View" item
        DB 0
        ORG $4CF8
        DB 0
        ORG $4D49
        call ret_zero
