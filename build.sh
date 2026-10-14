#!/bin/bash
#
# Builds Ding.app and packs it into a DMG with free tools only:
# SwiftPM (swift build), codesign (ad-hoc), hdiutil. No paid developer account.
#
#   ./build.sh
#
# Outputs:
#   dist/Ding.app                    the app
#   release/Ding-<version>.dmg       what visitors download
#   release/Ding-<version>.dmg.sha256
#   release/ding-icon-512.png        icon for the download page
set -euo pipefail

APP="Ding"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
RELEASE="$ROOT/release"
BUNDLE="$DIST/$APP.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
DMG="$RELEASE/$APP-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

# A universal app (Apple Silicon + Intel) needs full Xcode; use it if installed,
# without touching the system-wide xcode-select setting.
ARCHS=()
if [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  ARCHS=(--arch arm64 --arch x86_64)
fi

echo "==> Compiling $APP $VERSION (release${ARCHS:+, universal})"
swift build -c release --package-path "$ROOT" "${ARCHS[@]}" >/dev/null 2>&1 || {
  swift build -c release --package-path "$ROOT" "${ARCHS[@]}" 2>&1 | grep -E "error" -A3
  echo "error: build failed" >&2
  exit 1
}
BIN_DIR="$(swift build -c release --package-path "$ROOT" "${ARCHS[@]}" --show-bin-path)"

echo "==> Assembling $APP.app"
rm -rf "$DIST"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources/Characters" "$BUNDLE/Contents/Frameworks"
cp "$BIN_DIR/$APP" "$BUNDLE/Contents/MacOS/$APP"
cp "$ROOT/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
# Every Lottie JSON in Characters/ becomes a choice in the menu.
cp "$ROOT"/Characters/*.json "$BUNDLE/Contents/Resources/Characters/"

# Lottie is Apache-2.0 licensed: ship its licence text with the app.
mkdir -p "$BUNDLE/Contents/Resources/Acknowledgements"
cp "$ROOT/.build/checkouts/lottie-spm/LICENSE" "$BUNDLE/Contents/Resources/Acknowledgements/Lottie-LICENSE.txt"

# Lottie ships as a dynamic framework; embed it beside the binary.
cp -R "$BIN_DIR/Lottie.framework" "$BUNDLE/Contents/Frameworks/"
if ! otool -l "$BUNDLE/Contents/MacOS/$APP" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$BUNDLE/Contents/MacOS/$APP"
fi

echo "==> Signing (ad-hoc, free)"
codesign --force --deep --sign - "$BUNDLE"

echo "==> Creating DMG"
mkdir -p "$RELEASE"
rm -f "$DMG" "$DMG.sha256"
cp -R "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGING" -format UDZO -ov "$DMG" >/dev/null 2>&1
(cd "$RELEASE" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
sips -z 512 512 "$ROOT/Resources/AppIcon-1024.png" --out "$RELEASE/ding-icon-512.png" >/dev/null

echo "==> Done: $DMG"
