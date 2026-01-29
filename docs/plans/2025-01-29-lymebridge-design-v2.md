# Lymebridge Design Document v2

**Date:** 2025-01-29
**Status:** Updated - Multi-Channel Support

## Overview

Lymebridge is a macOS daemon that bridges **multiple messaging platforms** to Claude Code terminal sessions. v2 adds support for iMessage, Slack, Telegram, and Discord with a pluggable channel architecture.

## Updated Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              macOS                                       │
│                                                                          │
│  ┌─────────────┐                                                         │
│  │  iMessage   │───┐                                                     │
│  └─────────────┘   │                                                     │
│  ┌─────────────┐   │     ┌──────────────────────────────────────────┐   │
│  │    Slack    │───┼────►│          Lymebridge Daemon                │   │
│  └─────────────┘   │     │                                          │   │
│  ┌─────────────┐   │     │  ┌────────────┐    ┌─────────────────┐   │   │
│  │  Telegram   │───┘     │  │  Channel   │    │  Socket Server  │   │   │
│  └─────────────┘         │  │  Manager   │───►│                 │   │   │
│  ┌─────────────┐         │  └────────────┘    └────────┬────────┘   │   │
│  │   Discord   │─────────│                             │            │   │
│  └─────────────┘         └─────────────────────────────┼────────────┘   │
│                                                        │                 │
│                              Unix Socket /tmp/lymebridge.sock            │
│                                                        │                 │
│  ┌─────────────────────────────────────────────────────▼────────────┐   │
│  │                         Terminal                                  │   │
│  │  $ /bridge imessage work1                                         │   │
│  │  ✓ Connected to lymebridge via iMessage as "work1"                │   │
│  │                                                                   │   │
│  │  $ /bridge slack api-dev                                          │   │
│  │  ✓ Connected to lymebridge via Slack as "api-dev"                 │   │
│  └───────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

## Bridge Command Interface

```bash
# Connect via specific channel
/bridge imessage work1      # Use iMessage
/bridge slack api-dev       # Use Slack
/bridge telegram mobile     # Use Telegram
/bridge discord gaming      # Use Discord

# List available channels
/bridge --list

# Disconnect
/bridge --disconnect
```

## Message Routing

**Sending to sessions:**
```
iMessage: @work1 status?        → routes to "work1" session
Slack: @api-dev check logs      → routes to "api-dev" session
```

**Responses route back through the SAME channel:**
```
work1 (via iMessage) responds   → [work1] Response sent to iMessage
api-dev (via Slack) responds    → [api-dev] Response sent to Slack
```

## Configuration

`~/.config/lymebridge/config.json`:

```json
{
  "socketPath": "/tmp/lymebridge.sock",
  "logLevel": "info",

  "channels": {
    "imessage": {
      "enabled": true,
      "appleId": "your@appleid.com"
    },
    "slack": {
      "enabled": false,
      "botToken": "xoxb-your-bot-token",
      "appToken": "xapp-your-app-token"
    },
    "telegram": {
      "enabled": false,
      "botToken": "123456:ABC-your-bot-token"
    },
    "discord": {
      "enabled": false,
      "botToken": "your-discord-bot-token"
    }
  }
}
```

## Updated Socket Protocol

**Register with channel:**
```json
{"type": "register", "name": "work1", "channel": "imessage"}
```

**Server ack includes channel:**
```json
{"type": "ack", "channel": "imessage"}
```

**Messages include source channel:**
```json
{"type": "message", "text": "status?", "channel": "imessage"}
```

## Channel Protocol

All channels implement `MessageChannel`:

```swift
protocol MessageChannel: AnyObject {
    var id: String { get }              // "imessage", "slack", etc.
    var displayName: String { get }     // "iMessage", "Slack", etc.
    var isRunning: Bool { get }

    var onMessage: ((IncomingMessage) -> Void)? { get set }

    func start() throws
    func stop()
    func send(text: String, to recipient: String) -> Bool
}
```

## Implementation Priority

### Phase 1: iMessage (MVP)
- [x] MessageChannel protocol
- [ ] IMessageChannel implementation
- [ ] Basic daemon with single channel
- [ ] Bridge client

### Phase 2: Multi-Channel Foundation
- [ ] ChannelManager (manages multiple channels)
- [ ] Updated config with channels section
- [ ] Channel selection in bridge command

### Phase 3: Additional Channels (Future)
- [ ] SlackChannel (using Slack Bolt)
- [ ] TelegramChannel (using grammY or similar)
- [ ] DiscordChannel (using discord.js or similar)

## Updated Project Structure

```
lymebridge/
├── Sources/
│   └── lymebridge/
│       ├── main.swift
│       ├── Daemon/
│       │   ├── Daemon.swift
│       │   ├── Config.swift
│       │   └── ChannelManager.swift      # NEW: manages all channels
│       ├── Channels/
│       │   ├── MessageChannel.swift      # Protocol
│       │   ├── IMessageChannel.swift     # iMessage implementation
│       │   ├── SlackChannel.swift        # Future
│       │   ├── TelegramChannel.swift     # Future
│       │   └── DiscordChannel.swift      # Future
│       ├── Socket/
│       │   ├── Protocol.swift
│       │   ├── Session.swift             # Now includes channel info
│       │   └── SocketServer.swift
│       └── Router/
│           └── MessageRouter.swift
├── Package.swift
├── install.sh
├── com.lymebridge.daemon.plist
└── README.md
```

## Session Model Update

```swift
final class Session {
    let name: String
    let channel: String           // NEW: which channel this session uses
    let fileDescriptor: Int32
    var lastActive: Date
    // ...
}
```

## Remaining Tasks

| # | Task | Status |
|---|------|--------|
| 1 | Project Setup | ✅ Done |
| 2 | Config Module | ✅ Done |
| 3 | Socket Protocol | ✅ Done |
| 4 | Session Model | ✅ Done |
| 5 | Socket Server | ✅ Done |
| 6 | MessageChannel Protocol | ✅ Done |
| 7 | IMessageChannel | 🔄 Next |
| 8 | Update Session with channel | Pending |
| 9 | Update Config for channels | Pending |
| 10 | Message Router | Pending |
| 11 | Main Daemon | Pending |
| 12 | Support files (plist, install, README) | Pending |
| 13 | Bridge client with channel arg | Pending |
| 14 | Final test | Pending |
