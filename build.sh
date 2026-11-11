#!/bin/bash
# Builds a universal (Apple Silicon + Intel) "Gridiron Ticker Pro.app" into ./dist
#
# SIGN_ID="Developer ID Application: …" signs for notarization (hardened runtime + timestamp).
# Without it the app is ad-hoc signed, which is fine for running it on your own Mac.
#
# For testing the updater, these override the defaults (leave them unset for a normal build):
#   GRIDIRON_VERSION, GRIDIRON_BUILD, GRIDIRON_BUNDLE_ID, GRIDIRON_FEED_URL, GRIDIRON_ALLOW_HTTP_LOCAL=1
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${GRIDIRON_VERSION:-0.1.0}"
BUILD="${GRIDIRON_BUILD:-1}"     # must go up with every release: Sparkle compares it to decide what's newer
BUNDLE_ID="${GRIDIRON_BUNDLE_ID:-app.gridirontickerpro.mac}"
FEED_URL="${GRIDIRON_FEED_URL:-https://github.com/GeekNerdCarp/gridiron-ticker-pro/releases/latest/download/appcast.xml}"
PUBLIC_KEY="DF+W9Oxmnawg0meDOk/ecm7s1tZ89uh9irrYM4M9spg="   # Sparkle's public EdDSA key; the private half stays in the maintainer's Keychain

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="dist/Gridiron Ticker Pro.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/GridironTickerPro" "$APP/Contents/MacOS/GridironTickerPro"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sparkle (the updater). The app isn't sandboxed, so Sparkle's XPC helpers aren't needed.
SPARKLE=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
FW="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$FW/XPCServices" "$FW/Versions/B/XPCServices" \
       "$FW/Headers" "$FW/Versions/B/Headers" "$FW/PrivateHeaders" "$FW/Versions/B/PrivateHeaders" \
       "$FW/Modules" "$FW/Versions/B/Modules"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/GridironTickerPro"

ATS=""
if [[ -n "${GRIDIRON_ALLOW_HTTP_LOCAL:-}" ]]; then
    ATS='<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>'
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Gridiron Ticker Pro</string>
	<key>CFBundleDisplayName</key><string>Gridiron Ticker Pro</string>
	<key>CFBundleExecutable</key><string>GridironTickerPro</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>$BUILD</string>
	<key>LSMinimumSystemVersion</key><string>12.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
	<key>SUFeedURL</key><string>$FEED_URL</string>
	<key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
	<key>SUEnableAutomaticChecks</key><true/>
	<key>SUScheduledCheckInterval</key><integer>86400</integer>
	$ATS
</dict>
</plist>
PLIST

# Strip debug info (it embeds the builder's local file paths).
strip -S -x "$APP/Contents/MacOS/GridironTickerPro"

# Sign from the inside out: Sparkle's helpers, then the framework, then the app.
sign() {
    if [[ -n "${SIGN_ID:-}" ]]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$@"
    else
        codesign --force --sign - "$@"
    fi
}
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign "$APP"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/GridironTickerPro"
echo "Built: $APP ($VERSION, build $BUILD)"
