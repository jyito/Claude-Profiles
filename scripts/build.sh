#!/bin/bash
# Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
# See LICENSE and NOTICE in the repository root.
# build.sh — assemble "Claude Profiles.app" from app/ + src/ into dist/.
# The executable is the native SwiftUI `Profiles` binary (built from app/ with the
# Command Line Tools — no Xcode); engine.sh + badge-icon.applescript ship in
# Resources so the bundle is self-contained (the app's resolveEnginePath() falls
# back to Bundle.main.resourcePath/engine.sh — no SPIKE_ENGINE needed at runtime).
# Must succeed UNSIGNED (CI runs this with no identity); signing lives in sign.sh.
# zip always, DMG only on macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

# The app build is macOS-only (SwiftUI via the Command Line Tools); fail clearly off-Mac.
command -v swift >/dev/null 2>&1 || {
  echo "build.sh: needs the Swift toolchain (macOS Command Line Tools) to build app/. The bundle is a macOS app." >&2
  exit 1
}

APP="dist/Claude Profiles.app"

echo "==> Building the native SwiftUI app (Profiles binary, release)"
( cd app && swift build -c release )
BIN="app/.build/release/Profiles"
[ -f "$BIN" ] || { echo "missing $BIN — swift build did not produce the Profiles binary" >&2; exit 1; }

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp src/Info.plist             "$APP/Contents/Info.plist"
cp "$BIN"                     "$APP/Contents/MacOS/Profiles"
cp src/engine.sh             "$APP/Contents/Resources/engine.sh"
cp src/badge-icon.applescript "$APP/Contents/Resources/badge-icon.applescript"
chmod +x "$APP/Contents/MacOS/Profiles" "$APP/Contents/Resources/engine.sh"

if command -v plutil >/dev/null 2>&1; then
    plutil -lint -s "$APP/Contents/Info.plist"
fi

if [ "$(uname)" = "Darwin" ] && command -v iconutil >/dev/null 2>&1 && [ -d assets/icon.iconset ]; then
    iconutil -c icns assets/icon.iconset -o "$APP/Contents/Resources/app.icns"
fi

( cd dist && zip -ryq Claude-Profiles.zip "Claude Profiles.app" )
cp docs/INSTALL.md dist/

if [ "$(uname)" = "Darwin" ]; then
    bash scripts/make-dmg.sh "$APP"
    mv Claude-Profiles.dmg dist/ 2>/dev/null || true
fi

echo "Built: $(ls dist)"
