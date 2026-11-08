; ============================================================================
; Thumbnail grid browser for EverDrive GG OS v9  ->  builds os-v9-grid.mso
;
;   sjasmplus gridpatch.asm        (needs os-v9.mso next to this file)
;
; Patch points:
;   $0200  version byte $09 -> $18 (Device Info shows 24; build 15)
;   messages wider than the screen (20 characters) shortened in place (build 15)
;   $3F2B  os_init: "OS init..." -> no text (a start-up picture follows from thumbs.pak)
;   $4301  main menu: no "About" item; $4483-$465A (the About screen) holds wheel code
;   $07A8  browser_main: "call fn_180E" (load folder) -> "call load_dir_hook"
;   $1A5C  folder loader: "ld a,(ix-10) / and 10 / jr z" -> "call dir_filter / jr z" (wheel hides system entries)
;   $4003  usb_poll -> ret (the Flash Gear has no USB); $50A3-$5253 (the USB loaders) reused
;   $0090  name banner + title tidying, in the unused padding after the EDOS header
;   $6492  Hex View replaced by favourites / recently played / jump-to-letter (features_a.asm)
;   $7C00  font characters $20-$7F replaced with unscii-8-alt (public domain, viznut)
;   $07DC  browser_main: "call fn_59F1" (wait for key) -> "call grid_hook"
;   $3EEA  main: "call browser_main" -> "call boot_hook" (wheel on at boot)
;   $07C6  browser_main: "call dir_browser" -> "call dir_hook" (skipped while dark)
;   $5DCA  show_error: "call clear_screen" -> "call err_hook" (display back on)
;   $70EC  new code, in the OS's free space ($70EC-$7BFF)
; Nothing in the hardware layer ($0201-$0762) or the update code is touched.
;
; The file browser opens in a wheel of box art / wheel art read from
; /THUMBS/thumbs.pak (made by make_thumbs.py):  Up/Down scroll, 1 open,
; 2 back, Start = list + quick menu (Wheel View, List View, Jump To Letter,
; Recently Played, Favourites).
;
; thumbs.pak layout (512-byte sectors):
;   0        header: "GTPK", u16 count, u16 K (index sectors, power of 2),
;            u16 first data sector, palette (64 bytes) at offset 64
;   1..K     index buckets, bucket = hash & (K-1): u16 n, then at offset 8
;            n entries of {u32 hash, u16 data sector, u16 0}
;   data     4 sectors per thumbnail: 56 tiles (1792 bytes), 56 palette
;            flags, "GTH1"
;   hash     djb2 (h = h*33 + c, start 5381) over the lower-cased file name
;            without its extension
; Opening the pack makes the OS walk /THUMBS, which reloads its entry table,
; so after every page we reload the browser's folder with the OS's own loader.
; ============================================================================

        DEVICE NOSLOT64K
        ORG $0000
        INCBIN "os-v9.mso"

; ---- OS routines (SDCC calling convention: args on stack, result in L/HL) ---
WAIT_INPUT  EQU $5A00   ; -> HL = keys ($C17A), with the OS's auto-repeat
ALLOC       EQU $425D   ; (u16 size) -> HL ptr   (stack allocator, LIFO)
FREE        EQU $429C   ; (u16 size)
READ_ENTRY  EQU $1CDF   ; (u32 entry pos, rec*) -> L err; name at rec+0, dir flag rec+$E4
FOPEN       EQU $2669   ; (path*, rec*, u16 0) -> L err ($F0 = not found); file at sector 0
FREAD       EQU $23C6   ; (buf*, u16 sectors, u8 1=RAM) -> L err, reads the open file
FSKIP       EQU $2319   ; (u16 sectors) -> L err, skips forward in the open file
FSEEK0      EQU $213F   ; (rec*, u16 0) -> L err: reopen a file record at sector 0
LOAD_DIR    EQU $180E   ; (u32 folder) -> L err, the browser's folder loader
FONT_LOAD   EQU $5A58   ; (font*)  rebuilds the 3 coloured font copies
CRAM_WRITE  EQU $0665   ; (src*, u16 $4000 = 64 bytes from colour 0)
CLEAR_NT    EQU $5C0F   ; clear name-table shadow $D309-$DA08
FLUSH_NT    EQU $0714   ; copy shadow -> VRAM $3800 (vblank-synchronised)
DIR_BROWSER EQU $5E49   ; (u8 redraw, u16 selection)

