#!/bin/bash
set -e

cd "$(dirname "$0")/.."

# Build first
bash Scripts/build.sh

# Copy to Applications
echo ""
echo "Installing to /Applications..."
rm -rf /Applications/Respect.app
cp -R Respect.app /Applications/

# Remove old login item if it exists
osascript -e 'tell application "System Events" to delete login item "Respect"' 2>/dev/null || true

# Create a LaunchAgent that keeps Respect running and starts on login
PLIST="$HOME/Library/LaunchAgents/com.respect.timer.plist"
cat > "$PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.respect.timer</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Respect.app/Contents/MacOS/Respect</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key>
        <true/>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
</dict>
</plist>
EOF

# Remove the local build artifact — only run from /Applications
rm -rf Respect.app

# Load the agent
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo ""
echo "Done! Respect is installed and will:"
echo "  - Start automatically on every login"
echo "  - Restart if it crashes"
echo ""
echo "To start it now:  open /Applications/Respect.app"
echo "To uninstall later:"
echo "  launchctl unload ~/Library/LaunchAgents/com.respect.timer.plist"
echo "  rm ~/Library/LaunchAgents/com.respect.timer.plist"
echo "  rm -rf /Applications/Respect.app"
