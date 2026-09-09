#!/bin/bash
# Export the macos-arm64 branches of source-engine and its ivp submodule to patches/.
# Only file changes are exported; submodule pointer updates are excluded because
# build.sh recreates the ivp branch from patches/ivp before patching the engine.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$ROOT/patches" && mkdir -p "$ROOT/patches/engine" "$ROOT/patches/ivp"
git -C "$ROOT/source-engine/ivp" format-patch -q -o "$ROOT/patches/ivp" master..macos-arm64
git -C "$ROOT/source-engine" format-patch -q -o "$ROOT/patches/engine" master..macos-arm64 -- . ':!ivp'
ls -R "$ROOT/patches"
