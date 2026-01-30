#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

missing=0

check_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing dependency: $cmd"
        missing=1
    fi
}

echo "Smoke test: lymebridge"

# Syntax check the main script
bash -n "$ROOT_DIR/lymebridge"

# Verify required commands exist
check_cmd curl
check_cmd jq
check_cmd tmux

if ! command -v md5 >/dev/null 2>&1 && ! command -v md5sum >/dev/null 2>&1; then
    echo "Missing dependency: md5 or md5sum"
    missing=1
fi

if [[ $missing -ne 0 ]]; then
    echo "Dependency check failed."
    exit 1
fi

# Basic CLI sanity checks (no network calls)
"$ROOT_DIR/lymebridge" version >/dev/null
"$ROOT_DIR/lymebridge" help >/dev/null

CONFIG_FILE="$HOME/.config/lymebridge/config.json"
if [[ -f "$CONFIG_FILE" ]]; then
    if ! jq -e '.botToken and .chatId' "$CONFIG_FILE" >/dev/null 2>&1; then
        echo "Config is present but missing botToken or chatId."
        exit 1
    fi
else
    echo "Config not found. Run 'lymebridge setup' to create it."
fi

echo "OK"
