#!/usr/bin/env python3
"""Load every map of a game in the test instance; record RT status, crashes and a screenshot per map.
Usage: rtsweep.py <game: hl2|episodic|ep2> <outdir> [maps...]
Uses the same test instance conventions as rtshot.sh (testbase/, F-key bound to exec rtshot)."""
import os, sys, time, subprocess, re, glob
ROOT = os.path.expanduser('~/Half-Life-2-arm64'); TB = f'{ROOT}/testbase'
game, outdir = sys.argv[1], sys.argv[2]; maps = sys.argv[3:]
os.makedirs(outdir, exist_ok=True)
S = os.path.expanduser('~/Library/Application Support/Steam/steamapps/common/Half-Life 2')
if not maps:
    d = {'hl2': f'{S}/hl2/maps', 'episodic': f'{S}/episodic/maps', 'ep2': f'{S}/ep2/maps'}[game]
    pat = {'hl2': r'^d[123]_.*\.bsp$', 'episodic': r'^ep1_.*\.bsp$', 'ep2': r'^ep2_.*\.bsp$'}[game]
    maps = sorted(m[:-4] for m in os.listdir(d) if re.match(pat, m) and 'background' not in m)
log = open(f'{outdir}/sweep.log', 'a')
def note(s):
    print(s); log.write(s + '\n'); log.flush()
def running():
    return subprocess.run(['pgrep', '-f', 'hl2_launcher'], capture_output=True).returncode == 0
def kill():
    subprocess.run(['pkill', '-f', 'hl2_launcher']); 
    for _ in range(20):
        if not running(): break
        time.sleep(0.5)
    time.sleep(1)
def console():
    p = f'{TB}/{game}/console.log'
    return open(p, errors='replace').read() if os.path.exists(p) else ''
def cmd(text):
    os.makedirs(f'{TB}/{game}/cfg', exist_ok=True)
    open(f'{TB}/{game}/cfg/rtshot.cfg', 'w').write(text.replace(';', '\n') + '\n')
    subprocess.run(['osascript', '-e', 'tell application "System Events" to tell process "hl2_launcher" to set frontmost to true'], capture_output=True)
    time.sleep(0.7)
    subprocess.run(['osascript', '-e', 'tell application "System Events" to keystroke "p"'], capture_output=True)
def launch(first_map):
    kill()
    os.makedirs(f'{TB}/{game}/cfg', exist_ok=True)
    if game != 'hl2':
        if not os.path.exists(f'{TB}/{game}/videoconfig_mac.cfg'):
            subprocess.run(['cp', f'{TB}/hl2/videoconfig_mac.cfg', f'{TB}/{game}/videoconfig_mac.cfg'])
        subprocess.run(['cp', f'{TB}/hl2/cfg/autoexec.cfg', f'{TB}/{game}/cfg/autoexec.cfg'])
    cfg = f'{TB}/{game}/cfg/config.cfg'
    if os.path.exists(cfg):
        lines = [l for l in open(cfg) if not l.startswith('rt_')]; open(cfg, 'w').writelines(lines)
    env = dict(os.environ, HL2_GAME=game, HL2_BASE=TB)
    subprocess.Popen([f'{ROOT}/Half-Life 2.app/Contents/MacOS/Half-Life 2', '-condebug', '-console', '+con_enable', '1', '+sv_cheats', '1', '+map', first_map],
                     env=env, stdout=open(f'{outdir}/stderr.log', 'a'), stderr=subprocess.STDOUT)
    time.sleep(6)   # the launcher script execs hl2_launcher; give it time to appear
def crash_reports():
    return set(glob.glob(os.path.expanduser('~/Library/Logs/DiagnosticReports/hl2_launcher*')))
def wait_loaded(m, timeout, start_len):
    marker = f'[rt] maps/{m}.bsp:'
    t0 = time.time(); reports = crash_reports()
    while time.time() - t0 < timeout:
        if not running():
            new = crash_reports() - reports
            return 'crash ' + (os.path.basename(sorted(new)[-1]) if new else '(no report)')
        c = console()[start_len:]
        if marker in c: return 'ok'
        if 'Host_Error' in c or 'Engine error' in c: return 'error ' + [l for l in c.splitlines() if 'Host_Error' in l or 'Engine error' in l][-1][:200]
        time.sleep(1)
    return 'timeout'
need_launch = True
for m in maps:
    start_len = len(console())
    if need_launch:
        launch(m); need_launch = False
    else:
        cmd(f'map {m}')
    st = wait_loaded(m, 120, start_len)
    if st != 'ok':
        note(f'{m}: {st}')
        need_launch = True
        continue
    time.sleep(8)
    cmd('rt_status')
    time.sleep(2)
    if not running():
        note(f'{m}: crashed after load'); need_launch = True; continue
    c = console()[start_len:]
    rt = [l for l in c.splitlines() if l.startswith('[rt] maps/') or 'per frame' in l or 'disabled' in l or 'failed' in l or 'GPU did' in l]
    subprocess.run(['screencapture', '-x', '-D', '2', f'{outdir}/{m}.png'])
    subprocess.run(['sips', '-Z', '800', f'{outdir}/{m}.png', '--out', f'{outdir}/{m}_s.png'], capture_output=True)
    os.remove(f'{outdir}/{m}.png')
    info = ' | '.join(l[:220] for l in rt[-2:])
    note(f'{m}: ok {info}')
kill()
note('done')
