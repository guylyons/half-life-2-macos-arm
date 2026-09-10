#!/bin/bash
# Launch the test instance, run console commands, screenshot, quit.
# Usage: rtshot.sh <out.png> <map> [+cmd ...] -- [console command;...]
# Console commands after -- are typed into the in-game console after the map loads.
set -u
ROOT="$HOME/Half-Life-2-arm64"
TB="$ROOT/testbase"
OUT="$1"; MAP="$2"; shift 2
LAUNCH=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do LAUNCH+=("$1"); shift; done
[ $# -gt 0 ] && shift
CONS="${1:-}"
WAIT="${RTSHOT_WAIT:-45}"
pkill -f hl2_launcher 2>/dev/null; for i in $(seq 1 20); do pgrep -f hl2_launcher >/dev/null || break; sleep 0.5; done; sleep 1
sed -i '' '/^rt_/d' "$TB/${RTSHOT_GAME:-hl2}/cfg/config.cfg" 2>/dev/null
GAME="${RTSHOT_GAME:-hl2}"
if [ "$GAME" != hl2 ]; then
  mkdir -p "$TB/$GAME/cfg"
  [ -f "$TB/$GAME/videoconfig_mac.cfg" ] || cp "$TB/hl2/videoconfig_mac.cfg" "$TB/$GAME/videoconfig_mac.cfg"
  cp "$TB/hl2/cfg/autoexec.cfg" "$TB/$GAME/cfg/autoexec.cfg"
fi
(MTL_DEBUG_LAYER=${RTSHOT_MTLDEBUG:-0} MTL_SHADER_VALIDATION=${RTSHOT_MTLDEBUG:-0} MTL_SHADER_VALIDATION_REPORT_TO_STDERR=1 HL2_GAME="$GAME" HL2_BASE="$TB" "$ROOT/Half-Life 2.app/Contents/MacOS/Half-Life 2" -condebug -console +con_enable 1 +sv_cheats 1 +map "$MAP" ${LAUNCH[@]+"${LAUNCH[@]}"} > "$ROOT/rtshot.log" 2>&1 &)
sleep "$WAIT"
if [ -n "$CONS" ]; then
  osascript -e 'tell application "System Events" to tell process "hl2_launcher" to set frontmost to true' 2>/dev/null; sleep 1
  echo "$CONS" | tr ';' '\n' > "$TB/hl2/cfg/rtshot.cfg"
  osascript -e 'tell application "System Events" to keystroke "p"'
  sleep "${RTSHOT_SETTLE:-3}"
fi
screencapture -x -D 2 "$OUT"
sips -Z 1000 "$OUT" --out "${OUT%.png}s.png" >/dev/null
if [ -z "${RTSHOT_KEEP:-}" ]; then pkill -f hl2_launcher; sleep 2; fi
L=$(grep -n "\[rt\] ready" "$TB/$GAME/console.log" | tail -1 | cut -d: -f1)
tail -n +"$L" "$TB/$GAME/console.log" | grep "\[rt\]" | grep -v present | head -6 | cut -c1-200
