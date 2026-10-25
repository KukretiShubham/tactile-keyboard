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

# Signed locally ("ad-hoc"). macOS ties Accessibility to the signature, so
# after a rebuild you may need to switch Tactile off and on again under
# Privacy & Security → Accessibility.
codesign --force --sign - --options runtime --identifier app.tactile.mac "$APP"
codesign --verify --strict "$APP"

echo "Built $APP"
