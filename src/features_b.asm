; ============================================================================
; Build 4 features, part B (in the free space after the grid code)
;   quick menu on Start, the "recently played" hook, small helpers, strings
; ============================================================================

MENU        EQU $61BE   ; (items**, u16 0) -> L = chosen item (0..), other = cancelled
ROM_MENU    EQU $4058   ; (rec*) the ROM file menu: Load And Start / Load Only / Favourite
LOAD_ROM    EQU $47E0   ; (rec*) write the ROM to flash
WAIT_KEY    EQU $59F1   ; wait for release, then a press

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
        call letter_jump
        jr .back
.n1:    dec a
        jr nz,.n2
        ld hl,REC_BASE
        ld b,REC_MAX
        ld de,s_recent
        call show_list
        jr .back
.n2:    dec a
        jr nz,.back
        ld hl,FAV_BASE
        ld b,FAV_MAX
        ld de,s_favs
        call show_list
.back:  ld (ix+B_REDRAW),1      ; the browser redraws the list
        xor a
        ld (KEYS),a
        ret

; ---- replaces both "call LOAD_ROM" in the ROM menu: remember the game --------
rec_hook:
        ld hl,2
        add hl,sp
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl                ; HL = rec
        call recent_add
        jp LOAD_ROM             ; same stack as the original call

ret_zero:                       ; .txt files used to open the hex viewer
        ld l,0
        ret

; ---- save memory (bank 1, after the OS settings) ----------------------------
sram_on:
        ld a,$0C                ; SRAM bank 1 in slot 2 (as the OS's sram_map_on(1))
        ld (MAP_CTRL),a
        ret

sram_off:
        ld a,$02                ; back to the OS's normal mapping
        ld (MAP_CTRL),a
        ret

MAP_CTRL    EQU $FFFC

qm_items:   DW s_quick, s_q_wheel, s_q_grid, s_q_letter, s_recent, s_favs, 0
s_quick:    DB "Quick Menu",0
s_q_grid:   DB "List View",0
s_q_letter: DB "Jump To Letter",0
s_recent:   DB "Recently Played",0
s_favs:     DB "Favourites",0
s_fav:      DB "Favourite",0
