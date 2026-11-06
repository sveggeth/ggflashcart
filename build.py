#!/usr/bin/env python3
"""Build the wheel firmware from source.

Usage:  python3 build.py path/to/os-v9.mso

Needs sjasmplus (https://github.com/z00m128/sjasmplus) on your PATH. The
original OS image is only read; the result is src/os-v9-wheel.mso, then
the pre-flight check (tools/check_mso.py) runs on it.
"""
import sys, os, shutil, subprocess, hashlib

here = os.path.dirname(os.path.abspath(__file__))
if len(sys.argv) != 2:
    sys.exit(__doc__)
src = os.path.join(here, 'src')
shutil.copyfile(sys.argv[1], os.path.join(src, 'os-v9.mso'))
try:
    subprocess.run(['sjasmplus', '--nologo', 'gridpatch.asm'], cwd=src, check=True)
finally:
    os.remove(os.path.join(src, 'os-v9.mso'))
out = os.path.join(src, 'os-v9-wheel.mso')
print('md5', hashlib.md5(open(out, 'rb').read()).hexdigest())
sys.exit(subprocess.run([sys.executable, os.path.join(here, 'tools', 'check_mso.py'), out, sys.argv[1]]).returncode)
