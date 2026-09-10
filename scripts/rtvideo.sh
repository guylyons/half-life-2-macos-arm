#!/bin/bash
# Record display 2 for N seconds; print per-frame mean brightness of a region and the mean
# absolute frame-to-frame difference (temporal instability), both 0..255.
# Usage: rtvideo.sh <seconds> <out.mov> [crop x:y:w:h in screen points]
SEC="$1"; OUT="$2"; CROP="${3:-150:150:1200:700}"
rm -f "$OUT"; screencapture -x -D 2 -V "$SEC" "$OUT" 2>/dev/null
IFS=: read -r cx cy cw ch <<< "$CROP"
ffmpeg -v error -i "$OUT" -vf "crop=${cw}:${ch}:${cx}:${cy},scale=160:90" -f rawvideo -pix_fmt gray - | python3 -c "
import sys,statistics
d=sys.stdin.buffer.read(); n=len(d)//(160*90); fs=[d[i*14400:(i+1)*14400] for i in range(n)]
v=[sum(f)/14400 for f in fs]
diffs=[sum(abs(a-b) for a,b in zip(fs[i],fs[i+1]))/14400 for i in range(n-1)]
print('frames',n,'brightness mean %.1f sd %.2f | frame-to-frame diff mean %.2f p90 %.2f max %.2f'%(statistics.mean(v),statistics.pstdev(v),statistics.mean(diffs),sorted(diffs)[int(len(diffs)*0.9)],max(diffs)))
"
# also report the largest jump of the region mean between consecutive frames (a layer switching on/off shows as a jump)
ffmpeg -v error -i "$OUT" -vf "crop=${cw}:${ch}:${cx}:${cy},scale=32:18" -f rawvideo -pix_fmt gray - | python3 -c "
import sys
d=sys.stdin.buffer.read(); n=len(d)//576
v=[sum(d[i*576:(i+1)*576])/576 for i in range(n)]
j=[abs(v[i+1]-v[i]) for i in range(n-1)]
print('mean-brightness jumps: max %.2f, count>3: %d'%(max(j),sum(1 for x in j if x>3)))
"
