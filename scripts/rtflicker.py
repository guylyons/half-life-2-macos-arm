#!/usr/bin/env python3
"""Capture display 2 rapidly and report per-capture mean brightness of a region, to detect on/off flicker.
Usage: rtflicker.py <count> [x y w h]"""
import subprocess, sys, struct, time, statistics
n = int(sys.argv[1]); x, y, w, h = (int(v) for v in (sys.argv[2:6] if len(sys.argv) >= 6 else (600, 1200, 1800, 500)))
vals = []
for i in range(n):
    subprocess.run(['screencapture', '-x', '-D', '2', '/tmp/fl.png'], capture_output=True)
    subprocess.run(['sips', '-s', 'format', 'bmp', '-c', str(h), str(w), '--cropOffset', str(y), str(x), '/tmp/fl.png', '--out', '/tmp/fl.bmp'], capture_output=True)
    d = open('/tmp/fl.bmp', 'rb').read(); off = struct.unpack_from('<I', d, 10)[0]; bw = struct.unpack_from('<i', d, 18)[0]; bh = abs(struct.unpack_from('<i', d, 22)[0]); bpp = struct.unpack_from('<H', d, 28)[0]
    row = ((bw * bpp // 8) + 3) // 4 * 4
    tot = 0; cnt = 0
    for yy in range(0, bh, 8):
        for xx in range(0, bw, 8):
            o = off + yy * row + xx * (bpp // 8); tot += d[o] + d[o+1] + d[o+2]; cnt += 3
    vals.append(tot / cnt)
print(' '.join('%.1f' % v for v in vals))
print('mean %.1f sd %.2f min %.1f max %.1f' % (statistics.mean(vals), statistics.pstdev(vals), min(vals), max(vals)))
