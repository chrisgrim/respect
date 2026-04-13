#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "Building Respect..."
swift build -c release 2>&1

# Create .app bundle
APP="Respect.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/Respect "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Respect</string>
    <key>CFBundleIdentifier</key>
    <string>com.respect.timer</string>
    <key>CFBundleName</key>
    <string>Respect</string>
    <key>CFBundleDisplayName</key>
    <string>Respect</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Respect needs permission to log you out when your work session ends.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Hold spacebar to dictate how long you want to work.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Respect uses speech recognition to understand your voice input.</string>
</dict>
</plist>
PLIST

# Create entitlements
cat > /tmp/respect-entitlements.plist << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Code sign with developer certificate and entitlements
codesign --force --deep --sign "Apple Development: Chris Grim (BWCAXMSGPQ)" \
    --entitlements /tmp/respect-entitlements.plist "$APP"

echo ""
echo "Built: $APP"
echo "Run with: open Respect.app"
