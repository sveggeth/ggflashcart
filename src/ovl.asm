; ============================================================================
; The overlay (build 21): code that lives in thumbs.pak, not in the OS image.
; At power-on the OS copies the pack's "Overlay" record into save RAM bank 1
; at $9800 (16-byte header, code from $9810) and calls it with that bank
; mapped in slot 2. So this code must never call anything that changes the
; mapping (sram_on/sram_off, fav_count, root_fav, fetch_entry's favourites
; path, the flash writer...). The save RAM it needs (lists, choices) is in
; the same bank, so it is always there.
;
;   0 remap    before a picture is looked up: the picture chosen for this entry
;   1 fetch    Change Picture's wheel: entry G_IDX (0 = the entry's own picture)
;   2 result   1 / 2 / Start in that wheel: keep the choice, then go back
;   3 start    Quick Menu -> Change Picture: whose picture, the picture list
;   5 save     leaving the wheel: remember the centre entry
;   6 letter   Quick Menu -> Jump To Letter
;
; Choices: $9400 "OV01", $9404 count, $9408 entries of 10 bytes:
;   u32 hash of the entry's name, u32 hash of the picture's name, u16 its
;   number in the picture list (to start there next time). The picture list
;   is the pack's "Library" record: a header sector ("LIB1", u16 count), then
;   8 entries of 64 bytes per sector: u32 hash, name (up to 59 chars + 0).
; ============================================================================

        INCLUDE "ovl_syms.asm"

OV_MAG      EQU $9400
OV_N        EQU $9404
OV_TAB      EQU $9408
OV_MAX      EQU 100
O_TGT       EQU $9F00   ; u32 hash of the entry whose picture is being chosen
O_SEL       EQU $9F04   ; u16 its place in the wheel / list
O_LIST      EQU $9F06   ; Change Picture was opened from List View
O_LSEC      EQU $9F07   ; u16 first sector of the picture list
O_LN        EQU $9F09   ; u16 pictures in it
O_ORIG      EQU $9F10   ; [4] u32 the entry's own hash, for a slot that was remapped
O_MAP       EQU $9F20   ; [4] u32 what it was remapped to

        ORG $9800
        DB "OVL1"
        DW ovl_end - $9810
        DW 21                   ; OVL_BUILD in wheel_s.asm
        DS 8, 0
go:     add a,a                 ; A = function
        ld e,a
        ld d,0
        ld hl,tab
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)
tab:    DW f_remap, f_fetch, f_result, f_start, f_none, f_save, letter_jump
f_none: xor a
        ret

; ---- the table of choices -------------------------------------------------
ov_init:                        ; a fresh table if it has never been used
        ld hl,OV_MAG
        ld de,s_ovmag
        ld b,4
.c:     ld a,(de)
        cp (hl)
        jr nz,.new
        inc hl
        inc de
        djnz .c
        ret
.new:   ld hl,s_ovmag
        ld de,OV_MAG
        ld bc,4
        ldir
        xor a
        ld (de),a               ; count 0
        ret
s_ovmag:    DB "OV01"

ov_find:                        ; HL = u32 hash -> Z and DE = its entry if there is one
        push hl
        call ov_init
        pop hl
        ld de,OV_TAB
        ld a,(OV_N)
        or a
        jr z,.none
        ld b,a
.l:     push bc
        push hl
        push de
        ld b,4
.c:     ld a,(de)
        cp (hl)
        jr nz,.ne
        inc hl
        inc de
        djnz .c
.ne:    pop de
        pop hl
        pop bc
        ret z
        push hl
        ld hl,10
        add hl,de
        ex de,hl
        pop hl
        djnz .l
        ret                     ; (NZ from the last compare)
.none:  inc a
        ret

; ---- 0: the picture chosen for slot G_K's entry -------------------------------
f_remap:
        ld a,(W_SRC)
        cp 3
        ret z                   ; choosing: every picture as itself
        call orig_ptr
        ex de,hl                ; DE = O_ORIG[k]
        call hash_ptr           ; HL = the slot's hash
        push hl
        ld bc,4
        ldir                    ; O_ORIG[k] = the entry's own hash
        pop hl
        push hl
        call ov_find
        pop hl
        jr nz,.no
        ex de,hl                ; HL = entry
        inc hl
        inc hl
        inc hl
        inc hl
        ex de,hl                ; DE = the picture's hash, HL = slot hash
        push de
        push hl
        ex de,hl
        ld bc,4
        ldir                    ; slot hash = the picture's
        pop hl
        pop de
        call map_ptr
        ex de,hl                ; DE = O_MAP[k], HL = picture hash
        ld bc,4
        ldir
        ret
.no:    call map_ptr            ; not remapped
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        ret

orig_ptr:                       ; HL = O_ORIG + 4*G_K
        ld hl,O_ORIG
        jr k4
map_ptr:                        ; HL = O_MAP + 4*G_K
        ld hl,O_MAP
k4:     ld a,(G_K)
        add a,a
        add a,a
        add a,l
        ld l,a
        ret                     ; (no carry: $9F10-$9F2F)

; ---- 5: leaving the wheel: the centre entry and its place -----------------
f_save:
        ld a,(W_SRC)
        cp 3
        ret z
        ld hl,(G_SEL)
        ld (O_SEL),hl
        ld a,(W_S)
        ld (G_K),a
        call hash_ptr           ; the slot's hash, or its own if it was remapped
        push hl
        call map_ptr
        pop de                  ; DE = slot hash, HL = O_MAP[k]
        push de
        ld b,4
.c:     ld a,(de)
        cp (hl)
        jr nz,.own
        inc hl
        inc de
        djnz .c
        pop de
        call orig_ptr           ; remapped: the entry's own hash is kept here
        jr .cp
