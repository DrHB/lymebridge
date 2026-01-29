# Lymebridge Design Document v3

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS daemon that bridges iMessage and Telegram to Claude Code terminal sessions.

**Architecture:** Pluggable channel system with two implementations: iMessage (local SQLite + AppleScript) and Telegram (HTTP polling). Both use `[session-name]` prefix for responses.

**Tech Stack:** Swift 5.9+, Foundation, SQLite3, AppleScript, HTTP (URLSession for Telegram)

---

## Scope

**In scope:**
- iMessage channel (local, zero network)
- Telegram channel (simple HTTP polling, no SDK)
- `[session-name]` prefix for all responses (consistent UX)
- Multi-session support with `@session` routing
- **Works with Claude Code AND OpenAI Codex CLI** (tool-agnostic)

**Out of scope (future):**
- Discord, Slack (can add later using same MessageChannel protocol)
- Custom sender identities per session
- Deep integration hooks (v1 uses generic bridge client)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           macOS                                  │
│                                                                  │
│  ┌─────────────┐     ┌──────────────────────────────────────┐   │
│  │  iMessage   │────►│         Lymebridge Daemon             │   │
│  │  (SQLite)   │     │                                      │   │
│  └─────────────┘     │  ┌──────────────┐  ┌──────────────┐  │   │
│                      │  │   Channel    │  │    Socket    │  │   │
│  ┌─────────────┐     │  │   Manager    │  │    Server    │  │   │
│  │  Telegram   │────►│  │              │  │              │  │   │
│  │  (HTTP)     │     │  │ - iMessage   │  │ - Sessions   │  │   │
│  └─────────────┘     │  │ - Telegram   │  │ - Routing    │  │   │
│                      │  └──────────────┘  └──────┬───────┘  │   │
│                      └───────────────────────────┼──────────┘   │
│                                                  │               │
│                          Unix Socket /tmp/lymebridge.sock        │
│                                                  │               │
│  ┌───────────────────────────────────────────────▼───────────┐  │
│  │  Terminal                                                  │  │
│  │  $ /bridge imessage work1                                  │  │
│  │  $ /bridge telegram api-dev                                │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Message Flow

**iMessage:**
```
You send to yourself: "@work1 status?"
  → Daemon reads from ~/Library/Messages/chat.db
  → Routes to session "work1"
  → Response: "[work1] All good!"
  → Daemon sends via AppleScript back to yourself
```

**Telegram:**
```
You message your bot: "@api-dev check logs"
  → Daemon polls https://api.telegram.org/bot<TOKEN>/getUpdates
  → Routes to session "api-dev"
  → Response: "[api-dev] No errors found"
  → Daemon POSTs to https://api.telegram.org/bot<TOKEN>/sendMessage
```

---

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
    "telegram": {
      "enabled": false,
      "botToken": "123456789:ABCdefGHIjklMNOpqrsTUVwxyz",
      "chatId": "your-chat-id"
    }
  }
}
```

---

## Implementation Tasks

### Task 7: IMessageChannel Implementation

**Files:**
- Create: `Sources/lymebridge/Channels/IMessageChannel.swift`

**What it does:**
- Watches `~/Library/Messages/chat.db` using FSEvents
- Reads new self-messages using SQLite
- Sends responses via AppleScript
- Implements `MessageChannel` protocol

**Code:**

```swift
import Foundation
import SQLite3
import CoreServices

final class IMessageChannel: MessageChannel {
    let id = "imessage"
    let displayName = "iMessage"

    private let appleId: String
    private let dbPath: String
    private var db: OpaquePointer?
    private var lastRowId: Int64 = 0
    private var stream: FSEventStreamRef?
    private var _isRunning = false

    var isRunning: Bool { _isRunning }
    var onMessage: ((IncomingMessage) -> Void)?

    init(appleId: String) {
        self.appleId = appleId
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/Library/Messages/chat.db"
    }

    func start() throws {
        // Open database
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ChannelError.connectionFailed("Cannot open Messages database")
        }
        lastRowId = getCurrentMaxRowId()

