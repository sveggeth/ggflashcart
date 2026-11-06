; ============================================================================
; SYSDUMP 1.0 - read-only system-flash dumper for EverDrive-GG-compatible carts
; (EverDrive GG / Flash Gear Pro). Assemble with sjasmplus:
;     sjasmplus sysdump.asm ;     sjasmplus --raw=sysdump.gg sysdump.asm   (then run fixheader.py);     sjasmplus --raw=sysdump.gg sysdump.asm   (then run fixheader.py) python3 fixheader.py sysdump.gg
;
; What it does, per run:
;   * re-sends the cart unlock key ($FFF9 <- 00 'R' 'E' 'N')
;   * selects the system (OS) flash area   ($FFFC bit1 = 0)
;   * copies ONE 16 KB system-flash bank  -> cart SRAM bank 0, in 4 KB chunks
;     via a RAM buffer, re-reads flash and compares (verify)
;   * restores the exact mapper/lock state the OS left for a .gg game
; The OS then saves SRAM bank 0 (16 KB) to the SD card with its own
; "Copy SRAM To File" menu.  Flash is only ever READ: no flash command
; sequence (AA/55/...) is issued anywhere in this program.
;
; Register meanings come from disassembling os-v9.mso and are partly
; inferred; see the notes doc.  Everything that changes the cart mapping
; runs from RAM, because the system-area switch may also remap slots 0/1.
; ============================================================================

        DEVICE NOSLOT64K

; ---- hardware ---------------------------------------------------------------
VDP_DATA    EQU $BE
VDP_CTRL    EQU $BF
JOY         EQU $DC
GG_START    EQU $00

CART_CFG    EQU $FFF8
CART_KEY    EQU $FFF9
MAP_CTRL    EQU $FFFC
MAP_S0      EQU $FFFD
MAP_S1      EQU $FFFE
MAP_S2      EQU $FFFF

; launch state the OS leaves for a .gg, non-Codemasters ROM (see start_game)
GAME_CFG    EQU $20             ; $FFF8 = flags | $20, flags = 0 for us
GAME_MAPC   EQU $02             ; $FFFC

; ---- RAM ----------------------------------------------------------------------
v_bank      EQU $C000           ; bank to dump (0-255)
v_mode      EQU $C001           ; 0 = key only, 1 = key + $FFF8=$01 (OS mode)
v_fail      EQU $C002           ; verify failed
v_chunk     EQU $C003
v_ptr       EQU $C004           ; 2 bytes
v_sum       EQU $C006           ; 2 bytes
v_prev      EQU $C008           ; previous pad state
v_attr      EQU $C009           ; name-table high byte for printing
v_done      EQU $C00A           ; a dump has been made
v_same      EQU $C00B           ; self-test: system bank 0 == this ROM
v_dbank     EQU $C00C           ; bank of the last dump
v_dmode     EQU $C00D           ; mode of the last dump
HEAD        EQU $C010           ; first 8 bytes of the dump
EDOSBUF     EQU $C018           ; 4 bytes at dump offset $80
RAM_CODE    EQU $C100           ; dump_core runs here
TESTBUF     EQU $C400           ; 256 bytes, system bank 0 sample
BUF         EQU $C800           ; 4 KB copy buffer ($C800-$D7FF)
STACK_TOP   EQU $DFF0

; ============================================================================
        ORG $0000
        di
        im 1
        ld sp,STACK_TOP
        jp start

        ORG $0038
        reti                    ; interrupts are never enabled

        ORG $0066
        retn

; ----------------------------------------------------------------------------
        ORG $0080
start:
        ; clear our variables
        ld hl,$C000
        ld de,$C001
        ld bc,$00FF
        ld (hl),0
        ldir
        ld a,4                  ; default bank 4 (where the OS image seems to live)
        ld (v_bank),a

        call vdp_init
        call load_font
        call load_palette
        call clear_screen
        call draw_static
        call draw_bank
        call display_on

main_loop:
        call wait_vblank
        call read_pad           ; A = newly pressed buttons
        or a
        jr z,main_loop
        ld b,a
        bit 2,b                 ; left
        jr z,.notl
        ld hl,v_bank
        dec (hl)
.notl:  bit 3,b                 ; right
        jr z,.notr
        ld hl,v_bank
        inc (hl)
.notr:  bit 0,b                 ; up: +16
        jr z,.notu
        ld a,(v_bank)
        add a,16
        ld (v_bank),a
.notu:  bit 1,b                 ; down: -16
        jr z,.notd
        ld a,(v_bank)
        sub 16
        ld (v_bank),a
