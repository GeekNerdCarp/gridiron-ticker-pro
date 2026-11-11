#!/bin/bash
# Builds a signed, notarized release into ./dist:
#   dist/Gridiron-Ticker-Pro.dmg   for new installs (drag to Applications)
#   dist/Gridiron-Ticker-Pro.zip   what Sparkle downloads when an installed copy updates itself
#   dist/appcast.xml        Sparkle's update list, signed with the maintainer's key (kept in the Keychain)
#
# Needs:
#   SIGN_ID         your "Developer ID Application: Name (TEAMID)" certificate
#   NOTARY_PROFILE  a keychain profile made once with:
#                   xcrun notarytool store-credentials <name> --apple-id <email> --team-id <TEAMID>
#   NOTES_FILE      (optional) release notes in Markdown. The "### What's new" part goes in the update dialog.
#
# Then publish all three files on one GitHub release (the appcast must be named appcast.xml):
#   gh release create vX.Y.Z dist/Gridiron-Ticker-Pro.dmg dist/Gridiron-Ticker-Pro.zip dist/appcast.xml --title "…" --notes-file …
set -euo pipefail
cd "$(dirname "$0")"

: "${SIGN_ID:?Set SIGN_ID to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile}"
REPO="GeekNerdCarp/gridiron-ticker-pro"

SIGN_ID="$SIGN_ID" ./build.sh

APP="dist/Gridiron Ticker Pro.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# 1. Notarize the app itself and staple the ticket to it, so the copy Sparkle installs passes Gatekeeper offline.
ditto -c -k --keepParent "$APP" dist/notarize-app.zip
xcrun notarytool submit dist/notarize-app.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute -v "$APP"
rm dist/notarize-app.zip

# 2. The archive Sparkle downloads (the stapled app).
ZIP="dist/Gridiron-Ticker-Pro.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

# 3. The DMG for new installs.
DMG="dist/Gridiron Ticker Pro.dmg"
STAGE="dist/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Gridiron Ticker Pro.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Gridiron Ticker Pro" -srcfolder "$STAGE" -format UDZO "$DMG"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
cp "$DMG" dist/Gridiron-Ticker-Pro.dmg

# 4. The appcast. It lists just this version, with a download link on this release, and is signed
#    with the private key in the Keychain (macOS may ask once to allow access).
FEED="dist/feed"
rm -rf "$FEED"; mkdir -p "$FEED"
cp "$ZIP" "$FEED/Gridiron-Ticker-Pro.zip"
if [[ -n "${NOTES_FILE:-}" ]]; then
    sed '/^### Install/,$d' "$NOTES_FILE" > "$FEED/Gridiron-Ticker-Pro.md"   # just "What's new"
fi
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --embed-release-notes "$FEED"
cp "$FEED/appcast.xml" dist/appcast.xml

echo
echo "Release $VERSION ready in dist/:"
ls -1 dist/Gridiron-Ticker-Pro.dmg dist/Gridiron-Ticker-Pro.zip dist/appcast.xml
