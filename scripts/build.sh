#!/bin/bash
# Copyright 2026 jyito — Licensed under the Apache License, Version 2.0.
# See LICENSE and NOTICE in the repository root.
# build.sh — assemble "Claude Profiles.app" from src/ into dist/.
# Works anywhere (the bundle is plain files); zip always, DMG only on macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Claude Profiles.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp src/Info.plist            "$APP/Contents/Info.plist"
cp src/launcher              "$APP/Contents/MacOS/launcher"
cp src/engine.sh             "$APP/Contents/Resources/engine.sh"
cp src/dashboard.html        "$APP/Contents/Resources/dashboard.html"
cp src/dashboard.applescript "$APP/Contents/Resources/dashboard.applescript"
cp src/badge-icon.applescript "$APP/Contents/Resources/badge-icon.applescript"
chmod +x "$APP/Contents/MacOS/launcher" "$APP/Contents/Resources/engine.sh"

if command -v plutil >/dev/null 2>&1; then
    plutil -lint -s "$APP/Contents/Info.plist"
fi

( cd dist && zip -ryq Claude-Profiles.zip "Claude Profiles.app" ) 
cp docs/INSTALL.md dist/

if [ "$(uname)" = "Darwin" ] && command -v iconutil >/dev/null 2>&1 && [ -d assets/icon.iconset ]; then
    iconutil -c icns assets/icon.iconset -o "$APP/Contents/Resources/app.icns"
fi

if [ "$(uname)" = "Darwin" ]; then
    bash scripts/make-dmg.sh "$APP"
    mv Claude-Profiles.dmg dist/ 2>/dev/null || true
fi

echo "Built: $(ls dist)"
