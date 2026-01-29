#!/bin/bash
set -e

REPO="DrHB/lymebridge"
VERSION="latest"

echo "Installing lymebridge..."
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: lymebridge only works on macOS"
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    BINARY_NAME="lymebridge-macos-arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    BINARY_NAME="lymebridge-macos-x86_64"
else
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
fi

# Try to download pre-built binary
DOWNLOAD_URL="https://github.com/$REPO/releases/$VERSION/download/$BINARY_NAME"
TEMP_BINARY="/tmp/lymebridge-$$"

echo "Downloading lymebridge for $ARCH..."
if curl -fsSL "$DOWNLOAD_URL" -o "$TEMP_BINARY" 2>/dev/null; then
    chmod +x "$TEMP_BINARY"
else
    echo "Pre-built binary not available, building from source..."

    # Check for Swift
    if ! command -v swift &>/dev/null; then
        echo "Error: Swift not found. Install Xcode Command Line Tools:"
        echo "  xcode-select --install"
        exit 1
    fi

    # Clone to temp directory and build
    TEMP_DIR="/tmp/lymebridge-build-$$"
    echo "Cloning repository..."
    git clone --depth 1 "https://github.com/$REPO.git" "$TEMP_DIR" 2>/dev/null
    cd "$TEMP_DIR"

    echo "Building (this may take a moment)..."
    swift build -c release --quiet 2>/dev/null
    cp ".build/release/lymebridge" "$TEMP_BINARY"

    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
fi

# Install binary
echo "Installing to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo mv "$TEMP_BINARY" /usr/local/bin/lymebridge
sudo chmod +x /usr/local/bin/lymebridge

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Run: lymebridge setup"
echo "  2. Grant Full Disk Access to lymebridge in System Preferences > Privacy & Security"
echo "  3. Run the daemon: lymebridge"
echo ""
echo "To connect a Claude Code or Codex session:"
echo "  lymebridge connect imessage work1"
echo "  lymebridge connect telegram api"
echo ""
