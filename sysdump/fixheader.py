# Fill in the Sega header checksum ($7FFA, little endian) of a 32 KB ROM:
# 16-bit sum of bytes $0000-$7FEF, as checked by the SMS/GG BIOS.
import sys
p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
assert len(d) == 0x8000 and d[0x7FF0:0x7FF8] == b'TMR SEGA'
s = sum(d[:0x7FF0]) & 0xFFFF
d[0x7FFA] = s & 0xFF
d[0x7FFB] = s >> 8
open(p, 'wb').write(d)
print('checksum %04X' % s)
