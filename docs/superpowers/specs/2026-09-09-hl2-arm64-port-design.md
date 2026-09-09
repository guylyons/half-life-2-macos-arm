# Half-Life 2 on Apple Silicon: design

Date: 2026-09-09

## Goal

A native arm64 macOS build of Half-Life 2 that reads the player's own Steam
game data in place and ships as a double-clickable `Half-Life 2.app`, in the
same shape as the existing `~/Half-Life-arm64` project for Half-Life 1.

## Why this shape

Valve's macOS build of Half-Life 2 is 32-bit Intel (i386) only. Rosetta 2
translates only x86_64, so the shipped binaries cannot run on Apple Silicon.
Valve does not publish the Source engine. The only engine that can be built
for arm64 is `nillerusr/source-engine` (waf build, Linux/Android/macOS
targets). Its README states it derives from Valve's 2017 engine code that
leaked in 2020; the owner has chosen to use it for personal play of a game
they own. The Wine route was considered and rejected as non-native.

## Known risk

No public working Apple Silicon build exists. Issue #475 (May 2026) reports
that an arm64 macOS build compiles and boots, then crashes in
`DrawStartupGraphic` and later in vphysics/qhull. Reported causes:

1. `IsOSX()` false at run time because `OSX` is not defined for game modules,
   so `.dll` names are used instead of `.dylib`.
2. `DXABSTRACT_BREAK_ON_ERROR()` stubs in `togl/linuxwin/dxabstract.cpp`
   raise SIGTRAP on the normal startup path (`SetTransform` etc.).
3. Fixed-function wrappers in `shaderapidx8.cpp` call those stubs.
4. SIGBUS in vphysics qhull during BSP collision load (unresolved upstream).

Linux arm64 and Android arm64 work, so remaining problems are macOS-specific
ABI or stub issues. A dedicated debugging phase is part of the plan.

## Components

| Unit | Purpose | Depends on |
|------|---------|------------|
| `source-engine/` | Engine + game code clone (`nillerusr/source-engine`, recursive). Local fixes are commits on branch `macos-arm64`. | Homebrew: sdl2, freetype, fontconfig, libpng, libedit, opus, pkg-config; Xcode CLT; python3 |
| `patches/` | `git format-patch` export of every commit on `macos-arm64` so the outer repo records the fixes. `build.sh` re-applies them on a fresh clone. | `source-engine/` |
| `build.sh` | Clone/update engine, apply patches, `waf configure -T release -8`, `waf build`, then `make-app.sh`. | above |
| `make-app.sh` | Assemble `Half-Life 2.app` from build outputs: engine dylibs + launcher in `Contents/MacOS`, game `client.dylib`/`server.dylib` and mod templates in `Contents/Resources`, bundled SDL2, Info.plist, ad-hoc codesign. | build outputs |
| Launcher script (`Contents/MacOS/Half-Life 2`) | Locate Steam data, create the writable mod directory, refresh game libraries there, exec the engine. | app bundle |
| Mod directory (`~/Library/Application Support/Half-Life-2-arm64/hl2`) | Writable first search path. Its `gameinfo.txt` mounts the Steam `hl2` directory by absolute path. Holds `bin/` (arm64 game libs), `cfg/`, `save/`, logs. | Steam install |

## Data flow

1. Launcher resolves `HL2_STEAM_DIR` (default
   `~/Library/Application Support/Steam/steamapps/common/Half-Life 2`) and
   checks for `hl2/hl2_misc_dir.vpk`. Missing data shows an alert and exits.
2. Launcher writes/refreshes the mod directory: copies `client.dylib`,
   `server.dylib` into `<mod>/bin/`, renders `gameinfo.txt` with the absolute
   Steam path substituted. Nothing under the Steam directory is written.
3. Launcher `cd`s to the app's `MacOS` dir (engine `bin` layout) and execs the
   engine launcher with `-game "<mod dir>"` plus any user arguments.
4. Engine mounts search paths: mod dir first (write path), Steam `hl2`
   second, `hl2/hl2_*.vpk` via the mounted directory. Saves and
   `config.cfg` land in the mod dir.

The engine requires the pre-anniversary content. The owner switches the Steam
"Betas" setting for Half-Life 2 to `steam_legacy` ("Pre-25th Anniversary
Build") when asked; the launcher detects the anniversary layout
(`hl2_complete/` present, `hl2/hl2_misc_dir.vpk` absent) and explains.

## Rendering and audio

- Rendering: engine `togl` layer (Direct3D 9 calls translated to OpenGL) on
  Apple's OpenGL 4.1 over Metal, via SDL2 window/context.
- Audio: SDL2 audio backend (engine default for non-Windows). No Miles.

## Error handling

- Missing Steam data or wrong branch: user-facing `osascript` alert with the
  expected path and the fix.
- Engine crashes during the port are handled in the debugging phase with
  `lldb` and `-dev 2 -condebug` logs written to the mod directory.
- `make-app.sh` refuses to assemble if any required build output is absent.

## Testing

Manual verification, run from a terminal so logs are visible:

1. Engine boots to the main menu.
2. `map d1_trainstation_01` loads and renders; physics objects behave.
3. Save, quit, relaunch, load the save.
4. Clean quit with no crash report.
5. Double-clicking the `.app` from Finder works with no Homebrew on `PATH`.

## Phases

1. Build: get the engine compiling as arm64 on macOS 26 with current Clang.
2. Boot: fix startup crashes until the menu renders.
3. Play: fix the vphysics/qhull crash and any in-map issues until the tests
   above pass.
4. Package: launcher, app bundle, README, patches exported.
5. Episodes (follow-on): Episode One, Episode Two, Lost Coast as additional
   app bundles using the same binaries with different mod directories.

## Out of scope

- Multiplayer, Steam integration, achievements.
- Modifying anything under the Steam directory.
- The anniversary-build content (Valve's newer VPK/gameinfo layout).
