#!/bin/sh
# Signs WinLab.app and Sparkle inside it, inner parts first, with the
# hardened runtime that notarization requires.
set -eu
app=$1
id=${SIGN_IDENTITY:-"Developer ID Application: YongXiang Zhan (68PK3GTMDD)"}
sparkle="$app/Contents/Frameworks/Sparkle.framework"
xattr -cr "$app"
for part in \
  "$sparkle/Versions/B/XPCServices/Installer.xpc" \
  "$sparkle/Versions/B/XPCServices/Downloader.xpc" \
  "$sparkle/Versions/B/Autoupdate" \
  "$sparkle/Versions/B/Updater.app" \
  "$sparkle" \
  "$app"; do
  codesign --force --timestamp --options runtime --sign "$id" "$part"
done
codesign --verify --strict --deep "$app"
echo "$app: signed by $id"
