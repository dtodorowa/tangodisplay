#!/usr/bin/env bash
# Builds this fork as "TangoDisplay Prelisten.app" in build/, separate from an installed
# upstream TangoDisplay: its own bundle ID (so its own settings), nothing copied into
# /Applications, and no Sparkle feed that would "update" it back to upstream.
# Usage: Scripts/BuildPrelisten.sh [--open]
set -euo pipefail

EXECUTABLE="TangoDisplay"
BUNDLE_NAME="TangoDisplay Prelisten"
BUNDLE_ID="com.local.tangodisplay.prelisten"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION=$(grep -A1 CFBundleShortVersionString Install.sh | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)

echo "== Build (release, this Mac's architecture) =="
swift build -c release --product "$EXECUTABLE"

APP_DIR="$ROOT_DIR/build/$BUNDLE_NAME.app"
CONTENTS="$APP_DIR/Contents"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

cp ".build/release/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"
cp icon.icns "$CONTENTS/Resources/icon.icns"
cp Sources/TangoDisplay/Resources/SetlistLogo.png "$CONTENTS/Resources/"
cp -R Sources/TangoDisplay/Resources/RemoteUI "$CONTENTS/Resources/"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$BUNDLE_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$BUNDLE_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>icon</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>TangoDisplay reads the currently playing track from Music.app, Swinsian, or Embrace to show it on the dancer display.</string>
  <key>NSAppleMusicUsageDescription</key>
  <string>TangoDisplay reads your Music playlists for Prelisten and imports tracks dragged from Music.app into the setlist.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>TangoDisplay uses global keyboard shortcuts so you can trigger overrides and pauses without switching windows.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>TangoDisplay monitors the microphone to measure room noise so you can see whether music is too quiet, perfect, or too loud for the dance floor.</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>TangoDisplay hosts a small web page on this network so an iPhone can adjust volume and other sound controls from the dance floor.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_http._tcp</string>
  </array>
  <!-- No fork appcast exists; automatic checks stay off so Sparkle never offers upstream builds. -->
  <key>SUFeedURL</key>
  <string>https://raw.githubusercontent.com/dtodorowa/tangodisplay/prelisten/appcast-prelisten.xml</string>
  <key>SUEnableAutomaticChecks</key>
  <false/>
</dict>
</plist>
EOF

SPARKLE_FW="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
cp -R "$SPARKLE_FW" "$CONTENTS/Frameworks/"

echo "== Codesign (ad-hoc) =="
codesign --force --deep --sign - "$CONTENTS/Frameworks/Sparkle.framework"
codesign --force --deep --sign - "$APP_DIR"

echo "Built: $APP_DIR"
if [[ "${1:-}" == "--open" ]]; then
  open "$APP_DIR"
fi
