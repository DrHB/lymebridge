# Lymebridge Design Document

**Date:** 2025-01-29
**Status:** Approved

## Overview

Lymebridge is a macOS background daemon that bridges iMessage to active Claude Code terminal sessions. Users send messages to themselves via iMessage, and the daemon routes them to registered Claude Code sessions. Responses are sent back via iMessage.

## Core Requirements

1. **Two-way communication** - Send via iMessage, receive response via iMessage
2. **Self-messaging only** - Only processes messages you send to yourself (secure)
3. **Multi-session support** - Multiple Claude Code sessions can register with custom names
4. **Session routing** - Use `@session-name` prefix to target specific sessions
5. **Background daemon** - No UI, runs invisibly
6. **Zero network** - All communication local, nothing sent to external services
7. **Zero dependencies** - Pure Swift, Apple frameworks only
8. **Easy installation** - Homebrew or curl one-liner from GitHub

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS                                     │
│                                                                  │
│  ┌──────────────┐         ┌──────────────────────────────────┐  │
│  │   iMessage   │         │     Lymebridge Daemon            │  │
│  │     App      │         │     (Swift Background Process)   │  │
│  │              │         │                                  │  │
│  │  You → You   │────────►│  1. Watch ~/Library/Messages/    │  │
│  │  "@work1 hi" │         │  2. Parse @session routing       │  │
│  │              │◄────────│  3. Forward to Claude Code       │  │
│  │  "[work1]    │         │  4. Send response back           │  │
│  │   Hello!"    │         │                                  │  │
│  └──────────────┘         └───────────────┬──────────────────┘  │
│                                           │                      │
│                           Unix Socket /tmp/lymebridge.sock       │
│                                           │                      │
│  ┌────────────────────────────────────────▼──────────────────┐  │
│  │                    Terminal                                │  │
│  │  $ claude                                                  │  │
│  │  > /bridge work1                                           │  │
│  │  ✓ Registered as "work1"                                   │  │
│  │  > You: hi                                                 │  │
│  │  > Claude: Hello!                                          │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Daemon (main process)

- Runs as LaunchAgent (starts on login)
- Manages lifecycle of all other components
- Handles graceful shutdown

### 2. DatabaseWatcher

- Monitors `~/Library/Messages/chat.db` using FSEvents
- Triggers on file changes
- Debounces rapid changes

### 3. MessageReader

- SQLite queries to read new messages
- Tracks last seen ROWID to only process new messages
- Filters: `is_from_me = 1` AND self-chat only AND after daemon start

```sql
SELECT message.ROWID, message.text, message.date
FROM message
JOIN chat_message_join ON message.ROWID = chat_message_join.message_id
JOIN chat ON chat_message_join.chat_id = chat.ROWID
WHERE message.is_from_me = 1
  AND message.ROWID > ?
  AND chat.chat_identifier = ?  -- your Apple ID
ORDER BY message.ROWID ASC
```

### 4. MessageSender

- Sends iMessages via AppleScript/NSAppleScript
- Formats responses with `[session-name]` prefix

```applescript
tell application "Messages"
    set targetService to 1st account whose service type = iMessage
    set targetBuddy to participant "your@appleid.com" of targetService
    send "[work1] Response text here" to targetBuddy
end tell
```

### 5. SocketServer

- Unix domain socket at `/tmp/lymebridge.sock`
- Permissions: `0600` (owner only)
- Accepts connections from Claude Code sessions
- Manages multiple concurrent sessions

### 6. Session

- Represents one connected Claude Code instance
- Stores: name, socket file descriptor, last active timestamp
- Handles incoming/outgoing message relay

### 7. MessageRouter

- Parses `@session-name` prefix from incoming messages
- Routes to specific session or most recently active
- Special: `@all` broadcasts to all sessions (optional)

## Socket Protocol

JSON lines over Unix socket. Each message is a single JSON object followed by newline.

