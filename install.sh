#!/bin/bash
set -e

REPO="DrHB/lymebridge"

echo "Installing lymebridge..."
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: lymebridge requires macOS (uses tmux)"
    exit 1
fi

# Auto-install dependencies via Homebrew
install_dep() {
    local cmd=$1
    if ! command -v $cmd &> /dev/null; then
        echo "$cmd not found, installing..."
        if command -v brew &> /dev/null; then
            brew install $cmd
        else
            echo "Error: $cmd required but Homebrew not found"
            echo ""
            echo "Install Homebrew first:"
            echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
            echo ""
            echo "Then run this installer again."
            exit 1
        fi
    fi
}

install_dep jq
install_dep tmux

# Download script
echo ""
echo "Downloading lymebridge..."
sudo mkdir -p /usr/local/bin
sudo curl -fsSL "https://raw.githubusercontent.com/$REPO/main/lymebridge" -o /usr/local/bin/lymebridge
sudo chmod +x /usr/local/bin/lymebridge

echo ""
echo "✓ Installation complete!"
echo ""
echo "Next: Run 'lymebridge setup' to configure your Telegram bot."
echo ""
