#!/bin/zsh
# Double-click to start Tactile in Terminal (Terminal then owns the Accessibility permission).
cd "$(dirname "$0")"
swift run -c release Tactile
