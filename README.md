# lymebridge

Bridge Telegram to Claude Code via tmux. Send messages AND receive responses.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/DrHB/lymebridge/main/install.sh | bash
```

The installer auto-installs `jq` and `tmux` via Homebrew if needed (macOS only).

## Setup

```bash
lymebridge setup
```

This will:
1. Ask for your Telegram bot token (get one from [@BotFather](https://t.me/botfather))
2. Wait for you to message your bot
3. Auto-detect your chat ID

## Usage

**1. Start Claude Code inside tmux:**
```bash
tmux new -s claude
claude
```

**2. From a separate terminal, start the bridge:**
```bash
lymebridge bridge claude
```

**3. Send messages via Telegram** - they appear as input to Claude Code, and Claude's responses are sent back to you!

Walk away from your computer and continue working via Telegram.

## How it works

```
Telegram  <-->  lymebridge  <-->  Claude Code (in tmux)
```

1. **Input**: `lymebridge bridge` polls your Telegram bot for messages
2. **Inject**: When you send a message, it uses `tmux send-keys` to inject it into Claude Code
3. **Capture**: It monitors the tmux pane for Claude's responses
4. **Reply**: New responses are sent back to your Telegram chat

## Commands

```bash
lymebridge setup            # Configure Telegram bot (one-time)
lymebridge bridge <session> # Bridge Telegram to named tmux session
lymebridge bridge           # Bridge to current tmux pane (when run inside tmux)
lymebridge version          # Show version
lymebridge help             # Show help
```

## Example

```bash
# Terminal 1: Start Claude in tmux
tmux new -s dev
claude

# Terminal 2: Start the bridge
lymebridge bridge dev

# Now on Telegram:
# You: "help me write a python hello world"
# Bot: "Here's a simple Python hello world..."
```

## Requirements

- macOS (uses tmux)
- Homebrew (for auto-installing dependencies)
- Telegram account and bot token

## Smoke test

Quick local checks for syntax, dependencies, and config:

```bash
./scripts/smoke.sh
```

## Troubleshooting

- Setup times out: send any message to your bot (from the account you plan to use) and re-run `lymebridge setup`.
- No replies: verify you're bridging the correct tmux session and re-run `lymebridge setup` to refresh the chat ID.

## License

MIT