; ---- OS variables ------------------------------------------------------------
ENT_COUNT   EQU $C157   ; u16 entries in current folder
ENT_TABLE   EQU $C15E   ; ptr to u32 entry positions
KEYS        EQU $C17A   ; key byte the browser acts on
NT_SHADOW   EQU $D309   ; 32x28 name-table shadow, 2 bytes per entry
OS_PALETTE  EQU $5963   ; GG palette table used by video_init
OS_FONT     EQU $7C00
; browser_main locals (IX = its frame while our hook runs)
B_SEL_LO    EQU -$16
B_SEL_HI    EQU -$15
B_REDRAW    EQU -$14
B_FOLDER    EQU -6      ; u32 current folder, argument of LOAD_DIR

; ---- our variables: $DA10-$DAFF is never used by the OS ----------------------
G_MAGIC     EQU $DA10   ; $5A while grid view is switched on
G_SEL       EQU $DA11   ; u16
G_REC       EQU $DA15   ; ptr
G_PREC      EQU $DA17   ; ptr, file record of thumbs.pak
G_BUF       EQU $DA19   ; ptr
G_COUNT     EQU $DA1B   ; u16
G_K         EQU $DA1D   ; cell 0-3
G_IDX       EQU $DA1E   ; u16
G_RES       EQU $DA20   ; 0 list, 1 open, 2 back
G_STPREV    EQU $DA21   ; Start was held
G_ATTR      EQU $DA22
G_SEC       EQU $DA23
G_TILE      EQU $DA24   ; u16 first tile of the cell
G_VRAM      EQU $DA26   ; u16
G_COL       EQU $DA28
G_ROW       EQU $DA29
G_PACKOK    EQU $DA2A
G_HASPACK   EQU $DA3E   ; thumbs.pak was found when the grid opened
G_NEED      EQU $DA2B   ; any cell wants a thumbnail
G_VALID     EQU $DA2C   ; [4]
G_ISDIR     EQU $DA30   ; [4]
G_HAVE      EQU $DA34   ; [4]
G_NUM       EQU $DA38   ; 6-byte decimal buffer
G_NAMES     EQU $DD00   ; [4][64]  ($DD00-$DDFF; the stack stays above $DF00)
NAME_LEN    EQU 64
G_HASHES    EQU $DAC4   ; [4] u32  ($DAC4-$DAD3)
G_H         EQU $DAD4   ; u32 hash work
G_T         EQU $DAD8   ; u32
G_HPTR      EQU $DADC   ; u16
G_HLEN      EQU $DADE
G_PK        EQU $DAE0   ; u16 index sectors
G_POS       EQU $DAE2   ; u16 next sector of the open pack
G_LAST      EQU $DAE4   ; u16 sector now in G_BUF ($FFFF = none)
G_BKT       EQU $DAE6   ; [4] u16 index sector per cell ($FFFF = none)
G_DS        EQU $DAEE   ; [4] u16 data sector per cell ($FFFF = none)
G_STR       EQU $DB00   ; 16-byte text buffer (stack never gets this low)

THUMB_TILE  EQU 160     ; wheel slots: tiles 160-447, 72 each (font copies 2-3 are rebuilt on exit)
W_BOX       EQU $DE40   ; [4] x0,y0,x1,y1 of each slot's picture (for the frame)
LIST_MAGIC  EQU $3C     ; G_MAGIC: list view chosen (anything else = wheel)
W_QM        EQU $DB54   ; open the quick menu on the way back from the wheel
W_HID       EQU $DB55   ; screen left dark / font not rebuilt by the wheel
W_PKOK      EQU $DB56   ; pack: 0 not looked for yet, 1 found, 2 missing
W_DIRS      EQU $DB81   ; [4] slot holds a folder
W_FILT      EQU $DB85   ; the folder loader is filling the browser's list for the wheel
W_RET       EQU $DB86   ; u16
W_PREC      EQU $DC00   ; the pack's file record, kept ($E5 bytes; stack stays above $DF00)

; ============================================================================
        ORG $0200
        DB $18

        ORG $07DC
        call grid_hook

        ORG $3EEA               ; main: the browser starts in the wheel at every boot
        call boot_hook

        ORG $07C6               ; browser_main: no list drawing while the wheel has the screen dark
        call dir_hook

        ORG $5DCA               ; show_error: screen back on first if the wheel hid it
        call err_hook

