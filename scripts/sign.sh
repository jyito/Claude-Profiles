#!/bin/bash
# sign.sh — code-sign, notarize, and staple the built app + DMG for distribution.
#
# NONE of this is needed to run the app on your own Mac: locally-built bundles
# carry no quarantine, so Gatekeeper leaves them alone. Signing matters only when
# someone ELSE downloads your DMG — without it they get a "can't be opened"
# prompt and must right-click -> Open. Requires an Apple Developer ID.
#
# Full maintainer walkthrough (enrollment, notarytool profile, Homebrew cask):
#   docs/SIGNING.md
#
# Config via environment:
#   SIGN_IDENTITY   required — e.g. "Developer ID Application: Jane Doe (AB12CD34EF)"
#                   list yours with:  security find-identity -v -p codesigning
#   NOTARY_PROFILE  optional — a notarytool keychain profile name. Without it the
#                   app/DMG are signed but NOT notarized (still blocked for
#                   downloaders). Create the profile once with:
#                     xcrun notarytool store-credentials NOTARY_PROFILE \
#                       --apple-id you@example.com --team-id AB12CD34EF
#
# Usage:
#   bash scripts/build.sh
#   SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=notary bash scripts/sign.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Claude Profiles.app"
DMG="dist/Claude-Profiles.dmg"

: "${SIGN_IDENTITY:?set SIGN_IDENTITY to your Developer ID Application identity (see header)}"
[ -d "$APP" ] || { echo "missing $APP — run scripts/build.sh first" >&2; exit 1; }

echo "==> Signing the app (hardened runtime)"
codesign --deep --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Repacking the signed app into the zip + dmg"
( cd dist && rm -f Claude-Profiles.zip && zip -ryq Claude-Profiles.zip "Claude Profiles.app" )
rm -f "$DMG" Claude-Profiles.dmg
bash scripts/make-dmg.sh "$APP"
mv Claude-Profiles.dmg "$DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing (a few minutes; Apple scans the upload)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling the ticket onto the app and dmg"
    xcrun stapler staple "$APP"
    xcrun stapler staple "$DMG"
    ( cd dist && rm -f Claude-Profiles.zip && zip -ryq Claude-Profiles.zip "Claude Profiles.app" )
    echo "✓ signed + notarized + stapled -> $DMG"
    spctl -a -vvv -t install "$DMG" || true
else
    echo "✓ signed but NOT notarized (set NOTARY_PROFILE to notarize) -> $DMG"
fi
