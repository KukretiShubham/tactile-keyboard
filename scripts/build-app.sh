#!/bin/zsh
# Builds build/Tactile.app: a menu bar app that holds its own Accessibility
# permission (instead of Terminal holding it).
#
# UNIVERSAL=1 builds for both Apple silicon and Intel Macs (used for releases).
# RELEASE=1 marks the app as a release, which updates itself, and must be
# signed with SIGNING_IDENTITY (the release workflow's certificate).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Tactile.app"
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    ARCHS=(arm64 x86_64)
else
    ARCHS=("$(uname -m)")
fi

# One build per architecture, joined into a single executable.
BINARIES=()
for arch in $ARCHS; do
    swift build -c release --product Tactile --triple "$arch-apple-macosx15.0"
    BIN="$(swift build -c release --triple "$arch-apple-macosx15.0" --show-bin-path)"
    BINARIES+=("$BIN/Tactile")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/Tactile" $BINARIES
cp -R "$BIN/Tactile_Tactile.bundle/Web" "$APP/Contents/Resources/Web"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
if [[ "${RELEASE:-0}" == 1 ]]; then
    /usr/libexec/PlistBuddy -c "Add :TactileReleaseBuild bool true" "$APP/Contents/Info.plist"
fi

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift Packaging/render-icon.swift Packaging/AppIcon.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# macOS ties Accessibility to the app's signature. With a stable certificate
# (scripts/create-signing-certificate.sh makes one named "Tactile Local
# Signing"), the permission survives rebuilds. Without one the app is signed
# ad hoc, and every rebuild needs Accessibility switched on again.
# Releases are signed with the release certificate instead, which also lets
# each release verify the next one before updating to it.
IDENTITY="${SIGNING_IDENTITY:-Tactile Local Signing}"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$IDENTITY" --options runtime --identifier app.tactile.mac "$APP"
    echo "Signed with \"$IDENTITY\" (Accessibility stays allowed across rebuilds)."
elif [[ "${RELEASE:-0}" == 1 ]]; then
    echo "A release must be signed with \"$IDENTITY\", which isn't in a keychain." >&2
    exit 1
else
    codesign --force --sign - --options runtime --identifier app.tactile.mac "$APP"
    echo "Signed ad-hoc: switch Tactile's Accessibility permission on again after this build."
fi
codesign --verify --strict "$APP"

echo "Built $APP"
