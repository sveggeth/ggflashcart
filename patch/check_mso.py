#!/usr/bin/env python3
"""Pre-flight check for a modified EverDrive GG OS image (.mso).

Usage:  python3 check_mso.py my-os.mso os-v9.mso

Compares your image with the official os-v9.mso and refuses (exit code 1)
anything the updater would reject or that touches the code that erases and
writes flash. It does not prove your changes work; it catches the mistakes
that could stop the cart booting or damage the flash layout.
"""
import sys, hashlib

# hand-written hardware layer: flash erase/program, OS update, game launch
CRITICAL = [
    (0x0000, 0x0003, 'reset vector'),
    (0x0080, 0x0084, 'EDOS signature'),
    (0x0201, 0x0763, 'assembly hardware layer (flash, SD, USB, mapper)'),
    (0x4F6D, 0x50A3, 'os_update_from_sd'),
    (0x50A3, 0x5254, 'usb_load_game / usb_load_os'),
]
FUNCS = [(0x0000, 'reset'), (0x0038, 'irq'), (0x0066, 'nmi'), (0x0201, 'boot'), (0x020E, 'hw_unlock_init'), (0x024E, 'spi_xfer'), (0x0269, 'spi_write_nowait'), (0x027A, 'cfg_bit1_set'), (0x0283, 'cfg_bit1_clr'), (0x028C, 'cfg_bit2_set'), (0x0295, 'spi_read'), (0x0297, 'spi_write'), (0x02A4, 'spi_read_burst'), (0x02B2, 'sd_read_blocks'), (0x02F3, 'usb_rx_empty'), (0x02FA, 'usb_tx_full'), (0x0301, 'usb_getc'), (0x030D, 'usb_putc'), (0x0314, 'usb_putc_body'), (0x0325, 'flash_erase_64k'), (0x033D, 'ram_flash_erase'), (0x037C, 'sd_to_flash'), (0x03C5, 'ram_sd_sector_to_flash'), (0x041B, 'cpld_version'), (0x0420, 'sram_map_on'), (0x0439, 'map_ctrl_bit1'), (0x044E, 'sd_write_blocks'), (0x04CF, 'status_bit3'), (0x04D6, 'start_game'), (0x04F5, 'ram_game_launch_stub'), (0x0524, 'os_update_commit'), (0x0532, 'ram_os_update'), (0x05BB, 'usb_to_flash'), (0x05FB, 'ram_usb_sector_to_flash'), (0x0640, 'vdp_init'), (0x0665, 'vdp_write_cram'), (0x0688, 'vdp_write_vram'), (0x06B7, 'vdp_set_reg'), (0x06CE, 'memset'), (0x06F5, 'memcpy'), (0x0714, 'vdp_flush_nametable'), (0x0739, 'vdp_wait_vblank'), (0x0744, 'joy_read'), (0x0763, 'browser_main'), (0x0CA6, 'sd_crc7'), (0x0D41, 'sd_cmd'), (0x0EAC, 'sd_cmd_nowait'), (0x0F81, 'sd_init'), (0x11BA, 'sd_start_multiread'), (0x1208, 'sd_read'), (0x12BD, 'sd_read_to_flash'), (0x1372, 'sd_stop_transfer'), (0x13B6, 'sd_start_multiwrite'), (0x1404, 'sd_write'), (0x144F, 'sd_cmd0'), (0x1496, 'fat_mount'), (0x16A3, 'fn_16A3'), (0x170B, 'fn_170B'), (0x17A7, 'fat_check_sig'), (0x17F1, 'fn_17F1'), (0x180E, 'fn_180E'), (0x1B05, 'fn_1B05'), (0x1B8F, 'fn_1B8F'), (0x1C15, 'fn_1C15'), (0x1C5E, 'fn_1C5E'), (0x1CBE, 'fn_1CBE'), (0x1CDF, 'fn_1CDF'), (0x213F, 'file_seek'), (0x2319, 'fn_2319'), (0x23C6, 'file_read'), (0x2595, 'fn_2595'), (0x25E0, 'fn_25E0'), (0x2669, 'fn_2669'), (0x273E, 'fn_273E'), (0x299F, 'fn_299F'), (0x29D1, 'fn_29D1'), (0x29E2, 'fn_29E2'), (0x2BA9, 'fn_2BA9'), (0x2C27, 'fn_2C27'), (0x2C3F, 'fn_2C3F'), (0x2D7F, 'fn_2D7F'), (0x2FF0, 'fn_2FF0'), (0x3030, 'fn_3030'), (0x30B8, 'fn_30B8'), (0x3247, 'fn_3247'), (0x3309, 'fn_3309'), (0x33E6, 'fn_33E6'), (0x3565, 'fn_3565'), (0x3624, 'fn_3624'), (0x37A2, 'fn_37A2'), (0x3919, 'fn_3919'), (0x3D3D, 'fn_3D3D'), (0x3EC5, 'main'), (0x3EFC, 'os_init'), (0x4003, 'usb_poll'), (0x4058, 'fn_4058'), (0x4130, 'file_menu'), (0x425D, 'fn_425D'), (0x429C, 'fn_429C'), (0x42D1, 'main_menu'), (0x4378, 'fn_4378'), (0x437E, 'fn_437E'), (0x4382, 'fn_4382'), (0x4386, 'device_info_screen'), (0x4483, 'about_screen'), (0x465B, 'boot_game'), (0x46A7, 'detect_rom_type'), (0x47E0, 'load_rom_to_flash'), (0x4A30, 'save_sram_to_sd'), (0x4B68, 'fn_4B68'), (0x4B85, 'load_sram_from_sd'), (0x4C6D, 'fn_4C6D'), (0x4C8A, 'fn_4C8A'), (0x4CA8, 'fn_4CA8'), (0x4D95, 'fn_4D95'), (0x4E41, 'fn_4E41'), (0x4EFD, 'os_update_menu'), (0x4F6D, 'os_update_from_sd'), (0x50A3, 'usb_load_game'), (0x51ED, 'usb_load_os'), (0x5254, 'memcmp'), (0x5297, 'strlen'), (0x52A7, 'ext_match'), (0x52FF, 'fn_52FF'), (0x532A, 'fn_532A'), (0x5399, 'strcpy'), (0x53BB, 'fn_53BB'), (0x53E4, 'fn_53E4'), (0x5446, 'fn_5446'), (0x5485, 'fn_5485'), (0x54CA, 'fn_54CA'), (0x5536, 'fn_5536'), (0x55CB, 'fn_55CB'), (0x55E7, 'fn_55E7'), (0x5625, 'fn_5625'), (0x56B3, 'fn_56B3'), (0x5703, 'fn_5703'), (0x5726, 'fn_5726'), (0x5749, 'fn_5749'), (0x577E, 'fn_577E'), (0x57A6, 'fn_57A6'), (0x57D2, 'fn_57D2'), (0x589D, 'fn_589D'), (0x58E9, 'video_init'), (0x59E3, 'fn_59E3'), (0x59F1, 'fn_59F1'), (0x5A00, 'wait_input'), (0x5A58, 'font_load'), (0x5C0F, 'clear_screen'), (0x5C21, 'fn_5C21'), (0x5C9E, 'fn_5C9E'), (0x5D01, 'fn_5D01'), (0x5D3E, 'fn_5D3E'), (0x5D64, 'fn_5D64'), (0x5D92, 'fn_5D92'), (0x5DCA, 'show_error'), (0x5E49, 'dir_browser'), (0x61BE, 'fn_61BE'), (0x6438, 'fn_6438'), (0x6492, 'hex_viewer'), (0x695B, 'fn_695B'), (0x6966, 'fn_6966'), (0x6969, 'fn_6969'), (0x696C, 'fn_696C'), (0x699E, 'fn_699E'), (0x6A2C, 'fn_6A2C'), (0x6A38, 'fn_6A38'), (0x6A43, 'fn_6A43'), (0x6A4B, 'fn_6A4B'), (0x6A52, 'fn_6A52'), (0x6A55, 'fn_6A55'), (0x6A84, 'fn_6A84'), (0x6AA6, 'fn_6AA6'), (0x6AAC, 'fn_6AAC'), (0x6B15, 'fn_6B15'), (0x6E40, 'fn_6E40'), (0x6EEE, 'fn_6EEE'), (0x6FAB, 'fn_6FAB'), (0x706D, 'fn_706D')]