### Client → Server

**Register:**
```json
{"type": "register", "name": "work1"}
```

**Response (Claude's output):**
```json
{"type": "response", "text": "Here are the files..."}
```

**Disconnect:**
```json
{"type": "disconnect"}
```

### Server → Client

**Message (user input from iMessage):**
```json
{"type": "message", "text": "what files did we edit?"}
```

**Ack:**
```json
{"type": "ack"}
```

**Error:**
```json
{"type": "error", "message": "Session name already taken"}
```

## Multi-Session Routing

### Message format

- **To specific session:** `@work1 what files did we edit?`
- **To most recent session:** `what files did we edit?` (no prefix)
- **Response format:** `[work1] We edited 3 files...`

### Session tracking

```swift
struct Session {
    let name: String
    let socket: FileDescriptor
    var lastActive: Date
}

// Daemon maintains:
var sessions: [String: Session] = [:]
var mostRecentSession: String?
```

## Security Model

| Safeguard | Implementation |
|-----------|----------------|
| Zero network | No Network.framework, no URLSession, compile-time verifiable |
| Zero dependencies | Only Foundation, SQLite3, OSLog |
| Memory-only | Messages never written to disk by daemon |
| Minimal DB read | Only query ROWID > lastSeen, don't scan history |
| Socket hardened | Mode 0600, strict JSON validation |
| Self-only | Only process messages in self→self chat |
| Notarized | Apple-signed binary for Gatekeeper |
| Open source | Fully auditable |

## Required Permissions

1. **Full Disk Access** - Required to read `~/Library/Messages/chat.db`
2. **Automation (Messages.app)** - Required to send via AppleScript

## Installation

### Homebrew (preferred)

```bash
brew tap username/lymebridge
brew install lymebridge
brew services start lymebridge
```

### Manual

```bash
curl -fsSL https://raw.githubusercontent.com/username/lymebridge/main/install.sh | bash
```

### From source

```bash
git clone https://github.com/username/lymebridge.git
cd lymebridge
swift build -c release
sudo cp .build/release/lymebridge /usr/local/bin/
cp com.lymebridge.daemon.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.lymebridge.daemon.plist
```

## First-time Setup

```bash
lymebridge setup
```

1. Prompts for Apple ID / phone number (for self-chat filtering)
2. Guides through Full Disk Access permission
3. Guides through Automation permission
4. Creates config at `~/.config/lymebridge/config.json`
5. Starts daemon

## Claude Code Integration

User runs in their Claude Code session:

```
/bridge work1
```

This:
1. Connects to `/tmp/lymebridge.sock`
2. Sends register packet with name "work1"
3. Receives ack
4. Enters relay mode (stdin/stdout ↔ socket)

## Project Structure

```
lymebridge/
├── Sources/
│   └── lymebridge/
│       ├── main.swift
│       ├── Daemon/
│       │   ├── Daemon.swift
│       │   └── Config.swift
│       ├── Messages/
│       │   ├── DatabaseWatcher.swift
│       │   ├── MessageReader.swift
│       │   └── MessageSender.swift
│       ├── Socket/
│       │   ├── SocketServer.swift
│       │   ├── Session.swift
│       │   └── Protocol.swift
│       └── Router/
│           └── MessageRouter.swift
├── Package.swift
├── install.sh
├── com.lymebridge.daemon.plist
├── README.md
└── docs/
    └── plans/
        └── 2025-01-29-lymebridge-design.md
```

## Config File

`~/.config/lymebridge/config.json`:

```json
{
  "appleId": "your@appleid.com",
  "socketPath": "/tmp/lymebridge.sock",
  "logLevel": "info"
}
```

## Future Enhancements (out of scope for v1)

- [ ] Multiple Apple ID support
- [ ] Message history in daemon (opt-in)
- [ ] Web UI for session management
- [ ] Telegram/Signal alternative backends
- [ ] Encryption for socket communication
