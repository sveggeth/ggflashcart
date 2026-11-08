; ============================================================================
; Wheel view, part D (in the space of the OS's About screen, $4483-$465A;
; "About" is gone from the OS's main menu, Start Game and Device Info stay)
;
; Favourites as a wheel: at the root the wheel gets one more entry,
; "Favourites", after the folders. Opening it fills the wheel from the
; favourites list instead of the folder; 1 gives a game's file menu, 2 goes
; back to the root, Start leaves for the list + quick menu.
; ============================================================================

W_SRC       EQU $DB88   ; 0 = folder, 1 = favourites
W_VFAV      EQU $DB89   ; the root wheel has the extra Favourites entry

root_fav:                       ; at the root (with favourites): one more entry
        xor a
        ld (W_VFAV),a
        ld a,(ix-$1b)           ; the browser's folder depth
        or (ix-$1c)
        ret nz
        call fav_count
        or a
        ret z
        ld a,1
        ld (W_VFAV),a
        ld hl,(ENT_COUNT)
        inc hl
        ld (G_COUNT),hl
        ret

fav_count:                      ; -> A = favourites in use (the list is kept packed)
        call sram_on
        call lists_init
        ld hl,FAV_BASE+4
        ld de,32
        ld bc,FAV_MAX*256
.l:     ld a,(hl)
        or a
        jr z,.e
        inc c
        add hl,de
        djnz .l
.e:     call sram_off
        ld a,c
        ret

; ---- wheel entries: the folder's, the extra one, or the favourites' --------
fetch_entry:                    ; entry G_IDX -> name cache, dir flag, hash; A = err
        ld a,(W_SRC)
        cp 2
        jr z,.spl               ; the start-up picture
        cp 3
        jr z,.lib               ; Change Picture: the pack's pictures
        or a
        jr nz,.fav
        ld a,(W_VFAV)
        or a
        jp z,fetch_tab
        ld hl,(G_IDX)
        ld de,(ENT_COUNT)
        or a
        sbc hl,de
        jp nz,fetch_tab
        ld a,1                  ; the extra entry: a "folder" called Favourites
        ld hl,G_ISDIR
        call put_k
        ld hl,s_favs            ; its art (if any) is filed under "Favourites"
.virt:  push hl
        ld a,(G_K)
        call name_ptr
        ex de,hl
        pop hl
        push hl
        ld bc,11
        ldir
        pop hl
        call hash_name
        call hash_ptr
        ex de,hl
        ld hl,G_H
        ld bc,4
        ldir
        xor a
        ret
.spl:   ld hl,s_splash          ; filed under "Splash" in thumbs.pak
        jr .virt
.lib:   ld a,1
        jp ovl_call
.fav:   call sram_on            ; directory position from the favourites list
        ld hl,(G_IDX)
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,FAV_BASE
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        call sram_off
        jp fetch_tab.pos

; ---- 1 / 2 / Start in the wheel ---------------------------------------------
fav_res:                        ; G_RES: 0 Start, 1 open, 2 back
        ld a,(W_SRC)
        or a
        jr nz,.in
        ld a,(G_RES)            ; at the root: opening the Favourites entry?
        dec a
        jp nz,wheel_exit
        ld a,(W_VFAV)
        or a
        jp z,wheel_exit
        ld hl,(G_SEL)
        ld de,(ENT_COUNT)
        or a
        sbc hl,de
        jp nz,wheel_exit
        ld a,1
        ld (W_SRC),a
        call fav_count
        ld l,a
        ld h,0
        ld (G_COUNT),hl
        ld hl,0
        ld (G_SEL),hl
        jp wheel_start
.in:    ld a,(W_SRC)
        cp 3
        jr nz,.f
        ld a,2                  ; a picture chosen (or not): back where we were
        call ovl_call
        jp z,wheel_exit         ; (to the list, if it was opened from there)
        call root_fav
        jp wheel_start
.f:     ld a,(G_RES)
        or a
        jr z,.st
        dec a
        jr z,.open
.root:  xor a                   ; 2 (or no favourites left): back to the root wheel
        ld (W_SRC),a
        ld hl,(ENT_COUNT)
        ld (G_COUNT),hl
        dec hl
        ld (G_SEL),hl
        call root_fav
        ld a,(W_VFAV)
        or a
        jr z,.r1
        ld hl,(ENT_COUNT)       ; on the Favourites entry
        ld (G_SEL),hl
.r1:    jp wheel_start
.st:    xor a                   ; Start: the root's list and the quick menu
        ld (W_SRC),a
        ld h,a
        ld l,a
        ld (G_SEL),hl
        jp wheel_exit
.open:  call wheel_clean        ; the game's file menu, then back to this wheel
        call restore_video
        call CLEAR_NT
        call FLUSH_NT
        ld a,(W_S)
        ld (G_K),a
        call fetch_entry
        or a
        jr nz,.back
        ld hl,(G_REC)
        push hl
        call ROM_MENU
        pop af
.back:  call fav_count          ; the game may have been taken off the list
        or a
        jr z,.root
        ld l,a
        ld h,0
        ld (G_COUNT),hl
        call sel_clamp_c
        ld hl,OS_PALETTE
        call write_palette
        xor a
        ld (W_PAL),a
        jp wheel_start

sel_clamp:                      ; G_SEL < ENT_COUNT (for the browser)
        ld de,(ENT_COUNT)
        jr sel_c
sel_clamp_c:                    ; G_SEL < G_COUNT
        ld de,(G_COUNT)
sel_c:  ld hl,(G_SEL)
        or a
        sbc hl,de
        ret c
        ex de,hl
        ld a,h
        or l
        jr z,.z
        dec hl
.z:     ld (G_SEL),hl
        ret

wheel_exit:
        ld a,5                  ; remember the centre entry (for Change Picture)
        call ovl_call
        call wheel_clean
        jp view_exit

wheel_clean:                    ; sprites off, scroll 0, tiles 1-16 blank again
        call blank_off
        ld de,$3F00
        call vaddr
        ld a,$D0
        out ($BE),a
        ld de,$0020             ; (the OS's menu box uses them)
        call vaddr
        ld b,0
        xor a
.clr:   out ($BE),a
        out ($BE),a
        djnz .clr
        jp out_vs


vs_tab:     DB 168,0,56,112          ; centre art at screen y 32-87, banner y 120-143
