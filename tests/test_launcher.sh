#!/bin/bash
# Exercises launcher.sh in --dry-run mode against a fake Steam install and app layout.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/steam/hl2" "$TMP/app/Contents/MacOS" "$TMP/app/Contents/Resources/hl2/bin"
touch "$TMP/steam/hl2/hl2_misc_dir.vpk" "$TMP/app/Contents/Resources/hl2/bin/libclient.dylib" "$TMP/app/Contents/Resources/hl2/bin/libserver.dylib"
touch "$TMP/app/Contents/MacOS/hl2_launcher"
sleep 1; touch "$TMP/ref"  # anything in steam/ newer than ref was modified by the launcher
cp "$HERE/../gameinfo.hl2.txt" "$TMP/app/Contents/Resources/"
cp "$HERE/../videoconfig.template.cfg" "$TMP/app/Contents/Resources/"
cp "$HERE/../launcher.sh" "$TMP/app/Contents/MacOS/Half-Life 2"; chmod +x "$TMP/app/Contents/MacOS/Half-Life 2"

out="$(HL2_STEAM_DIR="$TMP/steam" HL2_BASE="$TMP/base" "$TMP/app/Contents/MacOS/Half-Life 2" --dry-run -windowed)"
echo "$out" | grep -q -- "-game \"$TMP/base/hl2\"" || { echo "FAIL: exec line missing -game: $out"; exit 1; }
echo "$out" | grep -q -- "-windowed" || { echo "FAIL: user args not forwarded"; exit 1; }
grep -q "\"$TMP/steam/hl2\"" "$TMP/base/hl2/gameinfo.txt" || { echo "FAIL: gameinfo not rendered"; exit 1; }
grep -q "@STEAM_HL2@" "$TMP/base/hl2/gameinfo.txt" && { echo "FAIL: placeholder left in gameinfo"; exit 1; }
grep -q "gamebin.*\"$TMP/app/Contents/Resources/hl2/bin\"" "$TMP/base/hl2/gameinfo.txt" || { echo "FAIL: gamebin not pointed at app"; exit 1; }
[ -z "$(find "$TMP/steam" -newer "$TMP/ref")" ] || { echo "FAIL: steam dir modified"; exit 1; }
grep -q '"ScreenMSAA"' "$TMP/base/hl2/videoconfig_mac.cfg" || { echo "FAIL: first-run video config not written"; exit 1; }
grep -q "@WIDTH@" "$TMP/base/hl2/videoconfig_mac.cfg" && { echo "FAIL: resolution placeholder left"; exit 1; }
echo marker > "$TMP/base/hl2/videoconfig_mac.cfg"
HL2_STEAM_DIR="$TMP/steam" HL2_BASE="$TMP/base" "$TMP/app/Contents/MacOS/Half-Life 2" --dry-run >/dev/null
grep -q marker "$TMP/base/hl2/videoconfig_mac.cfg" || { echo "FAIL: existing video config overwritten"; exit 1; }

# anniversary layout must be rejected
mkdir -p "$TMP/steam/hl2_complete"
if HL2_STEAM_DIR="$TMP/steam" HL2_BASE="$TMP/base" HL2_NO_ALERT=1 "$TMP/app/Contents/MacOS/Half-Life 2" --dry-run >/dev/null 2>&1; then
  echo "FAIL: anniversary layout accepted"; exit 1
fi
# missing data must be rejected
if HL2_STEAM_DIR="$TMP/nowhere" HL2_BASE="$TMP/base" HL2_NO_ALERT=1 "$TMP/app/Contents/MacOS/Half-Life 2" --dry-run >/dev/null 2>&1; then
  echo "FAIL: missing data accepted"; exit 1
fi
echo PASS
