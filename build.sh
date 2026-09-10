#!/bin/bash
# Build the arm64 Source engine and assemble Half-Life 2.app.
# Usage: ./build.sh [deps|patch|configure|build|install|episodic|app]...  (default: all)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$ROOT/source-engine"
STAGE="$ROOT/stage"
JOBS="$(sysctl -n hw.ncpu)"
BREW="$(brew --prefix)"
PYTHON="$BREW/bin/python3"
# keg-only packages need explicit pkg-config paths
export PKG_CONFIG_PATH="$BREW/opt/zlib/lib/pkgconfig:$BREW/opt/bzip2/lib/pkgconfig:$BREW/opt/curl/lib/pkgconfig:$BREW/opt/jpeg-turbo/lib/pkgconfig:$BREW/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

deps() {
  for p in sdl2-compat freetype fontconfig jpeg-turbo libpng curl zlib bzip2 pkg-config; do
    brew list --versions "$p" >/dev/null 2>&1 || brew install "$p"
  done
  xcode-select -p >/dev/null
}

patch() {
  [ -d "$ENGINE/.git" ] || git clone --recursive --depth 1 https://github.com/nillerusr/source-engine.git "$ENGINE"
  # Fixes live on branch macos-arm64 in the engine tree and in the ivp submodule;
  # patches/engine and patches/ivp recreate those branches on a fresh clone.
  apply_patches() {  # $1 = repo dir, $2 = patch dir
    cd "$1"
    if ! git rev-parse --verify -q macos-arm64 >/dev/null; then
      git checkout -q -b macos-arm64
      if ls "$2"/*.patch >/dev/null 2>&1; then git am -q "$2"/*.patch; fi
    fi
    git checkout -q macos-arm64
  }
  apply_patches "$ENGINE/ivp" "$ROOT/patches/ivp"
  apply_patches "$ENGINE" "$ROOT/patches/engine"
}

configure() {
  cd "$ENGINE"
  "$PYTHON" waf configure -T release --prefix="$STAGE" --build-games=hl2
}

build() { cd "$ENGINE" && "$PYTHON" waf build -j"$JOBS"; }
install() { cd "$ENGINE" && rm -rf "$STAGE" && "$PYTHON" waf install; }
app() { "$ROOT/make-app.sh"; }

# Episode One/Two use the same engine with game libraries compiled as "episodic"
# (HL2_EPISODIC). They are built in a second waf output directory; only the client
# and server libraries are taken from it, into stage-episodic/bin (install wipes
# stage/). The default configuration is restored afterwards.
episodic() {
  cd "$ENGINE"
  # waf keeps one lock file per source tree pointing at the current output directory;
  # save and restore it so the default build directory does not need reconfiguring.
  [ -f .lock-waf_darwin_build ] && cp .lock-waf_darwin_build .lock-waf_darwin_build.hl2
  "$PYTHON" waf configure -o build-episodic -T release --prefix="$STAGE" --build-games=episodic
  "$PYTHON" waf build -j"$JOBS" --targets=client,server
  mkdir -p "$ROOT/stage-episodic/bin"
  cp build-episodic/game/client/libclient.dylib build-episodic/game/server/libserver.dylib "$ROOT/stage-episodic/bin/"
  [ -f .lock-waf_darwin_build.hl2 ] && mv .lock-waf_darwin_build.hl2 .lock-waf_darwin_build
}

if [ $# -eq 0 ]; then set -- deps patch configure build install episodic app; fi
for step in "$@"; do "$step"; done
