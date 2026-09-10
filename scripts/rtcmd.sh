#!/bin/bash
# Send console commands to the running test instance and screenshot.
# Usage: rtcmd.sh <out.png> "cmd1;cmd2"
set -u
ROOT="$HOME/Half-Life-2-arm64"; TB="$ROOT/testbase"
OUT="$1"; CONS="$2"
echo "$CONS" | tr ';' '\n' > "$TB/hl2/cfg/rtshot.cfg"
osascript -e 'tell application "System Events" to tell process "hl2_launcher" to set frontmost to true' 2>/dev/null; sleep 0.7
osascript -e 'tell application "System Events" to keystroke "`"'; sleep 0.5
osascript -e 'tell application "System Events" to keystroke "exec rtshot"'
osascript -e 'tell application "System Events" to key code 36'; sleep 0.5
osascript -e 'tell application "System Events" to keystroke "`"'
sleep "${RTSHOT_SETTLE:-3}"
screencapture -x -D 2 "$OUT"
sips -Z 1000 "$OUT" --out "${OUT%.png}s.png" >/dev/null
