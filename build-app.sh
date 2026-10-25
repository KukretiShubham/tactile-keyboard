#!/bin/zsh
# Builds build/Tactile.app: a menu bar app that holds its own Accessibility
# permission (instead of Terminal holding it).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="build/Tactile.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Tactile" "$APP/Contents/MacOS/Tactile"
cp -R "$BIN/Tactile_Tactile.bundle/Web" "$APP/Contents/Resources/Web"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift Packaging/render-icon.swift Packaging/AppIcon.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# macOS ties Accessibility to the app's signature. With a stable certificate
# (create a "Code Signing" certificate named "Tactile Local Signing" once in
# Keychain Access), the permission survives rebuilds. Without one the app is
# signed ad-hoc, and every rebuild needs Accessibility switched on again.
IDENTITY="Tactile Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" --options runtime --identifier app.tactile.mac "$APP"
    echo "Signed with \"$IDENTITY\" (Accessibility stays allowed across rebuilds)."
else
    codesign --force --sign - --options runtime --identifier app.tactile.mac "$APP"
    echo "Signed ad-hoc: switch Tactile's Accessibility permission on again after this build."
fi
codesign --verify --strict "$APP"

echo "Built $APP"
