#!/bin/zsh
# Double-click to open Tactile in the menu bar. Builds Tactile.app first if the
# code changed since the last build. Without the signing certificate (see
# scripts/create-signing-certificate.sh) macOS asks for Accessibility again after each rebuild.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Tactile.app"
if [[ ! -x "$APP/Contents/MacOS/Tactile" ]] || [[ -n "$(find Sources Packaging Package.swift -newer "$APP/Contents/MacOS/Tactile" -print -quit)" ]]; then
    scripts/build-app.sh
fi
open "$APP"
