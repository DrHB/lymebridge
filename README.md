# lymebridge

Bridge iMessage and Telegram to Claude Code and Codex CLI terminal sessions.

Send messages via iMessage or Telegram → they appear as input in your AI session → responses come back to your messaging app.

## Features

- **Multi-channel support**: iMessage (local) and Telegram (remote)
- **Multi-session**: Run multiple AI sessions, route with `@session-name`
- **Tool-agnostic**: Works with Claude Code, Codex CLI, or any terminal AI
- **Zero network for iMessage**: All local, nothing leaves your Mac
- **Prefix-based responses**: `[session-name] response text`

## Quick Start

```bash
# Clone and install
git clone https://github.com/yourusername/lymebridge.git
cd lymebridge
./install.sh

# Setup (choose iMessage or Telegram)
lymebridge setup

# For iMessage: Grant permissions in System Preferences:
# - Full Disk Access for lymebridge
# - Automation access for Messages.app

# Start daemon
lymebridge
```

## Usage

### 1. Start the daemon

```bash
lymebridge
```

### 2. Connect your AI session

In your terminal with Claude Code or Codex:

```bash
./bridge-client.sh imessage work1
# or
./bridge-client.sh telegram api-dev
```

### 3. Send messages

**Via iMessage (to yourself):**
```
@work1 what files did we edit?
```

**Via Telegram (to your bot):**
```
@api-dev check the logs
```

### 4. Receive responses

```
[work1] We edited 3 files: main.swift, Config.swift...
[api-dev] No errors found in the logs.
```

## Multi-Session

```bash
# Terminal 1
./bridge-client.sh imessage work1

# Terminal 2
./bridge-client.sh telegram api-dev
```

**Routing:**
- `@work1 message` → routes to Terminal 1 (via iMessage)
- `@api-dev message` → routes to Terminal 2 (via Telegram)
- `message` (no prefix) → routes to most recently active session

## Configuration

Config file: `~/.config/lymebridge/config.json`

```json
{
  "socketPath": "/tmp/lymebridge.sock",
  "logLevel": "info",
  "channels": {
    "imessage": {
      "enabled": true,
      "appleId": "your@appleid.com"
    },
    "telegram": {
      "enabled": false,
      "botToken": "123456:ABC...",
      "chatId": "your-chat-id"
    }
  }
}
```

## Requirements

- macOS 13+
- For iMessage:
  - Full Disk Access permission
  - Automation permission for Messages.app
- For Telegram:
  - Bot token from @BotFather
  - Your chat ID

## Security

- **Zero network (iMessage)**: All communication is local
- **Zero dependencies**: Pure Swift, no third-party code
- **Memory-only**: Messages are never written to disk by the daemon
- **Socket hardened**: Permissions 0600, owner-only access
- **Open source**: Fully auditable

## License

MIT
