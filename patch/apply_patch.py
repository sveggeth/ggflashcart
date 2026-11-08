#!/usr/bin/env python3
"""Make the wheel firmware from your own copy of EverDrive GG OS v9.

Usage:  python3 apply_patch.py os-v9.mso [os-v9-wheel.mso]

Checks that the input is the expected OS v9 image, applies os-v9-wheel.ips
and checks the result, so a wrong or damaged input can't produce a file
you might flash by mistake.
"""
import sys, os, hashlib

OS_V9_MD5 = '1d6a22a2971785fbacc99078d0d540a9'
WHEEL_MD5 = '244c83b7f99f1998a422040a24f9cb74'


def apply_ips(data, ips):
    if ips[:5] != b'PATCH':
        sys.exit('not an IPS patch')
    out = bytearray(data)
    i = 5
    while ips[i:i + 3] != b'EOF':
        off = int.from_bytes(ips[i:i + 3], 'big')
        n = int.from_bytes(ips[i + 3:i + 5], 'big')
        i += 5
        if n == 0:                                   # RLE record
            n = int.from_bytes(ips[i:i + 2], 'big')
            out[off:off + n] = ips[i + 2:i + 3] * n
            i += 3
        else:
            out[off:off + n] = ips[i:i + n]
            i += n
    return bytes(out)


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) == 3 else 'os-v9-wheel.mso'
    data = open(src, 'rb').read()
    if hashlib.md5(data).hexdigest() != OS_V9_MD5:
        sys.exit('%s is not the expected EverDrive GG OS v9 image (md5 %s).\n'
                 'Nothing was written.' % (src, OS_V9_MD5))
    ips = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'os-v9-wheel.ips'), 'rb').read()
    out = apply_ips(data, ips)
    if hashlib.md5(out).hexdigest() != WHEEL_MD5:
        sys.exit('the patched image does not have the expected checksum. Nothing was written.')
    open(dst, 'wb').write(out)
    print('wrote %s (md5 %s)' % (dst, WHEEL_MD5))


if __name__ == '__main__':
    main()
