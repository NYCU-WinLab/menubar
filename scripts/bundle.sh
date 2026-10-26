#!/bin/sh
# Builds dist/WinLab.app, universal (Apple silicon and Intel), unsigned.
# scripts/release.sh signs, notarizes and publishes it.
set -eu
cd "$(dirname "$0")/.."
version=$(cat version.txt)
# Sparkle compares CFBundleVersion: the commit count only grows on main.
build=$(git rev-list --count HEAD 2>/dev/null || echo 1)
args="-c release --arch arm64 --arch x86_64 --product WinLab"
swift build $args
bin=$(swift build $args --show-bin-path)

# Outside iCloud: its extended attributes break code signing.
app=.build/dist/WinLab.app
rm -rf "$app"
mkdir -p .build/dist
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/WinLab" "$app/Contents/MacOS/WinLab"
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
sed -e "s/__VERSION__/$version/" -e "s/__BUILD__/$build/" Resources/Info.plist > "$app/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/MenuIcon.png Resources/MenuIcon@2x.png "$app/Contents/Resources/"
plutil -lint "$app/Contents/Info.plist" >/dev/null
echo "$app: $version ($build)"