; ============================================================================
        ORG $70EC
grid_hook:
        ld hl,(ENT_COUNT)
        ld a,h
        or l
        jr z,.list              ; empty folder: plain list
        ld a,(W_QM)
        or a
        jr nz,.qm               ; Start was pressed in the wheel
        ld a,(G_MAGIC)
        cp LIST_MAGIC
        jp nz,wheel_main        ; the wheel unless List View was chosen
.list:  ld a,(W_HID)            ; the wheel left the screen dark: restore it
        or a
        call nz,unhide
.wl:    call WAIT_INPUT         ; same as fn_59F1 (release, then press) + Start
        ld a,h
        or l
        jr nz,.wl
.poll:  call WAIT_INPUT
        ld a,h
        or l
        ret nz                  ; ordinary key: the browser handles it
        in a,($00)
        rla
        jr c,.poll              ; Start not pressed
        jp quick_menu
.qm:    xor a
        ld (W_QM),a
        jp quick_menu

boot_hook:                      ; RAM isn't cleared at power-on
        xor a
        ld (W_QM),a
        ld (W_PKOK),a
        ld (W_FILT),a
        inc a
        ld (W_HID),a            ; no list flash before the wheel
        ld (W_SPL),a            ; start-up picture on the way into the wheel
        call display_off
        ld a,WHEEL_MAGIC
        ld (G_MAGIC),a
        jp $0763                ; browser_main

dir_hook:                       ; draw the list unless the wheel is about to take over
        ld a,(W_HID)
        or a
        jp z,DIR_BROWSER
        ld a,(G_MAGIC)
        cp LIST_MAGIC
        jp z,DIR_BROWSER
        ld hl,(ENT_COUNT)
        ld a,h
        or l
        jp z,DIR_BROWSER        ; empty folder: the list it is
        ld l,0                  ; "no error"
        ret

err_hook:
        ld a,(W_HID)
        or a
        call nz,unhide
        jp CLEAR_NT

unhide:
        xor a
        ld (W_HID),a
        jp restore_video

; ----------------------------------------------------------------------------
view_setup:                     ; shared by the grid and the wheel
        xor a
        ld (G_SATTR),a
        ld (W_PAL),a
        ld hl,(ENT_COUNT)
        ld (G_COUNT),hl
        ld l,(ix+B_SEL_LO)
        ld h,(ix+B_SEL_HI)
        ld (G_SEL),hl
        ld a,1
        ld (G_STPREV),a         ; Start may still be held from the toggle
        ld hl,$00E5
        call alloc_hl
        ld (G_REC),hl
        ld hl,512
        call alloc_hl
        ld (G_BUF),hl
        ld hl,W_PREC            ; the pack's file record is kept between visits
        ld (G_PREC),hl
        ld hl,fallback_pal
        call write_palette
        ld a,(W_PKOK)           ; 0 = not looked yet, 1 = found, 2 = missing
        or a
        jr nz,.known
        call open_pack          ; once per power-on: the path walk reloads the OS
        ld a,l                  ; entry table, so give the browser its folder back
        or a
        ld a,2
        jr nz,.np
        dec a
.np:    ld (W_PKOK),a
        call reload_folder
.known: ld a,(W_PKOK)
        dec a
        ld a,0
        jr nz,.nopk
        inc a
.nopk:  ld (G_HASPACK),a
        ret


