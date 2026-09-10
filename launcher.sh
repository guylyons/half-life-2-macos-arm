#!/bin/bash
# Half-Life 2 launcher for Apple Silicon (engine: nillerusr/source-engine, arm64).
# Reads game data in place from Steam; writes saves/config to HL2_BASE.
#   HL2_GAME       hl2 (default), episodic (Episode One), ep2 (Episode Two), lostcoast
#   HL2_STEAM_DIR  Steam "Half-Life 2" directory (default: the Steam library path)
#   HL2_BASE       writable directory (default: ~/Library/Application Support/Half-Life-2-arm64)
#   --dry-run      set up the mod directory and print the command instead of running it
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$(cd "$HERE/../Resources" && pwd)"
GAME="${HL2_GAME:-@DEFAULT_GAME@}"
case "$GAME" in @*) GAME=hl2;; esac   # unsubstituted placeholder (running launcher.sh directly)
case "$GAME" in
  hl2)       NAME="Half-Life 2";               DATA="hl2/hl2_misc_dir.vpk";                GAMEBIN="hl2/bin";;
  episodic)  NAME="Half-Life 2: Episode One";  DATA="episodic/ep1_pak_dir.vpk";            GAMEBIN="episodic/bin";;
  ep2)       NAME="Half-Life 2: Episode Two";  DATA="ep2/ep2_pak_dir.vpk";                 GAMEBIN="episodic/bin";;
  lostcoast) NAME="Half-Life 2: Lost Coast";   DATA="lostcoast/lostcoast_pak_dir.vpk";     GAMEBIN="hl2/bin";;
  *) echo "unknown HL2_GAME: $GAME" >&2; exit 1;;
esac
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
[ -f "$STEAM/$DATA" ] || fail "$NAME data not found" "Expected $DATA under:
$STEAM

Install $NAME in Steam; it shares the Half-Life 2 directory."
[ ! -d "$STEAM/hl2_complete" ] || fail "Unsupported Half-Life 2 version" "This build needs the pre-anniversary game data.
In Steam: Half-Life 2 > Properties > Betas > steam_legacy (Pre-25th Anniversary Build)."

MOD="$BASE/$GAME"
mkdir -p "$MOD/cfg" "$MOD/save" "$MOD/custom"
# The game libraries stay inside the app (their library search path is relative
# to the bundle); gameinfo.txt points the engine at them by absolute path.
sed -e "s|@STEAM_HL2@|$STEAM|g" -e "s|@APP_GAMEBIN@|$RES/$GAMEBIN|g" "$RES/gameinfo.$GAME.txt" > "$MOD/gameinfo.txt"

# First run: start with maximum video settings at the main display's native
# resolution (pixels). The engine rewrites this file whenever settings change.
if [ ! -f "$MOD/videoconfig_mac.cfg" ] && [ -f "$RES/videoconfig.template.cfg" ]; then
  NATIVE="$(system_profiler SPDisplaysDataType 2>/dev/null | awk '
    /Resolution:/ { res=$2" "$4 }
    /Main Display: Yes/ { print res; exit }')"
  W="${NATIVE%% *}"; H="${NATIVE##* }"
  case "$W$H" in *[!0-9]*|"") W=1920; H=1080;; esac
  sed -e "s|@WIDTH@|$W|" -e "s|@HEIGHT@|$H|" "$RES/videoconfig.template.cfg" > "$MOD/videoconfig_mac.cfg"
fi

cd "$HERE"
if [ "$DRY" = 1 ]; then
  echo "exec \"$HERE/hl2_launcher\" -game \"$MOD\" $*"
  exit 0
fi
exec "$HERE/hl2_launcher" -game "$MOD" "$@"
