; ============================================================================
; Wheel view, part C (in the space of the OS's USB loaders, $50A3-$5253)
;   pack format 2: per thumbnail 5 sectors = 72 tiles (2304 bytes), a 20x7
;   map (140 bytes: 0 = empty, else tile 1-72, +$80 = palette 1), the
;   picture's box x0,y0,x1,y1 (4 bytes) and "GTH2" at the end.
; ============================================================================

thumb_nametable:                ; map at buf+256 -> slot rows (window columns 0-19)
        ld hl,(G_BUF)
        inc h
        ld (G_VRAM),hl          ; map pointer
        ld c,0
.r:     push bc
        ld b,0
        ld a,(G_ROW)
        add a,c
        ld c,a
        call nt_addr
        pop bc
        ld b,20
.c:     push bc
        push hl
        ld hl,(G_VRAM)
        ld a,(hl)
        inc hl
        ld (G_VRAM),hl
        pop hl
        ld de,0                 ; empty: tile 0
        or a
        jr z,.e
        ld c,a
        and $7F
        dec a
        ld e,a
        push hl
        ld hl,(G_TILE)
        add hl,de
        ex de,hl                ; DE = tile
        pop hl
        ld a,c
        and $80
        rrca
        rrca
        rrca
        rrca                    ; $08 = palette 1
        or d                    ; + tile bit 8
        ld d,a
.e:     ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        pop bc
        djnz .c
        inc c
        ld a,c
        cp 7
        jr nz,.r
        ld hl,(G_VRAM)          ; the box follows the map
        jr box_set

box_default:                    ; no picture: the frame goes round the 64x56 text box
        ld hl,def_box
box_set:                        ; HL = 4 bytes -> W_BOX[G_K]
        ld a,(G_K)
        add a,a
        add a,a
        add a,W_BOX & $FF
        ld e,a
        ld d,W_BOX >> 8
        ld bc,4
        ldir
        ret

frame_set:                      ; the 4 corner sprites round the centre picture
        ld a,(W_S)
        add a,a
        add a,a
        add a,W_BOX & $FF
        ld l,a
        ld h,W_BOX >> 8
        ld a,(hl)               ; x0
        add a,48
        ld (G_STR+4),a
        ld (G_STR+8),a
        inc hl
        ld a,(hl)               ; y0 (the slot starts at screen y 32 = sprite y 55)
        add a,55
        ld (G_STR),a
        ld (G_STR+1),a
        inc hl
        ld a,(hl)               ; x1
        add a,40
        ld (G_STR+6),a
        ld (G_STR+10),a
        inc hl
        ld a,(hl)               ; y1
        add a,47
        ld (G_STR+2),a
        ld (G_STR+3),a
        ld hl,G_STR+5
        ld a,1                  ; tiles 1-4
.t:     ld (hl),a
        inc hl
        inc hl
        inc a
        cp 5
        jr nz,.t
        ld hl,G_STR             ; screen is on: vram_copy spaces the writes
        ld de,$3F00
        ld bc,4
        call vram_copy
        ld hl,G_STR+4
        ld de,$3F80
        ld bc,8
        jp vram_copy

def_box:    DB 48,0,112,56

wheel_fill:                     ; centre, below + the banner (it sits on that slot),
        xor a                   ; above, then the hidden one ahead
        call ensure_rel
        ld a,1
        call ensure_rel
        call bar_on
        ld a,-1
        call ensure_rel
        ld a,(W_DIR)
        add a,a
        jp ensure_rel

held:                           ; NZ if the direction of W_DIR is still held
        ld a,(W_DIR)
        ld b,a
        in a,($DC)
        cpl
        bit 7,b
        jr nz,.u
        and 2                   ; down
        ret
.u:     and 1                   ; up
        ret

wheel_textbox:                  ; no picture (or scrolling fast): the tidied name,
        ld a,(G_K)              ; centred, up to 3 lines from the slot's row 2
        call name_ptr
        call make_title
        xor a
        ld (G_ATTR),a
        ld a,(G_ROW)
        inc a
        ld c,a
        inc c
        ld hl,W_TMP
        ld b,3
.l:     push bc
        push hl
        call wrap1              ; B = length, HL = next line
        pop de                  ; DE = this line
        ex (sp),hl              ; HL = lines/row, (sp) = next line
        push hl
        ld c,l
        ld a,b
        call bar_text
        pop bc
        pop hl
        inc c
        ld a,(hl)
        or a
        ret z
        djnz .l
        ret

; ---- what the wheel leaves out (called by the OS's folder loader per entry) --
; IX = the loader's frame: (ix-12/-11) -> the 32-byte directory entry,
; (ix-10) = its attributes. Z = keep. DE and BC must survive.
dir_filter:
        ld a,(ix-10)            ; the OS's own rule: hidden files, volume labels
        and 10
        ret nz
        ld a,(W_FILT)
        or a
        ret z                   ; path look-ups (/SAVE, /THUMBS...) and List View: everything
        bit 2,(ix-10)           ; the wheel also leaves out "system" entries
        ret nz
        push bc
        push de
        ld l,(ix-12)
        ld h,(ix-11)
        bit 4,(ix-10)
        jr nz,.dir
        ld de,8                 ; a file: games only
        add hl,de
        ld b,3
        ld de,rom_exts
        call match_list
        jr .out
.dir:   ld b,11                 ; a folder: not the system ones
        ld de,sys_dirs
        call match_list
        jr z,.hide
        xor a
        jr .out
.hide:  or 1
.out:   pop de
        pop bc
        ret


rom_exts:   DB "GG ","SMS","SG ","SC ","BIN",0
sys_dirs:   DB "THUMBS     ","SAVE       ","SAVES      ","EDGG       ","SYSTEM~1   ",0

s_splash:   DB "Splash",0
s_none:     DB 0
