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
.out:   ld hl,$00E5+512         ; both buffers (the OS's pool just counts)
        jp free_hl

; ---- Start in the file list --------------------------------------------------
quick_menu:
        xor a
        ld (G_SATTR),a
        ld hl,0
        push hl
        ld hl,qm_items
        push hl
        call MENU
        pop af
        pop af
        ld a,l
        or a
        jp z,wheel_enter
        dec a
        jr nz,.nl
        ld a,LIST_MAGIC         ; List View: reload the folder with nothing hidden
        ld (G_MAGIC),a
        ld (ix+B_REDRAW),2
        xor a
        ld (KEYS),a
        ret
.nl:    dec a
        jr nz,.n1
        call need_ovl           ; Jump To Letter lives in the overlay now
        ld a,6
        call nz,ovl_call
        jr .back
.n1:    dec a
        jr nz,.n2
        ld hl,REC_BASE
        ld b,REC_MAX
        ld de,s_recent
        call show_list
        jr .back
.n2:    dec a
        jr nz,.n3
        ld hl,FAV_BASE
        ld b,FAV_MAX
        ld de,s_favs
        call show_list
        jr .back
.n3:    dec a
        jp z,pick_start
.back:  ld (ix+B_REDRAW),1      ; the browser redraws the list
        xor a
        ld (KEYS),a
        ret

; ---- start-up sound player (see wheel_s.asm) ----
sound_play:                     ; save RAM -> PSG channel 0 volume, 450 cycles a sample
        ld a,(W_SND)
        or a
        ret z
        ld a,$FF
        out ($06),a             ; Game Gear stereo: everything on both sides
        ld hl,psg_init
        ld bc,$067F
        otir
        call sram_on
        ld hl,SND_RAM+16
        ld bc,(G_N)
.l:     ld a,(hl)               ; high nibble          7
        rrca                    ;                      16
        rrca
        rrca
        rrca
        and $0F                 ;                      7
        or $90                  ;                      7
        out ($7F),a             ;                      11
        ld a,26                 ; delays measured in the emulator:
.d1:    dec a
        jr nz,.d1
        ld a,(hl)               ; low nibble           7
        and $0F                 ;                      7
        or $90                  ;                      7
        out ($7F),a             ;                      11
        ld a,23                 ; 450 cycles between every two samples
.d2:    dec a
        jr nz,.d2
        inc hl                  ;                      6
        dec bc                  ;                      6
        ld a,b                  ;                      4
        or c                    ;                      4
        jr nz,.l                ;                      12 -> 450
        call sram_off
        ld a,$9F                ; channel 0 off again
        out ($7F),a
        ret


; ---- the overlay: more code, loaded from thumbs.pak into save RAM ------------
; (bank 1 $9800-$9FFF, copied there at power-on; see ovl.asm). Only code that
; never changes the memory mapping may be called from it.
ovl_call:                       ; A = overlay function -> its A and flags
        ld c,a                  ; (no overlay: A = 0, Z)
        ld a,(W_OVL)
        or a
        ret z
        call sram_on
        ld a,c
        call OVL_GO
        push af
        call sram_off
        pop af
        ret

ov_pf:                          ; pack_find, with the picture chosen for this entry
        xor a
        call ovl_call
        jp pack_find

need_ovl:                       ; NZ if the overlay is loaded, else says so (Z)
        ld a,(W_OVL)
        or a
        ret nz
        ld de,s_needpak
        call show_msg
        xor a
        ret
s_needpak:  DB "Update thumbs.pak",0

pick_start:                     ; Quick Menu -> Change Picture: a wheel of every picture
        call need_ovl
        jr z,.no
        xor a
        ld (G_RES),a
        call view_setup
        ld a,3
        call ovl_call
        jp z,view_exit          ; no picture list: back to the list
        jp wheel_start
.no:    ld (ix+B_REDRAW),1
        xor a
        ld (KEYS),a
        ret

s_added:    DB "Favourite added",0
s_removed:  DB "Favourite removed",0
s_full:     DB "Favourites full",0
s_empty:    DB "List is empty",0
s_gone:     DB "Not found",0
s_anykey:   DB "Press any key",0
s_lmagic:   DB "RF01"
        INCLUDE "wheel_m.asm"
ease_f:     DB 14,14,14,14
int_check:                      ; NZ (A = Up/Down bits) if filling in and Up/Down was
        ld a,(W_INT)            ; just pressed (a held button doesn't count)
        or a
        ret z
        jp pad_new

psg_init:   DB $9F,$BF,$DF,$FF,$80,$00  ; all silent; channel 0 period 0 = flat output
s_sound:    DB "Sound",0
s_ovl:      DB "Overlay",0
feat_a_end:
        ASSERT feat_a_end <= $695B, "features_a does not fit in the Hex View space"
        DISPLAY "features A: ", /D, feat_a_end - $6492, " of 1225 bytes"

; ---- wiring --------------------------------------------------------------------
        ORG $4096               ; ROM menu item 3: "Favourites" instead of "Hex View"
        DB s_favs & $FF          ; (operands of "ld (iy),$27" at $4093 / "ld (iy+1),$41" at $4097)
        ORG $409A
        DB s_favs >> 8
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
