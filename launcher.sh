#!/bin/bash
# Half-Life 2 launcher for Apple Silicon (engine: nillerusr/source-engine, arm64).
# Reads game data in place from Steam; writes saves/config to HL2_BASE.
#   HL2_STEAM_DIR  Steam "Half-Life 2" directory (default: the Steam library path)
#   HL2_BASE       writable directory (default: ~/Library/Application Support/Half-Life-2-arm64)
#   --dry-run      set up the mod directory and print the command instead of running it
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$(cd "$HERE/../Resources" && pwd)"
STEAM="${HL2_STEAM_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/Half-Life 2}"
BASE="${HL2_BASE:-$HOME/Library/Application Support/Half-Life-2-arm64}"
DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi

fail() {
  echo "$1: $2" >&2
  [ -n "${HL2_NO_ALERT:-}" ] || osascript -e "display alert \"$1\" message \"$2\" as critical" >/dev/null 2>&1
  exit 1
}

[ -f "$STEAM/hl2/hl2_misc_dir.vpk" ] || fail "Half-Life 2 data not found" "Expected the Steam install at:
$STEAM

Install Half-Life 2 in Steam (beta branch steam_legacy), or set HL2_STEAM_DIR."
[ ! -d "$STEAM/hl2_complete" ] || fail "Unsupported Half-Life 2 version" "This build needs the pre-anniversary game data.
In Steam: Half-Life 2 > Properties > Betas > steam_legacy (Pre-25th Anniversary Build)."

MOD="$BASE/hl2"
mkdir -p "$MOD/cfg" "$MOD/save" "$MOD/custom"
# The game libraries stay inside the app (their library search path is relative
# to the bundle); gameinfo.txt points the engine at them by absolute path.
sed -e "s|@STEAM_HL2@|$STEAM|g" -e "s|@APP_GAMEBIN@|$RES/hl2/bin|g" "$RES/gameinfo.hl2.txt" > "$MOD/gameinfo.txt"

cd "$HERE"
if [ "$DRY" = 1 ]; then
  echo "exec \"$HERE/hl2_launcher\" -game \"$MOD\" $*"
  exit 0
fi
exec "$HERE/hl2_launcher" -game "$MOD" "$@"
