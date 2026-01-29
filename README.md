# lymebridge

Bridge Telegram to Claude Code sessions.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/DrHB/lymebridge/main/install.sh | bash
```

## Setup

```bash
lymebridge setup
```

This will:
1. Ask for your Telegram bot token (get one from [@BotFather](https://t.me/botfather))
2. Wait for you to message your bot
3. Auto-detect your chat ID

## Usage

**Terminal 1** - Start the daemon:
```bash
lymebridge
```

**Terminal 2** - Connect a Claude Code session:
```bash
lymebridge connect work1
```

Now message your Telegram bot. Messages appear in Terminal 2.

To route to a specific session, prefix with `@name`:
```
@work1 what files are in src/
```

## Multi-Session

```bash
# Terminal 1
lymebridge connect work1

# Terminal 2
lymebridge connect api-dev
```

Route messages:
- `@work1 message` → Terminal 1
- `@api-dev message` → Terminal 2
- `message` (no prefix) → most recent session

## Commands

```bash
lymebridge              # Run daemon
lymebridge setup        # Interactive setup
lymebridge connect <n>  # Connect session named <n>
lymebridge version      # Show version
lymebridge help         # Show help
```

## License

MIT
