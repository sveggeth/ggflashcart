; ============================================================================
; Start-up picture and sound (build 16), in the main free space
;   picture: thumbs.pak entry "Splash" (a 144x56 thumbnail), shown centred
;   sound:   thumbs.pak entry "Sound": "SND1", u16 bytes, u16 rate, 8 spare,
;            then 4-bit samples (2 per byte, high nibble first) = PSG
;            attenuation values for channel 0, played at 7954 Hz.
;   The sound is copied into save RAM bank 1 at $A000-$BFFF (after the lists)
;   so playback isn't held up by the SD card.
; ============================================================================

W_SPL       EQU $DB8A   ; 1 until the start-up picture has been shown
W_SND       EQU $DB8B   ; a sound is waiting in save RAM
W_ABORT     EQU $DB8C   ; +1/-1: Up/Down stopped the filling in
W_INT       EQU $DB8D   ; the filling in may be stopped
W_PREV      EQU $DB8E   ; Up/Down bits a frame ago
W_SKIP      EQU $DB8F   ; quick steps left in a Left/Right skip
SND_RAM     EQU $A000
OVL_RAM     EQU $9800   ; the overlay (ovl.asm): header, then code from $9810
OVL_GO      EQU $9810
OVL_BUILD   EQU 21      ; the pack's overlay must be from this build
W_OVL       EQU $DB43   ; the overlay is loaded
G_DST       EQU $DB44   ; u16 load_rec's destination

splash:
        xor a
        ld (W_SPL),a
        ld (W_FAST),a           ; (not set yet at power-on)
        ld a,(G_HASPACK)
        or a
        ret z
        call display_off
        call CLEAR_NT
        ld hl,NT_SHADOW
        ld bc,$0700
        call row_flush
        ld a,156                ; slot 0 centred: screen y 44-99
        call out_vs
        ld a,2
        ld (W_SRC),a
        xor a
        ld (G_K),a
        ld h,a
        ld l,a
        ld (G_IDX),hl
        call load_slot
        xor a
        ld (W_SRC),a
        call sound_load
        ld hl,G_HAVE            ; a picture: show it
        call get_k
        or a
        call nz,display_on
        call sound_play
        call ovl_load           ; (while the picture is up)
        ld b,10                 ; then a moment more (1.5 s if there's no sound)
        ld a,(W_SND)
        or a
        jr nz,wait_frames
        ld b,70
wait_frames:                    ; B frames
        push bc
        call VBLANK
        pop bc
        djnz wait_frames
        ret

sound_load:                     ; "Sound" from the pack -> save RAM; W_SND = 1 if found
        ld hl,s_sound
        ld de,SND_RAM
        call load_rec
        ld (W_SND),a
        ret

ovl_load:                       ; "Overlay" -> save RAM $9800; W_OVL = 1 if it's this build's
        ld hl,s_ovl
        ld de,OVL_RAM
        call load_rec
        or a
        ret z
        call sram_on
        ld hl,(OVL_RAM+6)
        call sram_off
        ld de,OVL_BUILD
        or a
        sbc hl,de
        ret nz
        inc a                   ; (A = 2 after sram_off)
        ld (W_OVL),a
        ret

load_rec:                       ; HL = name, DE = save RAM address: the record is copied
        ld (G_DST),de           ; there (header too); A = 1 if found
        push hl
        call load_header        ; rewind (the palette is already set)
        pop hl
        ld a,(G_PACKOK)
        or a
        ret z
        call hash_name
        call hash_ptr
        ex de,hl
        ld hl,G_H
        ld bc,4
        ldir
        call pack_find
        ret z
        call goto_sector        ; header sector -> G_BUF
        or a
        jr nz,.no
        ld hl,(G_BUF)
        ld de,4
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (G_N),de             ; sample bytes after the 16-byte header
        ld hl,16+511
        add hl,de
        ld a,h
        srl a
        ld b,a                  ; sectors (the converter keeps it to 16)
        ld hl,(G_DST)
.s:     push bc
        push hl
        ex de,hl
        call sram_on
        ld hl,(G_BUF)
        ld bc,512
        ldir
        call sram_off
        pop hl
        inc h
        inc h                   ; +512
        pop bc
        dec b
        jr z,.ok
        push bc
        push hl
        call read_sector        ; the next sector of the pack
        pop hl
        pop bc
        or a
        jr z,.s
.no:    xor a
        ret
.ok:    ld a,1
        ret


pad_new:                        ; A = Up/Down bits pressed since the last look (bit 0 up,
        in a,($DC)              ; bit 1 down), Z if none: only a new press counts,
        cpl                     ; not a button that is still being held
        and 3
        ld hl,W_PREV
        ld c,(hl)
        ld (hl),a
        ld b,a
        ld a,c
        cpl
        and b
        ret

box_default:                    ; no picture: the frame goes round the 64x56 text box
        ld hl,def_box
        jp box_set
def_box:    DB 48,0,112,56

abort_dir:                      ; A = Up/Down bits -> W_ABORT = +1 (down) / -1 (up)
        and 2
        ld a,1
        jr nz,.s
        ld a,-1
.s:     ld (W_ABORT),a
        ret
