#!/bin/bash
set -e

echo "Installing lymebridge..."
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: lymebridge only works on macOS"
    exit 1
fi

# Build from source
if [[ -f "Package.swift" ]]; then
    echo "Building from source..."
    swift build -c release
    BINARY=".build/release/lymebridge"
else
    echo "Error: Run from lymebridge directory"
    exit 1
fi

# Install binary
echo "Installing to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo cp "$BINARY" /usr/local/bin/lymebridge
sudo chmod +x /usr/local/bin/lymebridge

# Install LaunchAgent
echo "Installing LaunchAgent..."
mkdir -p ~/Library/LaunchAgents
cp com.lymebridge.daemon.plist ~/Library/LaunchAgents/

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Run: lymebridge setup"
echo "  2. Grant Full Disk Access in System Preferences > Privacy & Security"
echo "  3. Start daemon: launchctl load ~/Library/LaunchAgents/com.lymebridge.daemon.plist"
echo "     Or run directly: lymebridge"
echo ""
echo "To connect a Claude Code or Codex session:"
echo "  ./bridge-client.sh imessage work1"