view_exit:                      ; G_RES: 0 list, 1 open, 2 back
        ld hl,512
        call free_hl
        ld hl,$00E5
        call free_hl
        call sel_clamp          ; (the root's Favourites entry isn't the browser's)
        ld hl,(G_SEL)
        ld (ix+B_SEL_LO),l
        ld (ix+B_SEL_HI),h
        ld a,(G_RES)
        cp 2
        jr z,.bk                ; back: straight to the parent's wheel
        dec a
        jr nz,.show             ; Start: list + quick menu
        ld a,(W_S)              ; open: a folder goes straight to its wheel,
        ld e,a                  ; a game to its file menu over the list
        ld d,0
        ld hl,W_DIRS
        add hl,de
        ld a,(hl)
        or a
        jr z,.show
        jr .hide
.bk:    ld a,(ix-$1b)           ; 2 at the root opens the OS's main menu: show it
        or (ix-$1c)
        jr z,.show
.hide:  ld a,1                  ; screen stays dark, font not rebuilt: the
        ld (W_HID),a            ; browser just presses the key for us
        ld (ix+B_REDRAW),0
        ld a,(G_RES)
        add a,a
        add a,a
        add a,a
        add a,a                 ; 1 -> $10, 2 -> $20
        ld (KEYS),a
        ret
.show:  call restore_video
        ld a,(G_RES)
        cp 1
        jr z,view_open
        ld (ix+B_REDRAW),1      ; list will be redrawn by the browser
        add a,a
        add a,a
        add a,a
        add a,a                 ; 0 -> 0, 2 -> $20 (main menu)
        ld (KEYS),a
        ret
view_open:
        ld hl,(G_SEL)           ; draw the list first, then press "1" for the user
        push hl
        ld a,1
        push af
        inc sp
        call DIR_BROWSER
        inc sp
        pop hl
        ld (ix+B_REDRAW),0
        ld a,$10
        ld (KEYS),a
        ret

; ----------------------------------------------------------------------------
grid_wait:                      ; release, then press; Start reported as $80
.rel:   call WAIT_INPUT
        ld a,l
        or a
        jr nz,.rel
.prs:   in a,($00)
        and $80
        jr nz,.up
        ld a,(G_STPREV)
        or a
        jr nz,.pad
        ld a,1
        ld (G_STPREV),a
        ld a,$80
        ret
.up:    xor a
        ld (G_STPREV),a
.pad:   call WAIT_INPUT
        ld a,l
        or a
        jr z,.prs
        ret

; ----------------------------------------------------------------------------
alloc_hl:
        push hl
        call ALLOC
        pop af
        ret

free_hl:
        push hl
        call FREE
        pop af
        ret

display_off:
        xor a
        out ($BF),a
        ld a,$81
        out ($BF),a
        ret

display_on:
        ld a,$40
        out ($BF),a
        ld a,$81
        out ($BF),a
        ret

restore_video:
        call display_off
        ld hl,OS_FONT
        push hl
        call FONT_LOAD
        pop af
        ld hl,$4000
        push hl
        ld hl,OS_PALETTE
        push hl
        call CRAM_WRITE
        pop af
        pop af
        ld a,2                  ; the OS's backdrop colour again
        out ($BF),a
        ld a,$87
        out ($BF),a
        call display_on
        ret

write_palette:                  ; HL = 64 bytes; then force the text colours
        xor a
        out ($BF),a
        ld a,$C0
        out ($BF),a
        ld b,64
.c:     ld a,(hl)
        out ($BE),a
        inc hl
        djnz .c
        xor a                   ; colour 0/1 = black/white
        out ($BF),a
        ld a,$C0
        out ($BF),a
        ld hl,fixed_pal
        ld b,4
.f:     ld a,(hl)
        out ($BE),a
        inc hl
        djnz .f
        ld a,32                 ; colour 16 = black (background of highlighted text),
        out ($BF),a             ; colour 17 = yellow (selection)
        ld a,$C0
        out ($BF),a
        xor a
        out ($BE),a
        out ($BE),a
        ld a,$FF
        out ($BE),a
        xor a
        out ($BE),a
        out ($BF),a             ; backdrop (shown while the screen is off) =
        ld a,$87                ; colour 16, always black here; the OS uses 18,
        out ($BF),a             ; which the art palette may make white
        ret

; ---- file helpers ------------------------------------------------------------
read_sector:                    ; one sector of the open file -> G_BUF; A = err
        ld a,1
        push af
        inc sp
        ld hl,1
        push hl
        ld hl,(G_BUF)
        push hl
        call FREAD
        pop af
        pop af
        inc sp
        ld a,l
        ret

skip_hl:                        ; skip HL sectors; A = err
        ld a,h
        or l
        ret z
        push hl
        call FSKIP
        pop af
        ld a,l
        ret

open_pack:                      ; L = err; record in G_PREC
        ld hl,s_packfile_uc     ; Mac/Windows store "thumbs.pak" as 8.3 only; the OS then
        call open_path          ; calls it "THUMBS  PAK" and compares names exactly
        ld a,l
        or a
        ret z
        ld hl,s_packfile
open_path:                      ; HL = path -> L = err
        ld de,0
        push de
        ld de,(G_PREC)
        push de
        push hl
        call FOPEN
        pop af
        pop af
        pop af
        ret

rewind_pack:                    ; A = err; the pack's record -> sector 0, no path walk
        ld a,(G_HASPACK)
        or a
        ld a,1
        ret z
        ld hl,0
        push hl
        ld hl,(G_PREC)
        push hl
        call FSEEK0
        pop af
        pop af
        ld a,l
        ret

reload_folder:                  ; give the browser its entry table back
        ld l,(ix+B_FOLDER+2)
        ld h,(ix+B_FOLDER+3)
        push hl
        ld l,(ix+B_FOLDER)
        ld h,(ix+B_FOLDER+1)
        push hl
        call load_dir_hook
        pop af
        pop af
        ret

load_dir_hook:                  ; (u32 folder) -> L: LOAD_DIR, hiding what the wheel
        ld a,(G_MAGIC)          ; leaves out; only for folders the browser shows,
        cp LIST_MAGIC           ; never for path look-ups like /SAVE
        jp z,LOAD_DIR
        ld a,1
        ld (W_FILT),a
        pop hl
        ld (W_RET),hl
        call LOAD_DIR           ; the arguments are where it expects them
        xor a
        ld (W_FILT),a
        ld de,(W_RET)
        push de
        ret

load_header:                    ; open the pack, check it, set the palette
        xor a
        ld (G_PACKOK),a
        call rewind_pack
        or a
        ret nz
        call read_sector
        or a
        ret nz
        ld hl,(G_BUF)
        ld de,s_packmagic
        ld b,4
.m:     ld a,(de)
        cp (hl)
        ret nz
        inc hl
        inc de
        djnz .m
        inc hl                  ; skip count
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (G_PK),de
        ld a,(W_PAL)            ; the palette only once per visit (it never changes,
        or a                    ; and the wheel loads while the screen is on)
        jr nz,.pal
        inc a
        ld (W_PAL),a
        ld hl,(G_BUF)
        ld de,64
        add hl,de
        call write_palette
.pal:
        ld hl,1
        ld (G_POS),hl
        ld hl,0
        ld (G_LAST),hl
        ld a,1
        ld (G_PACKOK),a
        ret

put_k:                          ; (HL + G_K) = A
        push af
        ld a,(G_K)
        add a,l
        ld l,a
        ld a,h
        adc a,0
        ld h,a
        pop af
        ld (hl),a
        ret

get_k:                          ; A = (HL + G_K)
        ld a,(G_K)
        add a,l
        ld l,a
        ld a,h
        adc a,0
        ld h,a
        ld a,(hl)
        ret

hash_ptr:                       ; HL = G_HASHES + 4*G_K
        ld a,(G_K)
        add a,a
        add a,a
        ld hl,G_HASHES
        add a,l
        ld l,a
        ld a,h
        adc a,0
        ld h,a
        ret

cell_origin:                    ; A = slot k -> G_COL 6, G_ROW 7k-3 (rows 7k..7k+6)
        ld b,a
        ld a,6
        ld (G_COL),a
        ld a,b
        add a,a
        add a,a
        add a,a
        sub b
        sub 3
        ld (G_ROW),a
        ret

name_ptr:                       ; A = cell -> HL = G_NAMES + cell*33
        ld hl,G_NAMES
        ld de,NAME_LEN
        or a
        ret z
.l:     add hl,de
        dec a
        jr nz,.l
        ret

fetch_tab:                      ; entry G_IDX of the folder -> name cache, dir flag, hash; A = err
        ld hl,(G_IDX)
        add hl,hl
        add hl,hl
        ld de,(ENT_TABLE)
        add hl,de               ; -> u32 position
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
.pos:   ld hl,(G_REC)           ; (E,D,C,B = directory position)
        push hl
        push bc
        push de
        call READ_ENTRY
        pop af
        pop af
        pop af
        ld a,l
        or a
        ret nz
        ld hl,(G_REC)           ; dir flag
        ld de,$E4
        add hl,de
        ld a,(hl)
        ld hl,G_ISDIR
        call put_k
        ld a,(G_K)              ; copy up to 32 chars of the name
        call name_ptr
        ex de,hl
        ld hl,(G_REC)
        ld b,NAME_LEN-1
.cp:    ld a,(hl)
        ld (de),a
        or a
        jr z,.end
        inc hl
        inc de
        djnz .cp
        xor a
        ld (de),a
.end:   ld hl,(G_REC)
        call hash_name
        call hash_ptr
        ex de,hl
        ld hl,G_H
        ld bc,4
        ldir
        xor a
        ret

hash_name:                      ; HL = name -> G_H = djb2 of lower-case name sans extension
        ld (G_HPTR),hl
        ld b,0                  ; position of the last '.'
        ld c,0                  ; length
.scan:  ld a,(hl)
        or a
        jr z,.sd
        cp '.'
        jr nz,.nd
        ld b,c
.nd:    inc hl
        inc c
        jr nz,.scan
.sd:    ld a,b
        or a
        jr nz,.dot
        ld b,c
.dot:   ld a,b
        ld (G_HLEN),a
        ld hl,5381
        ld (G_H),hl
        ld hl,0
        ld (G_H+2),hl
        ld a,(G_HLEN)
        or a
        ret z
.ch:    ld hl,(G_H)             ; T = H << 5
        ld (G_T),hl
        ld hl,(G_H+2)
        ld (G_T+2),hl
        ld b,5
.sh:    ld hl,G_T
        sla (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        djnz .sh
        ld hl,(G_H)             ; H += T
        ld de,(G_T)
        add hl,de
        ld (G_H),hl
        ld hl,(G_H+2)
        ld de,(G_T+2)
        adc hl,de
        ld (G_H+2),hl
        ld hl,(G_HPTR)          ; H += lower(c)
        ld a,(hl)
        inc hl
        ld (G_HPTR),hl
        cp 'A'
        jr c,.lc
        cp 'Z'+1
        jr nc,.lc
        add a,32
.lc:    ld e,a
        ld d,0
        ld hl,(G_H)
        add hl,de
        ld (G_H),hl
        ld hl,(G_H+2)
        ld e,d
        adc hl,de
        ld (G_H+2),hl
        ld hl,G_HLEN
        dec (hl)
        jr nz,.ch
        ret

; ---- thumbnails from the pack -> VRAM tiles + name table --------------------
; The pack is opened once per page; index sectors and then thumbnails are read
; in ascending sector order, so we only ever skip forwards.
load_thumbs:
        xor a
        ld (G_K),a
.b:     ld de,$FFFF
        ld hl,G_VALID
        call get_k
        or a
        jr z,.bs
        call hash_ptr           ; sector = 1 + (hash & (K-1)); folders too (build 13)
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(G_PK)
        dec hl
        ld a,l
        and e
        ld e,a
        ld a,h
        and d
        ld d,a
        inc de
.bs:    ld hl,G_BKT
        call put16_k
        ld de,$FFFF
        ld hl,G_DS
        call put16_k
        ld hl,G_K
        inc (hl)
        ld a,(hl)
        cp 4
        jr nz,.b
.nb:    ld hl,G_BKT             ; index sectors, lowest first
        call pick_min
        cp $FF
        jr z,.data
        ld (G_K),a
        push de
        ld de,$FFFF
        ld hl,G_BKT
        call put16_k
        pop de
        call goto_sector
        or a
        jr nz,.nb
        call find_hash
        ld hl,G_DS
        call put16_k
        jr .nb
.data:  ld hl,G_DS              ; thumbnails, lowest first
        call pick_min
        cp $FF
        ret z
        ld (G_K),a
        push de
        ld de,$FFFF
        ld hl,G_DS
        call put16_k
        ld a,(G_K)
        call cell_origin
        pop de
        call read_thumb
        ld hl,G_HAVE
        call put_k
        jr .data

put16_k:                        ; (HL + 2*G_K) = DE
        ld a,(G_K)
        add a,a
        add a,l
        ld l,a
        ld a,h
        adc a,0
        ld h,a
        ld (hl),e
        inc hl
        ld (hl),d
        ret

pick_min:                       ; HL = u16[4] -> A = cell with the lowest value, DE = value
        ld a,$FF                ; ($FFFF entries are ignored; A = $FF if all are)
        ld (G_STR),a
        ld bc,$FFFF
        xor a
.l:     push af
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        push hl
        ld h,d
        ld l,e
        or a
        sbc hl,bc
        pop hl
        jr nc,.no
        ld b,d
        ld c,e
        pop af
        push af
        ld (G_STR),a
.no:    pop af
        inc a
        cp 4
        jr nz,.l
        ld d,b
        ld e,c
        ld a,(G_STR)
        ret

goto_sector:                    ; DE = sector -> G_BUF; A = err
        ld hl,(G_LAST)
        or a
        sbc hl,de
        ld a,0
        ret z                   ; already in the buffer
        ld hl,(G_POS)
        ex de,hl                ; HL = target, DE = position
        push hl
        or a
        sbc hl,de
        jr c,.err
        call skip_hl
        or a
        jr nz,.err
        call read_sector
        or a
        jr nz,.err
        pop de
        ld (G_LAST),de
        inc de
        ld (G_POS),de
        xor a
        ret
.err:   pop de
        ld hl,$FFFF
        ld (G_POS),hl
        ld a,1
        ret

find_hash:                      ; bucket in G_BUF -> DE = data sector of cell G_K, or $FFFF
        ld hl,(G_BUF)
        ld b,(hl)               ; n (at most 63)
        ld de,8
        add hl,de
        ld a,b
        or a
        jr z,.none
.f:     push bc
        push hl
        call hash_ptr
        ex de,hl                ; DE = our hash
        pop hl
        push hl
        ld b,4
        ld c,1
.c:     ld a,(de)
        cp (hl)
        jr z,.e
        ld c,0
.e:     inc hl
        inc de
        djnz .c
        ld a,c
        pop hl
        pop bc
        or a
        jr nz,.got
        ld de,8
        add hl,de
        djnz .f
.none:  ld de,$FFFF
        ret
.got:   ld de,4
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ret

read_thumb:                     ; DE = first data sector, cell G_K at G_COL/G_ROW; A = 1 if drawn
        push de
        ld hl,(G_POS)
        ex de,hl
        or a
        sbc hl,de               ; HL = target - position
        pop de
        jp c,.fail
        push de
        call skip_hl
        pop de
        or a
        jp nz,.fail
        ld (G_POS),de
        ld hl,$FFFF
        ld (G_LAST),hl
        ld a,(G_K)              ; first tile = THUMB_TILE + 72*slot, VRAM = tile*32
        ld hl,THUMB_TILE
        ld de,72
        or a
        jr z,.t1
.t0:    add hl,de
        dec a
        jr nz,.t0
.t1:    ld (G_TILE),hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld (G_VRAM),hl
        xor a
        ld (G_SEC),a
.sec:   call read_sector
        or a
        jp nz,.fail
        ld hl,(G_POS)
        inc hl
        ld (G_POS),hl
        ld a,(G_SEC)
        cp 4
        jr z,.last
        ld hl,(G_BUF)
        ld de,(G_VRAM)
        ld bc,512
        call vram_copy
        ld hl,(G_VRAM)
        ld de,512
        add hl,de
        ld (G_VRAM),hl
        ld hl,G_SEC
        inc (hl)
        jr .sec
.last:  ld hl,(G_BUF)           ; magic "GTH2" at offset 508 of the 5th sector
        ld de,508
        add hl,de
        ld de,s_magic
        ld b,4
.m:     ld a,(de)
        cp (hl)
        jr nz,.bad
        inc hl
        inc de
        djnz .m
        ld hl,(G_BUF)
        ld de,(G_VRAM)
        ld bc,256
        call vram_copy
        call thumb_nametable
        ld a,1
        ret
.fail:  ld hl,$FFFF             ; position unknown now: skip the rest
        ld (G_POS),hl
.bad:   xor a
        ret

vram_copy:                      ; HL src, DE VRAM address, BC count (display off)
        ld a,e
        out ($BF),a
        ld a,d
        or $40
        out ($BF),a
.l:     ld a,(hl)
        out ($BE),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.l
        ret

nt_addr:                        ; B = window column, C = window row -> HL
        ld a,c
        add a,3
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,b
        add a,6
        ld e,a
        ld d,0
        add hl,de
        add hl,hl
        ld de,NT_SHADOW
        add hl,de
        ret

; ---- text ------------------------------------------------------------------
; print: B = col, C = row, DE = string, A = max chars; colour G_ATTR
print:
        push af
        push de
        call nt_addr
        pop de
        pop af
        ld b,a
.l:     ld a,(de)
        or a
        jr z,.pad
        ld (hl),a
        inc hl
        cp ' '
        ld a,(G_ATTR)
        jr nz,.a
        ld a,(G_SATTR)          ; spaces: black, unless a bar is being drawn
.a:     ld (hl),a
        inc hl
        inc de
        djnz .l
        ret
.pad:   ld a,(G_SATTR)          ; bar: fill the rest of the width
        or a
        ret z
.p:     ld (hl),' '
        inc hl
        ld (hl),a
        inc hl
        djnz .p
        ret

; ---- data --------------------------------------------------------------------
s_packfile_uc: DB "/THUMBS/THUMBS  PAK",0  ; how the OS names an 8.3-only entry
s_packfile: DB "/THUMBS/thumbs.pak",0
s_packmagic: DB "GTPK"
s_magic:    DB "GTH2"
fixed_pal:  DB $00,$00, $FF,$0F         ; colour 0 black, 1 white
fallback_pal:                           ; greys, used until a pack palette loads
        DB $00,$00, $FF,$0F, $11,$01, $22,$02, $33,$03, $44,$04, $55,$05, $66,$06
        DB $77,$07, $88,$08, $99,$09, $AA,$0A, $BB,$0B, $CC,$0C, $DD,$0D, $EE,$0E
        DB $00,$00, $FF,$00, $11,$01, $22,$02, $33,$03, $44,$04, $55,$05, $66,$06
        DB $77,$07, $88,$08, $99,$09, $AA,$0A, $BB,$0B, $CC,$0C, $DD,$0D, $EE,$0E
        INCLUDE "features_b.asm"
        INCLUDE "wheel_b.asm"
        INCLUDE "wheel_lo.asm"
        INCLUDE "wheel_a.asm"
grid_end:
        ASSERT grid_end <= $7C00, "grid code does not fit in free space"
        DISPLAY "grid code: ", /D, grid_end - $70EC, " bytes, free left: ", /D, $7C00 - grid_end

        INCLUDE "features_a.asm"

; ---- messages that were wider than the 20-character screen (same place, shorter)
        ORG $3FD8
        DB "Settings reset",0               ; was "Settings reset to default"
        ORG $4234
        DB "Unzip the ROM first",0          ; was "ROM file must be unzipped"
        ORG $49E6
        DB "DO NOT SWITCH OFF!",0           ; game loading; was "!DO NOT TURN OFF THE SYSTEM!"
        ORG $4A03
        DB "-------------------",0          ; 19, like the OS's other loading screen
        ORG $5081
        DB "DO NOT SWITCH OFF!",0           ; OS update (text only, the code is untouched)
        ORG $5E21
        DB "FAT16 not supported",0          ; was "FAT16 is not supported"

        ORG $3F2B               ; os_init's message: none
        DW s_none

        ORG $07A8               ; browser_main: its folder load goes through the wheel's filter
        call load_dir_hook

        ORG $1A5C               ; folder loader, per entry: keep it? (Z = yes)
        call dir_filter
        jr z,$1A69
        nop
        nop
        ASSERT $ == $1A63

        ORG $4301               ; main menu items: Start Game, Device Info (no About)
        ld bc,0

        ORG $4483               ; about_screen, unreachable now
        INCLUDE "wheel_d.asm"
wheel_d_end:
        ASSERT wheel_d_end <= $465B, "wheel_d does not fit in the About screen's space"
        DISPLAY "wheel part D: ", /D, wheel_d_end - $4483, " of 472 bytes"

        ORG $4003               ; usb_poll: the Flash Gear Pro has no USB port
        ret

        ORG $50A3               ; usb_load_game / usb_load_os, unreachable now
        INCLUDE "wheel_c.asm"
wheel_c_end:
        ASSERT wheel_c_end <= $5254, "wheel_c does not fit in the USB loaders' space"
        DISPLAY "wheel part C: ", /D, wheel_c_end - $50A3, " of 433 bytes"

        ORG $0090               ; unused padding after the EDOS header (nothing in the OS reads it)
        INCLUDE "wheel_t.asm"
        INCLUDE "wheel_bt.asm"
wheel_t_end:
        ASSERT wheel_t_end <= $0200, "wheel_t does not fit before $0200"
        DISPLAY "banner/title part: ", /D, wheel_t_end - $0090, " of 368 bytes"

; ---- font: characters $20-$7F (glyphs $80-$9F and the register window stay) --
        ORG $7C00
        INCBIN "font_unscii8alt.bin"
        ASSERT $ == $7F00

        SAVEBIN "os-v9-wheel.mso", $0000, $8000