.notd:  push bc
        call draw_bank
        pop bc
        bit 4,b                 ; button 1: dump, key only
        jr z,.not1
        xor a
        jr do_dump
.not1:  bit 5,b                 ; button 2: dump, key + OS-mode config
        jr z,main_loop
        ld a,1

; ----------------------------------------------------------------------------
do_dump:
        ld (v_mode),a
        ld (v_dmode),a
        ld a,(v_bank)
        ld (v_dbank),a
        call show_working
        ; copy the mapping-sensitive code to RAM and run it there
        ld hl,dump_core_rom
        ld de,RAM_CODE
        ld bc,dump_core_end-dump_core
        ldir
        call RAM_CODE
        ; back in the normal game mapping: is the "system" sample just this ROM?
        ld hl,$0000
        ld de,TESTBUF
        ld b,0
        ld c,1                  ; assume same
.cmp:   ld a,(de)
        cp (hl)
        jr z,.eq
        ld c,0
.eq:    inc hl
        inc de
        djnz .cmp
        ld a,c
        ld (v_same),a
        ld a,1
        ld (v_done),a
        call draw_results
        jp main_loop

; ============================================================================
; dump_core: assembled for RAM_CODE, stored in ROM, copied before use.
; ============================================================================
dump_core_rom:
        DISP RAM_CODE
dump_core:
        di
        xor a
        ld (v_fail),a
        ; unlock key, same sequence as the OS (hw_unlock_init, $020E)
        ld (CART_KEY),a
        ld a,'R'
        ld (CART_KEY),a
        ld a,'E'
        ld (CART_KEY),a
        ld a,'N'
        ld (CART_KEY),a
        ld a,(v_mode)
        or a
        jr z,.nocfg
        ld a,$01                ; value the OS uses while it runs
        ld (CART_CFG),a
.nocfg:
        ; self-test sample: first 256 bytes of system bank 0
        xor a
        ld (MAP_CTRL),a         ; system area, SRAM off
        ld (MAP_S2),a
        ld hl,$8000
        ld de,TESTBUF
        ld bc,256
        ldir

        xor a
        ld (v_chunk),a
.chunk:
        xor a
        ld (MAP_CTRL),a         ; system flash in slot 2
        ld a,(v_bank)
        ld (MAP_S2),a
        ld a,(v_chunk)
        add a,a
        add a,a
        add a,a
        add a,a
        or $80
        ld h,a
        ld l,0
        ld (v_ptr),hl
        ld de,BUF               ; flash -> RAM
        ld bc,$1000
        ldir
        ld a,$08                ; SRAM bank 0 in slot 2 (as OS sram_map_on(0))
        ld (MAP_CTRL),a
        ld hl,BUF               ; RAM -> SRAM
        ld de,(v_ptr)
        ld bc,$1000
        ldir
        ; verify: read the flash chunk again and compare with SRAM
        xor a
        ld (MAP_CTRL),a
        ld hl,(v_ptr)
        ld de,BUF
        ld bc,$1000
        ldir
        ld a,$08
        ld (MAP_CTRL),a
        ld hl,(v_ptr)
        ld de,BUF
        ld bc,$1000
.vcmp:  ld a,(de)
        cp (hl)
        jr z,.vok
        ld a,1
        ld (v_fail),a
.vok:   inc hl
        inc de
        dec bc
        ld a,b
        or c
        jr nz,.vcmp
        ld a,(v_chunk)
        inc a
        ld (v_chunk),a
        cp 4
        jr nz,.chunk

        ; SRAM bank 0 still mapped: grab a summary for the screen
        ld hl,$8000
        ld de,HEAD
        ld bc,8
        ldir
        ld hl,$8080
        ld de,EDOSBUF
        ld bc,4
        ldir
        ld hl,$8000
        ld de,0
        ld bc,$4000
.sum:   ld a,(hl)
        add a,e
        ld e,a
        jr nc,.nc
        inc d
.nc:    inc hl
        dec bc
        ld a,b
        or c
        jr nz,.sum
        ld (v_sum),de

        ; restore the launch state written by the OS game stub ($04F5)
        ld a,(v_mode)
        or a
        jr z,.norest
        ld a,GAME_CFG
        ld (CART_CFG),a
.norest:
        ld a,GAME_MAPC
        ld (MAP_CTRL),a
        xor a
        ld (MAP_S0),a
        inc a
        ld (MAP_S1),a
        inc a
        ld (MAP_S2),a
        xor a
        ld (CART_KEY),a         ; lock again
        ret
dump_core_end:
        ENT

; ============================================================================
; screen
; ============================================================================
draw_static:
        ld bc,$0000
        ld hl,s_title
        call print_hl
        ld bc,$0001
        ld hl,s_sub
        call print_hl
        ld bc,$0004
        ld hl,s_help1
        call print_hl
        ld bc,$0005
        ld hl,s_help2
        call print_hl
        ret

