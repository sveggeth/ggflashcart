#!/usr/bin/env python3
"""Join SYSDUMP bank files into one image and sanity-check them.

Usage:  python3 join_banks.py BANK00.SRM BANK01.SRM ... [--os os-v9.mso]
Banks are joined in the order given (name them so that sorts correctly).
With --os, checks that BANK04+BANK05 match your OS file byte for byte, which
proves the dumper really read the system area.
"""
import sys, hashlib

args = sys.argv[1:]
os_file = None
if '--os' in args:
    i = args.index('--os')
    os_file = args[i + 1]
    del args[i:i + 2]
if not args:
    sys.exit(__doc__)

banks = {}
for p in args:
    d = open(p, 'rb').read()
    note = ''
    if len(d) < 0x4000:
        note = '  <-- shorter than 16 KB'
    d = d[:0x4000]
    if d == b'\xff' * len(d):
        note = '  <-- all $FF: never copied, or an erased bank'
    for q, e in banks.items():
        if e == d:
            note += '  <-- identical to ' + q
    banks[p] = d
    print('%-14s sum16 %04X  md5 %s%s' % (p, sum(d) & 0xFFFF, hashlib.md5(d).hexdigest(), note))

img = b''.join(banks.values())
open('system_dump.bin', 'wb').write(img)
print('wrote system_dump.bin, %d bytes' % len(img))

if os_file:
    osd = open(os_file, 'rb').read()
    names = list(banks)
    pair = [n for n in names if n.upper().startswith(('BANK04', 'BANK05'))]
    if len(pair) == 2:
        got = banks[pair[0]] + banks[pair[1]]
        print('BANK04+BANK05 vs %s: %s' % (os_file, 'MATCH' if got == osd else 'DIFFERENT'))
    else:
        print('need BANK04 and BANK05 to compare with', os_file)
