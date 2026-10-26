#!/bin/sh
# Builds, signs with the Developer ID in this Mac's keychain (a stable
# signature, so the keychain does not ask again after each build) and
# restarts WinLab. Extra environment passes through, e.g.
#   WINLAB_OPEN_MENU=1 scripts/dev-run.sh
set -eu
cd "$(dirname "$0")/.."
scripts/bundle.sh
app=.build/dist/WinLab.app
scripts/sign.sh "$app"
pkill -f "WinLab.app/Contents/MacOS/WinLab" || true
"$app/Contents/MacOS/WinLab" >/dev/null 2>&1 &
