#!/usr/bin/env bash
# TangoDisplay — Build, bundle, sign, and install to /Applications
# Usage: ./Install.sh
# Requirements: Xcode Command Line Tools (xcode-select --install)
set -euo pipefail

APP_NAME="TangoDisplay"
BUNDLE_ID="com.local.tangodisplay"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$ROOT_DIR"

echo "== Generate app icon =="
swift Scripts/GenerateIcon.swift
iconutil -c icns icon.iconset -o icon.icns
rm -rf icon.iconset

echo "== Build (Release, universal) =="
swift build -c release --triple arm64-apple-macosx13.0
swift build -c release --triple x86_64-apple-macosx13.0
lipo -create \
  ".build/arm64-apple-macosx/release/$APP_NAME" \
  ".build/x86_64-apple-macosx/release/$APP_NAME" \
  -output ".build/$APP_NAME-universal"

BIN_PATH=".build/$APP_NAME-universal"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "ERROR: Expected binary at $BIN_PATH"
  exit 1
fi

APP_DIR="$ROOT_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "== Create app bundle =="
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

# Copy icon if present
if [[ -f "$ROOT_DIR/icon.icns" ]]; then
  cp "$ROOT_DIR/icon.icns" "$RES_DIR/icon.icns"
else
  echo "WARN: icon.icns not found — app will use default macOS icon"
fi

# Copy image resources into Contents/Resources
cp "Sources/TangoDisplay/Resources/SetlistLogo.png" "$RES_DIR/"
# Copy Setlist Remote web UI (loaded by HTTPServerTransport via Bundle.main)
cp -R "Sources/TangoDisplay/Resources/RemoteUI" "$RES_DIR/"

echo "== Write Info.plist =="
cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>icon</string>
  <key>CFBundleVersion</key>
  <string>112</string>
  <key>CFBundleShortVersionString</key>
  <string>3.33.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <!-- Required for reading track data via AppleScript (Music.app, Embrace) -->
  <key>NSAppleEventsUsageDescription</key>
  <string>TangoDisplay reads the currently playing track from Music.app, Swinsian, or Embrace to show it on the dancer display.</string>
  <!-- Required for receiving drags of iTunes-purchased tracks from Music.app -->
  <key>NSAppleMusicUsageDescription</key>
  <string>TangoDisplay needs access to your Apple Music library so tracks dragged from Music.app can be added to your setlist.</string>
  <!-- Required for global hotkeys (⌘⇧O/P/R) -->
  <key>NSInputMonitoringUsageDescription</key>
  <string>TangoDisplay uses global keyboard shortcuts so you can trigger overrides and pauses without switching windows.</string>
  <!-- Required for built-in microphone room noise monitoring (decibel meter) -->
  <key>NSMicrophoneUsageDescription</key>
  <string>TangoDisplay monitors the microphone to measure room noise so you can see whether music is too quiet, perfect, or too loud for the dance floor.</string>
  <!-- Required for the Setlist Remote feature so a phone on the same Wi-Fi can connect (Bonjour advertise + accept incoming HTTP/WebSocket) -->
  <key>NSLocalNetworkUsageDescription</key>
  <string>TangoDisplay hosts a small web page on this network so an iPhone can adjust volume and other sound controls from the dance floor.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_http._tcp</string>
  </array>
  <!-- Sparkle auto-update -->
  <key>SUFeedURL</key>
  <string>https://raw.githubusercontent.com/richardsladetdj-creator/TangoDisplay/main/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>BUHKUUjLMvf3imY9/qbRJiES6Vq7/C3w94lkRB37CJw=</string>
</dict>
</plist>
EOF

echo "== Embed Sparkle framework =="
SPARKLE_FW="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FW" ]]; then
  echo "ERROR: Sparkle framework not found at $SPARKLE_FW"
  echo "       Run: swift package resolve"
  exit 1
fi
mkdir -p "$CONTENTS/Frameworks"
cp -R "$SPARKLE_FW" "$CONTENTS/Frameworks/"

# Ad-hoc sign — satisfies Gatekeeper on most machines without a developer account
# Sign inner bundles before the outer app
echo "== Codesign (ad-hoc) =="
codesign --force --deep --sign - "$CONTENTS/Frameworks/Sparkle.framework" || true
codesign --force --deep --sign - "$APP_DIR" || true

echo "== Install to /Applications =="
DEST="/Applications/$APP_NAME.app"
rm -rf "$DEST"
cp -R "$APP_DIR" "$DEST"

echo "Installed: $DEST"
echo ""
echo "== Notes =="
echo "  • On first launch, macOS will ask permission to control Music.app or Embrace."
echo "  • For global hotkeys (⌘⇧O/P/R), grant Input Monitoring access in:"
echo "    System Settings › Privacy & Security › Input Monitoring"
echo "  • If Gatekeeper blocks launch: right-click the app › Open"
echo ""
echo "Launching..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5
open "$DEST"
