# SYSDUMP: back up the cart's system flash

A small Game Gear program you run like a game. It copies one 16 KB bank of
the cart's **system** flash area, where the OS lives, into the cart's save
RAM. The OS then copies the save RAM to a file on the SD card. Repeat once
per bank, then join the files on your computer.

It only **reads** flash and never sends a flash erase or write command. If
anything goes wrong, the worst case should be a crash: power off and on.
It was tested on a Flash Gear Pro.

> [!WARNING]
> This is still low-level code running on your cart. Back up your SD card's
> `/SAVE` folder first: the dumper overwrites the cart's save RAM.

## Build

```sh
sjasmplus sysdump.asm
python3 fixheader.py sysdump.gg        # Sega header checksum
python3 make_banks.py SYSDUMP           # empty target files BANK00-07.SRM
```

Keep the extension `.gg`. A `.sms` name makes the OS start it in SMS mode.

## Use

1. Copy `sysdump.gg` and the `BANKnn.SRM` files to the SD card, for example
   into a folder called `SYSDUMP`.
2. Highlight `sysdump.gg`, press 1, **Load And Start**. With the wheel
   firmware, `.srm` files only show in **List View** (Start → List View).
3. SYSDUMP starts on bank `$04`, where the OS lives.
   * Left/Right: bank −1 / +1. Up/Down: bank +16 / −16.
   * Button 1: dump (unlock key only).
   * Button 2: dump (unlock key + OS-mode config). Use this if 1 says
     FAILED.

   Read the result:
   * `AREA SWITCH OK`: it read the system area. `FAILED`: it only saw
     the game area. Try button 2.
   * `VERIFY OK`: two reads matched what's in save RAM.
   * `EDOS AT $80 YES`: expected for bank `$04` (the OS header).
4. Power off and on. Save RAM keeps its contents (it's FRAM).
5. In the file list, highlight the `BANKnn.SRM` with the **same** number,
   press 1 and choose **Copy SRAM To File**, *not* "Copy File To SRAM".
6. Next bank: press 2 at the top level for the Main Menu, choose
   **Start Game** (SYSDUMP is still in flash), pick the next bank and
   repeat.

Banks `04` and `05` are the OS. Together they should equal your
`os-v9.mso`, which proves the dumper works. Banks `00`-`03` hold the boot
program and the backup OS (Right + 2 at power-on).

## Join and check

```sh
python3 join_banks.py BANK00.SRM BANK01.SRM ... BANK07.SRM --os os-v9.mso
```

This writes `system_dump.bin`. It flags files that were never copied (all
`$FF`) and banks that repeat, and checks `BANK04`+`BANK05` against the OS
file.

The font is font8x8 by Daniel Hepper (public domain).
