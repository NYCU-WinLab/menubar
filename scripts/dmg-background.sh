#!/bin/sh
# Renders Resources/dmg/background.svg into the 1x + 2x TIFF the DMG uses.
set -eu
cd "$(dirname "$0")/../Resources/dmg"
tmp=$(mktemp -d)
rsvg-convert -w 660 -h 400 background.svg -o "$tmp/1x.png"
rsvg-convert -w 1320 -h 800 background.svg -o "$tmp/2x.png"
tiffutil -cathidpicheck "$tmp/1x.png" "$tmp/2x.png" -out background.tiff
rm -rf "$tmp"