draw_bank:
        ld bc,$0003
        ld hl,s_bank
        call print_hl           ; "BANK $"
        ld a,(v_bank)
        call print_hex          ; continues at cursor
        ld hl,s_at
        call print_str
        ld a,(v_bank)           ; offset = bank * $4000 (24 bits)
        rrca
        rrca
        and $3F
        call print_hex
        ld a,(v_bank)
        rrca
        rrca
        and $C0
        call print_hex
        xor a
        call print_hex
        ret

show_working:
        call clear_results
        ld bc,$0007
        ld hl,s_working
        jp print_hl

clear_results:
        ld c,7
.l:     ld b,0
        push bc
        ld hl,s_blank
        call print_hl
        pop bc
        inc c
        ld a,c
        cp 18
        jr nz,.l
        ret

draw_results:
        call clear_results
        ld bc,$0007
        ld hl,s_done
        call print_hl
        ld a,(v_dbank)
        call print_hex
        ld a,(v_dmode)
        or a
        ld hl,s_mkey
        jr z,.m
        ld hl,s_mcfg
.m:     call print_str

        ld bc,$0008
        ld hl,s_switch
        call print_hl
        ld a,(v_same)
        or a
        ld hl,s_ok
        jr z,.s
        ld a,$08                ; highlight a failure
        ld (v_attr),a
        ld hl,s_failed
.s:     call print_str
        xor a
        ld (v_attr),a

        ld bc,$0009
        ld hl,s_verify
        call print_hl
        ld a,(v_fail)
        or a
        ld hl,s_ok
        jr z,.v
        ld a,$08
        ld (v_attr),a
        ld hl,s_failed
.v:     call print_str
        xor a
        ld (v_attr),a

        ld bc,$000A
        ld hl,s_sum
        call print_hl
        ld a,(v_sum+1)
        call print_hex
        ld a,(v_sum)
        call print_hex

        ld bc,$000B
        ld hl,s_head
        call print_hl
        ld hl,HEAD
        ld b,8
.h:     ld a,(hl)
        push hl
        push bc
        call print_hex
        pop bc
        pop hl
        inc hl
        djnz .h

        ld bc,$000C
        ld hl,s_edos
        call print_hl
        ld hl,EDOSBUF
        ld de,s_edos_sig
        ld b,4
        ld c,1
.e:     ld a,(de)
        cp (hl)
        jr z,.e1
        ld c,0
.e1:    inc hl
        inc de
        djnz .e
        ld a,c
        or a
        ld hl,s_yes
        jr nz,.e2
        ld hl,s_no
.e2:    call print_str

        ld a,(v_same)
        or a
        jr z,.good
        ld bc,$000E
        ld hl,s_bad1
        call print_hl
        ld bc,$000F
        ld hl,s_bad2
        call print_hl
        ld bc,$0010
        ld hl,s_bad3
        jp print_hl
.good:
        ld bc,$000E
        ld hl,s_next1
        call print_hl
        ld bc,$000F
        ld hl,s_next2
        call print_hl
        ld bc,$0010
        ld hl,s_next3
        jp print_hl

; ---- text output ---------------------------------------------------------
; print_hl: B = column (0-19), C = row (0-17) in the Game Gear window,
;           HL = 0-terminated string.  Leaves the VDP address after the text,
;           so print_str / print_hex can continue on the same line.
print_hl:
        push hl
        ld a,c
        add a,3                 ; GG window starts at tile row 3
        ld l,a
        ld h,0
        add hl,hl               ; *32
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,b
        add a,6                 ; and tile column 6
        ld e,a
        ld d,0
        add hl,de
        add hl,hl               ; *2 bytes per entry
        ld de,$3800
        add hl,de
        ld a,l
        out (VDP_CTRL),a
        ld a,h
        or $40
        out (VDP_CTRL),a
        pop hl
print_str:
        ld a,(hl)
        or a
        ret z
        call put_char
        inc hl
        jr print_str

put_char:                       ; A = ASCII
        out (VDP_DATA),a
        nop
        nop
        nop
        nop
        ld a,(v_attr)
        out (VDP_DATA),a
        nop
        nop
        ret

print_hex:                      ; A = byte, 2 hex digits
        push af
        rrca
        rrca
        rrca
        rrca
        call .dig
        pop af
.dig:   and $0F
        add a,'0'
        cp '9'+1
        jr c,.p
        add a,7
.p:     jp put_char

; ---- VDP setup -----------------------------------------------------------
vdp_init:
        ld hl,vdp_regs
        ld b,11
        ld c,$80