def func_of(a):
    if a < 0x0201:
        return 'header / vectors'
    if a >= 0x7C00:
        return 'font'
    if 0x70EC <= a < 0x7C00:
        return 'free space'
    best = None
    for f, n in FUNCS:
        if f <= a:
            best = (f, n)
    return '%s+$%X' % (best[1], a - best[0]) if best else '?'

def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    new = open(sys.argv[1], 'rb').read()
    ref = open(sys.argv[2], 'rb').read()
    bad = 0
    def fail(msg):
        nonlocal bad
        bad += 1
        print('FAIL  ' + msg)
    if hashlib.md5(ref).hexdigest() != '1d6a22a2971785fbacc99078d0d540a9':
        print('note  reference is not the official os-v9.mso; comparing anyway')
    if len(new) != 0x8000:
        fail('size is %d bytes, must be exactly 32768 (updater error $37)' % len(new))
        new = new[:0x8000].ljust(0x8000, b'\xff')
    else:
        print('ok    size 32768')
    if new[0x80:0x84] != b'EDOS':
        fail('no EDOS at $0080 (updater error $38)')
    else:
        print('ok    EDOS at $0080')
    if new[0] != 0xC3 or (new[1] | new[2] << 8) >= 0x7F00:
        fail('reset vector is not a JP into the image')
    usb_off = new[0x4003] == 0xC9 and ref[0x4003] != 0xC9
    if usb_off:
        print('ok    usb_poll returns at once: the USB loaders ($50A3-$5253) are unreachable, free to reuse')
    # the OS update screen's warning ($5081-$509D) is text only: a shorter,
    # printable, 0-terminated replacement is allowed; the code around it is not
    msg = new[0x5081:0x509E]
    msg_ok = 0 in msg and all(32 <= c < 127 for c in msg[:msg.index(0)])
    if new[0x5081:0x509E] != ref[0x5081:0x509E]:
        print('%s  OS update warning text: %r' % ('ok  ' if msg_ok else 'FAIL', bytes(msg[:msg.index(0)] if 0 in msg else msg)))
    for a, b, what in CRITICAL:
        if usb_off and a == 0x50A3:
            continue
        if a == 0x4F6D and msg_ok:
            if new[0x4F6D:0x5081] != ref[0x4F6D:0x5081] or new[0x509E:0x50A3] != ref[0x509E:0x50A3]:
                fail('changed: %s ($%04X-$%04X)' % (what, a, b - 1))
            continue
        if new[a:b] != ref[a:b]:
            fail('changed: %s ($%04X-$%04X)' % (what, a, b - 1))
    if new[0x7F00:0x7F04] != ref[0x7F00:0x7F04]:
        print('note  $7F00-$7F03 changed: those addresses are cart registers, the CPU never reads these bytes')
    diff = [i for i in range(0x8000) if new[i] != ref[i]]
    print('info  version byte at $0200: %d (official %d)' % (new[0x200], ref[0x200]))
    print('info  %d bytes differ from the reference' % len(diff))
    runs, start, prev = [], None, None
    for i in diff:
        if start is None or i != prev + 1:
            if start is not None:
                runs.append((start, prev))
            start = i
        prev = i
    if start is not None:
        runs.append((start, prev))
    for s, e in runs[:40]:
        print('      $%04X-$%04X  %s' % (s, e, func_of(s)))
    if len(runs) > 40:
        print('      ... %d more ranges' % (len(runs) - 40))
    if new[0x200] == ref[0x200] and diff:
        print('tip   change the version byte at $0200 so Device Info shows which build is installed')
    print('RESULT: %s' % ('DO NOT FLASH' if bad else 'passes the pre-flight checks'))
    sys.exit(1 if bad else 0)

main()
