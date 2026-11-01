#!/bin/sh
# Installs (or updates) Tactile from its latest GitHub release:
#
#   curl -fsSL https://raw.githubusercontent.com/KukretiShubham/tactile-keyboard/main/install.sh | sh
#
# It downloads the release zip, checks its SHA-256 checksum (and, if the
# GitHub CLI is installed, its build provenance attestation), then puts
# Tactile.app in /Applications and opens it. Nothing else on the Mac changes.
#
# Options, as environment variables:
#   TACTILE_VERSION=1.1.0       install that version instead of the latest
#   TACTILE_DIR=~/Applications  install somewhere other than /Applications
#   TACTILE_NO_OPEN=1           don't open Tactile afterwards
# To uninstall: curl -fsSL …/install.sh | sh -s -- --uninstall
set -eu

REPO="KukretiShubham/tactile-keyboard"
DIR="${TACTILE_DIR:-/Applications}"
APP="$DIR/Tactile.app"

say() { printf '%s\n' "$*"; }
# Downloads with retries and time limits, so a stalled connection can't hang the install.
fetch() { curl -fsSL --retry 3 --connect-timeout 15 --max-time 600 "$@"; }
fail() { printf 'Tactile: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "Tactile runs on macOS."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 15 ] || fail "Tactile needs macOS 15 or later (this Mac has $(sw_vers -productVersion))."

# Quits the copy being replaced (and only that one), so it lets go of any
# held keys before its files change.
quit_running() {
    if pgrep -f "$APP/Contents/MacOS/Tactile" >/dev/null 2>&1; then
        say "Quitting the running Tactile…"
        osascript -e "tell application \"$APP\" to quit" >/dev/null 2>&1 || pkill -f "$APP/Contents/MacOS/Tactile" || true
        sleep 1
    fi
}

if [ "${1:-}" = "--uninstall" ]; then
    quit_running
    rm -rf "$APP"
    say "Removed $APP."
    say "Your paired devices and certificate are in ~/Library/Application Support/Tactile; delete that folder to remove them too."
    exit 0
fi

# Which release: the one asked for, or the latest.
if [ -n "${TACTILE_VERSION:-}" ]; then
    tag="v${TACTILE_VERSION#v}"
else
    tag=$(fetch "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
    [ -n "$tag" ] || fail "couldn't find the latest release. Check your connection, or set TACTILE_VERSION."
fi
printf '%s' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || fail "unexpected release name: $tag"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
zip="Tactile-$tag.zip"
base="https://github.com/$REPO/releases/download/$tag"

say "Downloading Tactile ${tag#v}…"
fetch -o "$work/$zip" "$base/$zip" || fail "couldn't download $base/$zip"
fetch -o "$work/$zip.sha256" "$base/$zip.sha256" || fail "couldn't download the checksum"

say "Checking the download…"
(cd "$work" && shasum -a 256 -c "$zip.sha256" >/dev/null) || fail "the checksum doesn't match; nothing was installed."
if command -v gh >/dev/null 2>&1; then
    gh attestation verify "$work/$zip" --repo "$REPO" >/dev/null 2>&1 \
        || fail "the build provenance attestation doesn't verify; nothing was installed."
    say "Verified: built by GitHub Actions from $REPO at $tag."
fi

ditto -x -k "$work/$zip" "$work/unzipped"
[ -d "$work/unzipped/Tactile.app" ] || fail "the download doesn't contain Tactile.app."

quit_running
mkdir -p "$DIR"
[ -w "$DIR" ] || fail "can't write to $DIR. Run with TACTILE_DIR=~/Applications to install just for you."
rm -rf "$APP"
ditto "$work/unzipped/Tactile.app" "$APP"
say "Installed Tactile ${tag#v} in $DIR."

if [ -z "${TACTILE_NO_OPEN:-}" ]; then
    open "$APP"
fi

say ""
say "Next:"
say "  1. Allow Tactile in System Settings → Privacy & Security → Accessibility."
say "     Updating? Switch Tactile off and on there: macOS treats each version as a new app."
say "  2. Click the Tactile icon in the menu bar, choose Pair a Device…, and scan the QR code with your iPad."