.r:     ld a,(hl)
        out (VDP_CTRL),a
        ld a,c
        out (VDP_CTRL),a
        inc hl
        inc c
        djnz .r
        ; hide sprites: Y = $D0 at SAT start ($3F00)
        ld a,$00
        out (VDP_CTRL),a
        ld a,$3F|$40
        out (VDP_CTRL),a
        ld a,$D0
        out (VDP_DATA),a
        ret

display_on:
        ld a,$C0
        out (VDP_CTRL),a
        ld a,$81
        out (VDP_CTRL),a
        ret

load_font:                      ; 1bpp font -> 4bpp tiles 32..127, colour 1
        ld a,$00                ; VRAM $0400 = tile 32
        out (VDP_CTRL),a
        ld a,$04|$40
        out (VDP_CTRL),a
        ld hl,font
        ld bc,96*8
.f:     ld a,(hl)
        out (VDP_DATA),a
        xor a
        out (VDP_DATA),a
        out (VDP_DATA),a
        out (VDP_DATA),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.f
        ret

load_palette:                   ; GG CRAM: 2 bytes per colour, ----BBBB GGGGRRRR
        xor a
        out (VDP_CTRL),a
        ld a,$C0
        out (VDP_CTRL),a
        ld hl,palette
        ld b,palette_end-palette
.p:     ld a,(hl)
        out (VDP_DATA),a
        inc hl
        djnz .p
        ret

clear_screen:                   ; name table $3800-$3EFF -> tile 32 (space)
        xor a
        out (VDP_CTRL),a
        ld a,$38|$40
        out (VDP_CTRL),a
        ld bc,32*28
.c:     ld a,' '
        out (VDP_DATA),a
        xor a
        out (VDP_DATA),a
        dec bc
        ld a,b
        or c
        jr nz,.c
        ret

wait_vblank:
.a:     in a,(VDP_CTRL)
        rlca
        jr c,.a
.b:     in a,(VDP_CTRL)
        rlca
        jr nc,.b
        ret

read_pad:                       ; returns newly pressed buttons in A
        in a,(JOY)
        cpl
        and $3F
        ld c,a
        ld a,(v_prev)
        cpl
        and c
        ld b,a
        ld a,c
        ld (v_prev),a
        ld a,b
        ret

; ---- data ----------------------------------------------------------------
vdp_regs:
        DB $06,$80,$FF,$FF,$FF,$FF,$FB,$00,$00,$00,$FF

palette:                        ; background palette: 0 = dark blue, 1 = white
        DB $00,$05, $FF,$0F
        DS 28,0
        DB $00,$05, $0F,$00      ; sprite palette (used for highlights): 1 = red
        DS 28,0
palette_end:

s_title:    DB "SYSDUMP 1.0",0
s_sub:      DB "SYSTEM FLASH DUMPER",0
s_bank:     DB "BANK $",0
s_at:       DB "  @$",0
s_help1:    DB "L/R +-1   U/D +-16",0
s_help2:    DB "1:DUMP  2:DUMP+CFG",0
s_working:  DB "READING...",0
s_blank:    DB "                    ",0
s_done:     DB "DUMPED BANK $",0
s_mkey:     DB " (1)",0
s_mcfg:     DB " (2)",0
s_switch:   DB "AREA SWITCH: ",0
s_verify:   DB "VERIFY:      ",0
s_ok:       DB "OK    ",0
s_failed:   DB "FAILED",0
s_sum:      DB "SUM16:       ",0
s_head:     DB "00:",0
s_edos:     DB "EDOS AT $80: ",0
s_edos_sig: DB "EDOS"
s_yes:      DB "YES",0
s_no:       DB "NO ",0
s_next1:    DB "POWER OFF, ON, THEN",0
s_next2:    DB "SRM MENU: COPY SRAM",0
s_next3:    DB "TO FILE (BANKnn.SRM)",0
s_bad1:     DB "STILL GAME AREA -",0
s_bad2:     DB "DUMP NOT USABLE.",0
s_bad3:     DB "TRY BUTTON 2",0

font:       INCBIN "font.bin"

; ---- header -------------------------------------------------------------
        ASSERT $ < $7E00
        DS $7FE0-$,$FF
        DS 16,$FF               ; $7FE0: no Codemasters header
        ORG $7FF0
        DB "TMR SEGA"
        DW 0                    ; reserved
        DW 0                    ; checksum, filled in by fixheader.py
        DB 0,0,0                ; product code / version
        DB $7C                  ; region 7 (GG international), 32 KB

        SAVEBIN "sysdump.gg",$0000,$8000
