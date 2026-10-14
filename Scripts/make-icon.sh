#!/bin/bash
#
# Regenerates Resources/AppIcon.icns from AppIconArtwork.swift.
# Only needed after changing the artwork; build.sh uses the committed .icns.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Top-level code must live in main.swift when compiling several files together.
cp "$ROOT/Scripts/RenderIcon.swift" "$WORK/main.swift"
swiftc -O -target "$(uname -m)-apple-macos14.0" \
  "$WORK/main.swift" \
  "$ROOT/Sources/Ding/UI/AppIconArtwork.swift" \
  "$ROOT/Sources/Ding/UI/Theme.swift" \
  -o "$WORK/render-icon"
"$WORK/render-icon" "$WORK/icon-1024.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
cp "$WORK/icon-1024.png" "$ROOT/Resources/AppIcon-1024.png"
echo "==> Wrote Resources/AppIcon.icns"
