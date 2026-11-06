#!/usr/bin/env python3
"""Make the empty bank files SYSDUMP copies into: BANK00.SRM ... BANK07.SRM
(16 KB of $FF each). Usage: python3 make_banks.py [OUT_FOLDER] [COUNT]"""
import sys, os
out = sys.argv[1] if len(sys.argv) > 1 else '.'
n = int(sys.argv[2]) if len(sys.argv) > 2 else 8
os.makedirs(out, exist_ok=True)
for i in range(n):
    with open(os.path.join(out, 'BANK%02X.SRM' % i), 'wb') as f:
        f.write(b'\xff' * 0x4000)
print('wrote BANK00.SRM ... BANK%02X.SRM in %s' % (n - 1, out))
