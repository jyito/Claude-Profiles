#!/bin/bash
# make-icon.sh — regenerate assets/icon.iconset from assets/app-icon.svg using
# only macOS built-ins (sips reads SVG natively; no Homebrew/librsvg needed).
# Run this whenever the icon SVG changes; build.sh then bakes the iconset into
# the app bundle with iconutil.
set -eu
cd "$(dirname "$0")/.."

SRC="assets/app-icon.svg"
ICONSET="assets/icon.iconset"
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }
command -v sips >/dev/null 2>&1 || { echo "sips not found (macOS only)" >&2; exit 1; }

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

render() {  # $1 = pixel size, $2 = iconset filename
    sed "s/width=\"1024\" height=\"1024\"/width=\"$1\" height=\"$1\"/" "$SRC" > "$tmp/i.svg"
    sips -s format png "$tmp/i.svg" --out "$ICONSET/$2" >/dev/null
    sips -z "$1" "$1" "$ICONSET/$2" >/dev/null
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

echo "Baked $ICONSET from $SRC"
if command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns "$ICONSET" -o "$tmp/app.icns" && echo "iconutil verified the iconset (build.sh bakes it into the bundle)"
fi