        // Start watching for changes
        startWatching()
        _isRunning = true
        print("[imessage] Started, watching from ROWID > \(lastRowId)")
    }

    func stop() {
        stopWatching()
        if let db = db { sqlite3_close(db) }
        db = nil
        _isRunning = false
    }

    func send(text: String, to recipient: String) -> Bool {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
            tell application "Messages"
                set targetService to 1st account whose service type = iMessage
                set targetBuddy to participant "\(appleId)" of targetService
                send "\(escaped)" to targetBuddy
            end tell
            """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        appleScript.executeAndReturnError(&error)
        return error == nil
    }

    // MARK: - Private

    private func getCurrentMaxRowId() -> Int64 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT MAX(ROWID) FROM message", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return sqlite3_column_int64(stmt, 0)
    }

    private func checkForNewMessages() {
        guard let db = db else { return }

        let sql = """
            SELECT m.ROWID, m.text, m.date
            FROM message m
            JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            JOIN chat c ON cmj.chat_id = c.ROWID
            WHERE m.is_from_me = 1 AND m.ROWID > ?
              AND (c.chat_identifier = ? OR c.chat_identifier LIKE ?)
              AND m.text IS NOT NULL AND m.text != ''
            ORDER BY m.ROWID ASC
            """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_bind_int64(stmt, 1, lastRowId)
        sqlite3_bind_text(stmt, 2, appleId, -1, nil)
        sqlite3_bind_text(stmt, 3, "%\(appleId)%", -1, nil)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(stmt, 0)
            guard let textPtr = sqlite3_column_text(stmt, 1) else { continue }
            let text = String(cString: textPtr)

            // Skip our own responses
            if text.hasPrefix("[") && text.contains("]") { continue }

            lastRowId = max(lastRowId, rowId)

            let msg = IncomingMessage(
                channelId: id,
                text: text,
                sender: appleId
            )
            onMessage?(msg)
        }
    }

    private func startWatching() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let messagesDir = "\(home)/Library/Messages" as CFString
        let pathsToWatch = [messagesDir] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        stream = FSEventStreamCreate(
            nil,
            { (_, info, _, _, _, _) in
                guard let info = info else { return }
                let channel = Unmanaged<IMessageChannel>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async { channel.checkForNewMessages() }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream = stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    private func stopWatching() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
```

**Verify:** `swift build`
**Commit:** `feat: add IMessageChannel implementation`

---

### Task 8: Update Session & Protocol for channels

**Files:**
- Modify: `Sources/lymebridge/Socket/Session.swift`
- Modify: `Sources/lymebridge/Socket/Protocol.swift`

**Changes to Session.swift:**
```swift
final class Session {
    let name: String
    let channel: String           // NEW
    let fileDescriptor: Int32
    var lastActive: Date
    // ... rest unchanged

    init(name: String, channel: String, fileDescriptor: Int32) {
        self.name = name
        self.channel = channel    // NEW
        self.fileDescriptor = fileDescriptor
        self.lastActive = Date()
    }
}
```

**Changes to Protocol.swift - ClientMessage.register:**
```swift
case register(name: String, channel: String)  // Add channel

// Update encoding/decoding to include channel
```

**Verify:** `swift build`
**Commit:** `feat: add channel to Session and Protocol`

---

### Task 9: Update Config for multi-channel

**Files:**
- Modify: `Sources/lymebridge/Daemon/Config.swift`

**New Config structure:**
```swift
struct ChannelConfig: Codable {
    let enabled: Bool
}

struct IMessageConfig: Codable {
    let enabled: Bool
    let appleId: String
}

struct TelegramConfig: Codable {
    let enabled: Bool
    let botToken: String
    let chatId: String
}

struct ChannelsConfig: Codable {
    let imessage: IMessageConfig?
    let telegram: TelegramConfig?
}

struct Config: Codable {
    let socketPath: String
    let logLevel: String
    let channels: ChannelsConfig

    // ... load/save methods
}
```

**Verify:** `swift build`
**Commit:** `feat: update Config for multi-channel support`

---

### Task 10: ChannelManager & Router

**Files:**
- Create: `Sources/lymebridge/Daemon/ChannelManager.swift`
- Create: `Sources/lymebridge/Router/MessageRouter.swift`

**ChannelManager:**
```swift
final class ChannelManager {
    private var channels: [String: MessageChannel] = [:]
    var onMessage: ((IncomingMessage) -> Void)?

    func register(_ channel: MessageChannel) {
        channels[channel.id] = channel
        channel.onMessage = { [weak self] msg in
            self?.onMessage?(msg)
        }
    }

    func start() throws {
        for channel in channels.values {
            try channel.start()
        }
    }

    func stop() {
        for channel in channels.values {
            channel.stop()
        }
    }

    func send(text: String, via channelId: String, to recipient: String) -> Bool {
        channels[channelId]?.send(text: text, to: recipient) ?? false
    }

    func getEnabledChannels() -> [String] {
        channels.filter { $0.value.isRunning }.map { $0.key }
    }
}
```

**MessageRouter:**
```swift
struct RoutedMessage {
    let sessionName: String?
    let text: String
}

final class MessageRouter {
    func parse(_ input: String) -> RoutedMessage {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("@") else {
            return RoutedMessage(sessionName: nil, text: trimmed)
        }
        guard let spaceIndex = trimmed.firstIndex(of: " ") else {
            return RoutedMessage(sessionName: String(trimmed.dropFirst()), text: "")
        }
        let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<spaceIndex])
        let text = String(trimmed[trimmed.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespaces)
        return RoutedMessage(sessionName: name, text: text)
    }
}
```

**Verify:** `swift build`
**Commit:** `feat: add ChannelManager and MessageRouter`

---

### Task 11: Main Daemon

**Files:**
- Create: `Sources/lymebridge/Daemon/Daemon.swift`
- Modify: `Sources/lymebridge/main.swift`

**Daemon.swift** - orchestrates everything:
- Loads config
- Creates ChannelManager with enabled channels
- Creates SocketServer
- Routes incoming messages to sessions
- Routes responses back through correct channel

**main.swift** - CLI:
- `lymebridge setup` - interactive config creation
- `lymebridge` - run daemon

**Verify:** `swift build`
**Commit:** `feat: add main Daemon`

---

### Task 12: TelegramChannel Implementation

**Files:**
- Create: `Sources/lymebridge/Channels/TelegramChannel.swift`

**Simple HTTP polling implementation:**
```swift
final class TelegramChannel: MessageChannel {
    let id = "telegram"
    let displayName = "Telegram"

    private let botToken: String
    private let chatId: String
    private var lastUpdateId: Int = 0
    private var pollTimer: Timer?
    private var _isRunning = false

    var isRunning: Bool { _isRunning }
    var onMessage: ((IncomingMessage) -> Void)?

    init(botToken: String, chatId: String) {
        self.botToken = botToken
        self.chatId = chatId
    }

    func start() throws {
        _isRunning = true
        startPolling()
        print("[telegram] Started polling")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        _isRunning = false
    }

    func send(text: String, to recipient: String) -> Bool {
        let url = URL(string: "https://api.telegram.org/bot\(botToken)/sendMessage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["chat_id": chatId, "text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                success = true
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return success
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollUpdates()
        }
    }

    private func pollUpdates() {
        let url = URL(string: "https://api.telegram.org/bot\(botToken)/getUpdates?offset=\(lastUpdateId + 1)&timeout=0")!

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data else { return }
            self.processUpdates(data)
        }.resume()
    }

    private func processUpdates(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["result"] as? [[String: Any]] else { return }

        for update in results {
            if let updateId = update["update_id"] as? Int {
                lastUpdateId = max(lastUpdateId, updateId)
            }

            if let message = update["message"] as? [String: Any],
               let text = message["text"] as? String,
               let chat = message["chat"] as? [String: Any],
               let msgChatId = chat["id"] as? Int,
               String(msgChatId) == chatId {

                // Skip our own responses
                if text.hasPrefix("[") && text.contains("]") { continue }

                let msg = IncomingMessage(
                    channelId: id,
                    text: text,
                    sender: chatId
                )
                DispatchQueue.main.async { self.onMessage?(msg) }
            }
        }
    }
}
```

**Verify:** `swift build`
**Commit:** `feat: add TelegramChannel implementation`

---

### Task 13: Support Files

**Files:**
- Create: `com.lymebridge.daemon.plist`
- Create: `install.sh`
- Create: `README.md`
- Create: `bridge-client.sh`

**Commit:** `feat: add support files`

---

### Task 14: Final Build & Test

1. `swift build -c release`
2. `./install.sh`
3. `lymebridge setup`
4. Test iMessage flow
5. Test Telegram flow (if configured)

**Commit:** `chore: final verification`

---

## Summary

| Task | Component | Status |
|------|-----------|--------|
| 1-6 | Foundation | ✅ Done |
| 7 | IMessageChannel | Pending |
| 8 | Session + Protocol update | Pending |
| 9 | Config update | Pending |
| 10 | ChannelManager + Router | Pending |
| 11 | Main Daemon | Pending |
| 12 | TelegramChannel | Pending |
| 13 | Support files | Pending |
| 14 | Final test | Pending |

**Total:** ~800 lines of Swift, 2 channels, zero external dependencies
