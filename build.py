#!/usr/bin/env python3
"""Build the wheel firmware (and its overlay) from source.

Usage:  python3 build.py path/to/os-v9.mso

Needs sjasmplus (https://github.com/z00m128/sjasmplus) on your PATH. The
original OS image is only read. The result is src/os-v9-wheel.mso; the
pre-flight check (tools/check_mso.py) runs on it.

The overlay (src/ovl.asm: Change Picture and Jump To Letter, which run from
the cart's save RAM) is assembled against the firmware's addresses and put
into tools/make_thumbs.py, which writes it into thumbs.pak. A firmware and a
thumbs.pak only work together when they come from the same build.
"""
import sys, os, re, shutil, subprocess, hashlib, base64, zlib

here = os.path.dirname(os.path.abspath(__file__))
if len(sys.argv) != 2:
    sys.exit(__doc__)
src = os.path.join(here, 'src')


def asm(*args):
    subprocess.run(['sjasmplus', '--nologo'] + list(args), cwd=src, check=True)


shutil.copyfile(sys.argv[1], os.path.join(src, 'os-v9.mso'))
try:
    asm('--sym=wsym.txt', 'gridpatch.asm')
finally:
    os.remove(os.path.join(src, 'os-v9.mso'))
out = os.path.join(src, 'os-v9-wheel.mso')
os.replace(os.path.join(src, 'os-v9-grid.mso'), out)

# the overlay, against the firmware's symbols
syms = []
for line in open(os.path.join(src, 'wsym.txt')):
    m = re.match(r'(\w+): EQU 0x([0-9A-F]+)', line)
    if m:
        v = int(m.group(2), 16)
        syms.append('%-12s EQU %d' % (m.group(1), v - (1 << 32) if v >= 1 << 31 else v))
open(os.path.join(src, 'ovl_syms.asm'), 'w').write('\n'.join(syms) + '\n')
asm('--raw=ovl.bin', 'ovl.asm')
code = open(os.path.join(src, 'ovl.bin'), 'rb').read()
d = base64.b64encode(zlib.compress(code, 9)).decode()
lines = ''.join("    '%s'\n" % d[i:i + 72] for i in range(0, len(d), 72))
mt = os.path.join(here, 'tools', 'make_thumbs.py')
s = open(mt).read()
s2 = re.sub(r'    # OVERLAY-BEGIN\n.*?    # OVERLAY-END\n',
            lambda _: '    # OVERLAY-BEGIN\n' + lines + '    # OVERLAY-END\n', s, flags=re.S)
if s2 != s:
    open(mt, 'w').write(s2)
    print('tools/make_thumbs.py: overlay updated (remake thumbs.pak)')
for f in ('wsym.txt', 'ovl_syms.asm', 'ovl.bin'):
    os.remove(os.path.join(src, f))

print('md5', hashlib.md5(open(out, 'rb').read()).hexdigest())
sys.exit(subprocess.run([sys.executable, os.path.join(here, 'tools', 'check_mso.py'), out, sys.argv[1]]).returncode)
