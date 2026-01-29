#!/bin/bash
set -e

REPO="DrHB/lymebridge"

echo "Installing lymebridge..."
echo ""

if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: lymebridge only works on macOS"
    exit 1
fi

ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    BINARY_NAME="lymebridge-macos-arm64"
elif [[ "$ARCH" == "x86_64" ]]; then
    BINARY_NAME="lymebridge-macos-x86_64"
else
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
fi

DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$BINARY_NAME"
TEMP_BINARY="/tmp/lymebridge-$$"

echo "Downloading lymebridge for $ARCH..."
if curl -fsSL "$DOWNLOAD_URL" -o "$TEMP_BINARY" 2>/dev/null; then
    chmod +x "$TEMP_BINARY"
else
    echo "Pre-built binary not available, building from source..."

    if ! command -v swift &>/dev/null; then
        echo "Error: Swift not found. Install Xcode Command Line Tools:"
        echo "  xcode-select --install"
        exit 1
    fi

    TEMP_DIR="/tmp/lymebridge-build-$$"
    git clone --depth 1 "https://github.com/$REPO.git" "$TEMP_DIR" 2>/dev/null
    cd "$TEMP_DIR"
    swift build -c release --quiet 2>/dev/null
    cp ".build/release/lymebridge" "$TEMP_BINARY"
    cd /
    rm -rf "$TEMP_DIR"
fi

echo "Installing to /usr/local/bin..."
sudo mkdir -p /usr/local/bin
sudo mv "$TEMP_BINARY" /usr/local/bin/lymebridge
sudo chmod +x /usr/local/bin/lymebridge

echo ""
echo "Installation complete!"
echo ""
echo "Run this to configure:"
echo "  lymebridge setup"
echo ""
