#!/bin/bash
# make-dmg.sh — build the polished, native DMG on a Mac (one command, builder-only;
# end users never run this). Produces a compressed UDZO image with the standard
# drag-to-Applications layout.
#
#   bash make-dmg.sh "/path/to/Claude Profiles.app"
#
# Optional (for public distribution, requires an Apple Developer ID):
#   codesign --deep --force --options runtime -s "Developer ID Application: YOUR NAME" "Claude Profiles.app"
#   xcrun notarytool submit Claude-Profiles.dmg --keychain-profile "notary" --wait
#   xcrun stapler staple Claude-Profiles.dmg
set -euo pipefail

APP="${1:?usage: make-dmg.sh \"/path/to/Claude Profiles.app\"}"
NAME=$(basename "$APP" .app)
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
[ -f "$(dirname "$APP")/INSTALL.md" ] && cp "$(dirname "$APP")/INSTALL.md" "$STAGE/Read Me First.md"

hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "${NAME// /-}.dmg"
echo "Built ${NAME// /-}.dmg"
