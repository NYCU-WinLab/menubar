#!/usr/bin/env bash
# Builds, signs, notarizes and publishes a WinLab release.
#
# Release Please creates a draft release and its tag when the release pull
# request merges. Run this on a Mac whose login keychain holds:
#   - the Developer ID Application identity,
#   - the notarytool profile (xcrun notarytool store-credentials zyx-notary),
#   - the Sparkle EdDSA key (generate_keys --account winlab-menubar).
#
#   scripts/release.sh v0.1.0
#
# It attaches WinLab-<version>.dmg (people download it), WinLab-<version>.zip
# (Sparkle installs it) and appcast.xml (Sparkle reads it through
# releases/latest), then publishes the draft, which makes it the latest.
set -euo pipefail

tag=${1:?usage: scripts/release.sh <tag>}
version=${tag#v}
repo=NYCU-WinLab/menubar
profile=${NOTARY_PROFILE:-zyx-notary}
sparkle_account=${SPARKLE_ACCOUNT:-winlab-menubar}
root="$(cd "$(dirname "$0")/.." && pwd)"
# Outside iCloud: extended attributes there break code signing.
work=$(mktemp -d "${TMPDIR:-/tmp}/winlab-release.XXXXXX")
trap 'git -C "$root" worktree remove --force "$work/src" 2>/dev/null || true; rm -rf "$work"' EXIT

state=$(gh release view "$tag" --repo "$repo" --json isDraft --jq .isDraft 2>/dev/null || echo missing)
if [ "$state" = missing ]; then
  echo "No release $tag on $repo. Merge the release pull request first." >&2
  exit 1
fi

# Build exactly the tagged commit.
git -C "$root" fetch --quiet --tags origin
git -C "$root" worktree add --quiet --detach "$work/src" "$tag"
cd "$work/src"
if [ "$(cat version.txt)" != "$version" ]; then
  echo "version.txt says $(cat version.txt), the tag says $version." >&2
  exit 1
fi
# Share the SwiftPM cache with the main checkout so Sparkle's tools are there.
ln -s "$root/.build" .build
scripts/bundle.sh
app="$work/WinLab.app"
ditto .build/dist/WinLab.app "$app"
scripts/sign.sh "$app"

notarize() {
  local result status id
  result=$(xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --output-format json)
  status=$(plutil -extract status raw -o - - <<<"$result")
  if [ "$status" != "Accepted" ]; then
    id=$(plutil -extract id raw -o - - <<<"$result")
    xcrun notarytool log "$id" --keychain-profile "$profile" >&2
    echo "Notarization of $1 finished with status $status." >&2
    exit 1
  fi
}

# The app first, so its ticket is stapled inside both the zip and the DMG.
ditto -c -k --sequesterRsrc --keepParent "$app" "$work/notarize.zip"
notarize "$work/notarize.zip"
xcrun stapler staple "$app"
spctl --assess --type execute --verbose=2 "$app"

zip="$work/WinLab-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

# A DMG with the app and a link to /Applications, signed and notarized too.
stage="$work/dmg"
mkdir -p "$stage"
ditto "$app" "$stage/WinLab.app"
ln -s /Applications "$stage/Applications"
dmg="$work/WinLab-$version.dmg"
hdiutil create -quiet -volname "WinLab $version" -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg"
codesign --force --timestamp --sign "${SIGN_IDENTITY:-Developer ID Application: YongXiang Zhan (68PK3GTMDD)}" "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"

# The appcast: one item, signed with the Sparkle key.
signature=$("$root/.build/artifacts/sparkle/Sparkle/bin/sign_update" --account "$sparkle_account" "$zip")
build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist")
minimum=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$app/Contents/Info.plist")
cat >"$work/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>WinLab</title>
    <link>https://github.com/$repo/releases</link>
    <item>
      <title>WinLab $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$repo/releases/tag/$tag</sparkle:fullReleaseNotesLink>
      <enclosure url="https://github.com/$repo/releases/download/$tag/WinLab-$version.zip" type="application/octet-stream" $signature/>
    </item>
  </channel>
</rss>
XML
xmllint --noout "$work/appcast.xml"

(cd "$work" && shasum -a 256 "WinLab-$version.dmg" "WinLab-$version.zip" >SHA256SUMS)
gh release upload "$tag" "$dmg" "$zip" "$work/appcast.xml" "$work/SHA256SUMS" --repo "$repo" --clobber
gh release edit "$tag" --repo "$repo" --draft=false --latest
echo "Published $tag: https://github.com/$repo/releases/tag/$tag"
