#!/bin/bash
# Assemble "Half-Life 2.app" from stage/ (the waf install prefix).
# Layout: Contents/MacOS/{Half-Life 2 (launcher script), hl2_launcher, bin/*.dylib}
#         Contents/Resources/{gameinfo.hl2.txt, hl2/bin/{libclient,libserver}.dylib}
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGE="$ROOT/stage"
APP="$ROOT/Half-Life 2.app"
STEAM="$HOME/Library/Application Support/Steam/steamapps/common/Half-Life 2"
BIN="$APP/Contents/MacOS/bin"

for f in "$STAGE/hl2_launcher" "$STAGE/bin/libengine.dylib" "$STAGE/bin/liblauncher.dylib" \
         "$STAGE/hl2/bin/libclient.dylib" "$STAGE/hl2/bin/libserver.dylib"; do
  [ -f "$f" ] || { echo "missing build output: $f (run ./build.sh first)" >&2; exit 1; }
done

rm -rf "$APP"
mkdir -p "$BIN" "$APP/Contents/Resources/hl2/bin"
cp "$STAGE/hl2_launcher" "$APP/Contents/MacOS/"
cp "$STAGE/bin/"*.dylib "$BIN/"
cp "$STAGE/hl2/bin/"*.dylib "$APP/Contents/Resources/hl2/bin/"
cp "$ROOT/gameinfo.hl2.txt" "$APP/Contents/Resources/"
cp "$ROOT/videoconfig.template.cfg" "$APP/Contents/Resources/"
cp "$ROOT/launcher.sh" "$APP/Contents/MacOS/Half-Life 2"
chmod +x "$APP/Contents/MacOS/Half-Life 2"
chmod u+w "$BIN/"*.dylib "$APP/Contents/Resources/hl2/bin/"*.dylib "$APP/Contents/MacOS/hl2_launcher"

# Bundle every Homebrew dylib the binaries depend on (transitively) into bin/
# and point all references at @loader_path so Homebrew is not needed at run time.
# The engine dlopens its own modules from bin/ next to the executable, and the
# game libraries in Resources/hl2/bin are loaded with an absolute path, so their
# Homebrew references are rewritten to @rpath with an rpath of the app's bin dir.
brew_deps() { otool -L "$1" | awk 'NR>1 && $1 ~ /^\/opt\/homebrew\// {print $1}'; }
# @rpath/@loader_path references inside Homebrew libraries (e.g. brotli) resolve
# next to the library they came from; we track the source directory to find them.
rel_deps() { otool -L "$1" | awk 'NR>1 && $1 ~ /^@(rpath|loader_path)\// {print $1}'; }
queue=()
for f in "$APP/Contents/MacOS/hl2_launcher" "$BIN/"*.dylib "$APP/Contents/Resources/hl2/bin/"*.dylib; do
  while read -r dep; do [ -n "$dep" ] && queue+=("$dep"); done < <(brew_deps "$f")
done
seen=" "
while [ ${#queue[@]} -gt 0 ]; do
  dep="${queue[0]}"; queue=("${queue[@]:1}")
  real="$(cd "$(dirname "$dep")" && pwd -P)/$(basename "$dep")"
  name="$(basename "$dep")"
  case "$seen" in *" $name "*) continue;; esac
  seen="$seen$name "
  cp "$real" "$BIN/$name"; chmod u+w "$BIN/$name"
  install_name_tool -id "@loader_path/$name" "$BIN/$name" 2>/dev/null
  while read -r sub; do [ -n "$sub" ] && queue+=("$sub"); done < <(brew_deps "$BIN/$name")
  while read -r sub; do
    [ -n "$sub" ] || continue
    cand="$(dirname "$real")/$(basename "$sub")"
    if [ -f "$cand" ]; then
      queue+=("$cand")
      install_name_tool -change "$sub" "@loader_path/$(basename "$sub")" "$BIN/$name" 2>/dev/null
    else
      echo "WARNING: cannot resolve $sub referenced by $name" >&2
    fi
  done < <(rel_deps "$BIN/$name")
done
# sdl2-compat dlopens SDL3 at run time; ship it under both names it may look for.
SDL3="$(brew --prefix)/lib/libSDL3.0.dylib"
if [ -f "$SDL3" ]; then
  cp "$SDL3" "$BIN/libSDL3.0.dylib"; chmod u+w "$BIN/libSDL3.0.dylib"
  install_name_tool -id "@loader_path/libSDL3.0.dylib" "$BIN/libSDL3.0.dylib" 2>/dev/null
  ln -sf libSDL3.0.dylib "$BIN/libSDL3.dylib"
fi
rewrite() {  # $1 = file, $2 = prefix for references
  while read -r dep; do
    [ -n "$dep" ] && install_name_tool -change "$dep" "$2/$(basename "$dep")" "$1" 2>/dev/null
  done < <(brew_deps "$1")
}
for f in "$BIN/"*.dylib; do [ -L "$f" ] || rewrite "$f" "@loader_path"; done
rewrite "$APP/Contents/MacOS/hl2_launcher" "@executable_path/bin"
for f in "$APP/Contents/Resources/hl2/bin/"*.dylib; do
  rewrite "$f" "@rpath"
  install_name_tool -add_rpath "@loader_path/../../../MacOS/bin" "$f" 2>/dev/null || true
done
if otool -L "$BIN/"*.dylib "$APP/Contents/MacOS/hl2_launcher" "$APP/Contents/Resources/hl2/bin/"*.dylib | grep -q /opt/homebrew; then
  echo "WARNING: Homebrew dylibs still referenced:" >&2
  otool -L "$BIN/"*.dylib "$APP/Contents/MacOS/hl2_launcher" "$APP/Contents/Resources/hl2/bin/"*.dylib | grep /opt/homebrew >&2
fi

[ -f "$STEAM/hl2/resource/game.icns" ] && cp "$STEAM/hl2/resource/game.icns" "$APP/Contents/Resources/Half-Life 2.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Half-Life 2</string>
  <key>CFBundleDisplayName</key>     <string>Half-Life 2</string>
  <key>CFBundleIdentifier</key>      <string>local.halflife2.arm64</string>
  <key>CFBundleVersion</key>         <string>1.0</string>
  <key>CFBundleShortVersionString</key> <string>1.0</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleExecutable</key>      <string>Half-Life 2</string>
  <key>CFBundleIconFile</key>        <string>Half-Life 2</string>
  <key>LSMinimumSystemVersion</key>  <string>12.0</string>
  <key>LSArchitecturePriority</key>  <array><string>arm64</string></array>
  <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS lets the freshly assembled bundle launch.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