.own:   pop hl                  ; not remapped: the slot's hash is the entry's
.cp:    ld de,O_TGT
        ld bc,4
        ldir
        ret

; ---- 3: Change Picture: whose, and the list of pictures ----------------------
f_start:
        ld a,(G_MAGIC)
        cp LIST_MAGIC
        ld a,0
        jr nz,.wh
        ld l,(ix+B_SEL_LO)      ; List View: the entry under the cursor
        ld h,(ix+B_SEL_HI)
        ld (G_IDX),hl
        ld (O_SEL),hl
        xor a
        ld (G_K),a
        call fetch_tab
        or a
        jr nz,.fail
        call hash_ptr
        ld de,O_TGT
        ld bc,4
        ldir
        ld a,1
.wh:    ld (O_LIST),a
        call load_header
        ld a,(G_PACKOK)
        or a
        jr z,.fail
        ld hl,s_lib             ; the picture list
        call hash_name
        xor a
        ld (G_K),a
        call hash_ptr
        ex de,hl
        ld hl,G_H
        ld bc,4
        ldir
        call pack_find
        jr z,.fail
        ld (O_LSEC),de
        call goto_sector
        or a
        jr nz,.fail
        ld hl,(G_BUF)
        ld de,4
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (O_LN),de
        inc de                  ; + the entry's own picture
        ld (G_COUNT),de
        ld hl,O_TGT             ; start at the picture chosen last time
        call ov_find
        ld hl,0
        jr nz,.s0
        ex de,hl
        ld de,8
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        ld de,(G_COUNT)         ; (a newer pack may have fewer pictures)
        or a
        sbc hl,de
        add hl,de
        jr c,.s0
        ld hl,0
.s0:    ld (G_SEL),hl
        ld a,3
        ld (W_SRC),a
        or a                    ; NZ: go
        ret
.fail:  xor a
        ld (G_RES),a
        ret
s_lib:      DB "Library",0

; ---- 1: entry G_IDX of the picture wheel -> slot G_K --------------------------
f_fetch:
        ld hl,(G_IDX)
        ld a,h
        or l
        jr nz,.lib
        ld de,s_orig            ; 0: the entry's own picture
        ld hl,O_TGT
        jr .put
.lib:   dec hl
        push hl
        call load_header
        pop hl
        ld a,(G_PACKOK)
        or a
        jr z,.err
        ld a,l
        and 7
        push af
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        inc hl                  ; after the header sector
        ld de,(O_LSEC)
        add hl,de
        ex de,hl
        call goto_sector
        pop bc                  ; B = entry in the sector
        or a
        jr nz,.err
        ld hl,(G_BUF)
        ld de,64
        inc b
.e:     dec b
        jr z,.at
        add hl,de
        jr .e
.at:    ld d,h                  ; DE = name, HL = hash
        ld e,l
        inc de
        inc de
        inc de
        inc de
.put:   push de                 ; HL = u32 hash, DE = name
        push hl
        call hash_ptr
        ex de,hl
        pop hl
        ld bc,4
        ldir
        ld a,(G_K)
        call name_ptr
        ex de,hl
        pop hl
        ld b,59
.n:     ld a,(hl)
        ld (de),a
        or a
        ret z                   ; A = 0: no error
        inc hl
        inc de
        djnz .n
        xor a
        ld (de),a
        ret
.err:   ld a,1
        ret
s_orig:     DB "Its own picture",0

; ---- 2: the choice -------------------------------------------------------------
f_result:
        ld a,(G_RES)
        dec a
        jr nz,.back             ; 2 or Start: leave it as it was
        ld hl,O_TGT
        call ov_find            ; Z: DE = its entry
        push af
        ld hl,(G_SEL)
        ld a,h
        or l
        jr z,.own
        pop af
        jr z,.have
        ld a,(OV_N)             ; a new entry at the end
        cp OV_MAX
        jr nc,.back
        ld l,a
        inc a
        ld (OV_N),a
        ld h,0
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        add hl,hl               ; *10
        ld de,OV_TAB
        add hl,de
        ex de,hl
        ld hl,O_TGT
        push de
        ld bc,4
        ldir
        pop de
.have:  ld hl,4                 ; DE = entry: the picture's hash and number
        add hl,de
        ex de,hl
        ld a,(W_S)
        ld (G_K),a
        call hash_ptr           ; the centre slot: the chosen picture
        ld bc,4
        ldir
        ld hl,(G_SEL)
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        jr .back
.own:   pop af                  ; its own picture: forget the choice
        jr nz,.back
        ld a,(OV_N)             ; the last entry takes its place
        dec a
        ld (OV_N),a
        ld l,a
        ld h,0
        ld b,h
        ld c,l
        add hl,hl
        add hl,hl
        add hl,bc
        add hl,hl
        ld bc,OV_TAB
        add hl,bc               ; HL = last entry
        ld bc,10
        ldir
.back:  xor a                   ; back to the folder
        ld (W_SRC),a
        ld hl,(O_SEL)
        ld (G_SEL),hl
        ld hl,(ENT_COUNT)
        ld (G_COUNT),hl
        ld a,(O_LIST)
        or a
        jr nz,.list
        inc a                   ; NZ: the wheel
        ret
.list:  xor a                   ; Z: the list
        ld (G_RES),a
        ret

; ---- 6: Jump To Letter (was in the OS) -------------------------------------------
        INCLUDE "ovl_letter.inc"
s_search:   DB "Searching...",0

ovl_end:
        ASSERT ovl_end <= O_TGT, "the overlay is too big"
        DISPLAY "overlay: ", /D, ovl_end - $9800, " bytes"
