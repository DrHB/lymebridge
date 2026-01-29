#!/bin/bash
# bridge-client.sh - Connect Claude Code or Codex CLI session to lymebridge
#
# Usage:
#   ./bridge-client.sh imessage work1
#   ./bridge-client.sh telegram api-dev

SOCKET_PATH="/tmp/lymebridge.sock"
CHANNEL="${1:-imessage}"
SESSION_NAME="${2:-default}"

if [[ -z "$1" ]] || [[ -z "$2" ]]; then
    echo "Usage: ./bridge-client.sh <channel> <session-name>"
    echo ""
    echo "Channels: imessage, telegram"
    echo ""
    echo "Examples:"
    echo "  ./bridge-client.sh imessage work1"
    echo "  ./bridge-client.sh telegram api-dev"
    exit 1
fi

if [[ ! -S "$SOCKET_PATH" ]]; then
    echo "Error: lymebridge daemon not running"
    echo "Start it with: lymebridge"
    exit 1
fi

echo "Connecting to lymebridge..."
echo "  Channel: $CHANNEL"
echo "  Session: $SESSION_NAME"
echo ""

# Use nc (netcat) to connect to Unix socket
# Send register message and keep connection open

{
    # Send register message
    echo "{\"type\":\"register\",\"name\":\"$SESSION_NAME\",\"channel\":\"$CHANNEL\"}"

    # Keep stdin open for sending responses
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            # Escape the line for JSON
            escaped=$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
            echo "{\"type\":\"response\",\"text\":\"$escaped\"}"
        fi
    done
} | nc -U "$SOCKET_PATH" | while IFS= read -r response; do
    # Parse and display incoming messages
    if [[ "$response" == *'"type":"message"'* ]]; then
        # Extract text (simple parsing)
        text=$(echo "$response" | sed 's/.*"text":"\([^"]*\)".*/\1/' | sed 's/\\n/\n/g; s/\\"/"/g; s/\\\\/\\/g')
        echo ""
        echo "[iMessage] $text"
        echo -n "> "
    elif [[ "$response" == *'"type":"ack"'* ]]; then
        echo "Connected! Messages to @$SESSION_NAME will appear here."
        echo "Type responses and press Enter to send back."
        echo ""
        echo -n "> "
    elif [[ "$response" == *'"type":"error"'* ]]; then
        error=$(echo "$response" | sed 's/.*"message":"\([^"]*\)".*/\1/')
        echo "Error: $error"
        exit 1
    fi
done
