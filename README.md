# lymebridge

Bridge Telegram to Claude Code via tmux. Dead simple.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/DrHB/lymebridge/main/install.sh | bash
```

That's it! The installer auto-installs `jq` and `tmux` via Homebrew if needed.

## Setup

```bash
lymebridge setup
```

This will:
1. Ask for your Telegram bot token (get one from [@BotFather](https://t.me/botfather))
2. Wait for you to message your bot
3. Auto-detect your chat ID

## Usage

**Start Claude Code inside tmux:**
```bash
tmux new -s claude
claude
```

**In Claude Code, start the bridge:**
```
lymebridge bridge
```

**Now send messages via Telegram** - they appear as input to Claude Code!

Walk away and continue working via Telegram.

## How it works

1. `lymebridge bridge` polls your Telegram bot
2. When you send a message, it runs `tmux send-keys` to inject it
3. The message appears in Claude Code as if you typed it

That's it. ~150 lines of bash. No daemon, no complexity.

## Commands

```bash
lymebridge setup    # Configure Telegram bot
lymebridge bridge   # Bridge Telegram to current tmux pane
lymebridge version  # Show version
lymebridge help     # Show help
```

## License

MIT
