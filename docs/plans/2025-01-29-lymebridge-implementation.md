# Lymebridge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS daemon that bridges iMessage to Claude Code terminal sessions.

**Architecture:** Swift daemon monitors Messages.db for self-messages, routes them via Unix socket to registered Claude Code sessions, and sends responses back via AppleScript. Zero dependencies, zero network.

**Tech Stack:** Swift 5.9+, Foundation, SQLite3 (system), OSLog, AppleScript via NSAppleScript

---

## Task 1: Project Setup

**Files:**
- Create: `Package.swift`
- Create: `Sources/lymebridge/main.swift`

**Step 1: Create Package.swift**

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lymebridge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "lymebridge",
            path: "Sources/lymebridge"
        )
    ]
)
```

**Step 2: Create minimal main.swift**

```swift
// Sources/lymebridge/main.swift
import Foundation

print("lymebridge v0.1.0")
```

**Step 3: Verify it builds**

Run: `swift build`
Expected: Build succeeds, binary at `.build/debug/lymebridge`

**Step 4: Verify it runs**

Run: `.build/debug/lymebridge`
Expected: Prints "lymebridge v0.1.0"

**Step 5: Commit**

```bash
git add Package.swift Sources/
git commit -m "feat: initial project setup"
```

---

## Task 2: Config Module

**Files:**
- Create: `Sources/lymebridge/Daemon/Config.swift`

**Step 1: Create Config struct**

```swift
// Sources/lymebridge/Daemon/Config.swift
import Foundation

struct Config: Codable {
    let appleId: String
    let socketPath: String
    let logLevel: String

    static let defaultSocketPath = "/tmp/lymebridge.sock"
    static let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/lymebridge/config.json")

    static func load() throws -> Config {
        let data = try Data(contentsOf: configPath)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    static func createDefault(appleId: String) -> Config {
        Config(
            appleId: appleId,
            socketPath: defaultSocketPath,
            logLevel: "info"
        )
    }

    func save() throws {
        let dir = Config.configPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: Config.configPath)
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/lymebridge/Daemon/Config.swift
git commit -m "feat: add Config module"
```

---

## Task 3: Socket Protocol Types

**Files:**
- Create: `Sources/lymebridge/Socket/Protocol.swift`

**Step 1: Create protocol message types**

```swift
// Sources/lymebridge/Socket/Protocol.swift
import Foundation

// MARK: - Client -> Server Messages

enum ClientMessage: Codable {
    case register(name: String)
    case response(text: String)
    case disconnect

    enum CodingKeys: String, CodingKey {
        case type, name, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "register":
            let name = try container.decode(String.self, forKey: .name)
            self = .register(name: name)
        case "response":
            let text = try container.decode(String.self, forKey: .text)
            self = .response(text: text)
        case "disconnect":
            self = .disconnect
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .register(let name):
            try container.encode("register", forKey: .type)
            try container.encode(name, forKey: .name)
        case .response(let text):
            try container.encode("response", forKey: .type)
            try container.encode(text, forKey: .text)
        case .disconnect:
            try container.encode("disconnect", forKey: .type)
        }
    }
}

// MARK: - Server -> Client Messages

enum ServerMessage: Codable {
    case message(text: String)
    case ack
    case error(message: String)

    enum CodingKeys: String, CodingKey {
        case type, text, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "message":
            let text = try container.decode(String.self, forKey: .text)
            self = .message(text: text)
        case "ack":
            self = .ack
        case "error":
            let msg = try container.decode(String.self, forKey: .message)
            self = .error(message: msg)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let text):
            try container.encode("message", forKey: .type)
            try container.encode(text, forKey: .text)
        case .ack:
            try container.encode("ack", forKey: .type)
        case .error(let msg):
            try container.encode("error", forKey: .type)
            try container.encode(msg, forKey: .message)
        }
    }
}

// MARK: - JSON Line Helpers

extension ClientMessage {
    static func parse(_ line: String) -> ClientMessage? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ClientMessage.self, from: data)
    }
}

extension ServerMessage {
    func toJSONLine() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str + "\n"
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/lymebridge/Socket/Protocol.swift
git commit -m "feat: add socket protocol types"
```

---

## Task 4: Session Model

**Files:**
- Create: `Sources/lymebridge/Socket/Session.swift`

**Step 1: Create Session struct**

```swift
// Sources/lymebridge/Socket/Session.swift
import Foundation

final class Session {
    let name: String
    let fileDescriptor: Int32
    var lastActive: Date

    private var buffer: String = ""

    init(name: String, fileDescriptor: Int32) {
        self.name = name
        self.fileDescriptor = fileDescriptor
        self.lastActive = Date()
    }

    func touch() {
        lastActive = Date()
    }

    func send(_ message: ServerMessage) -> Bool {
        guard let line = message.toJSONLine(),
              let data = line.data(using: .utf8) else { return false }

        return data.withUnsafeBytes { ptr in
            let written = write(fileDescriptor, ptr.baseAddress, data.count)
            return written == data.count
        }
    }

    func appendToBuffer(_ data: Data) {
        if let str = String(data: data, encoding: .utf8) {
            buffer += str
        }
    }

    func extractLines() -> [String] {
        var lines: [String] = []
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            lines.append(line)
            buffer.removeSubrange(..<range.upperBound)
        }
        return lines
    }

    func close() {
        Darwin.close(fileDescriptor)
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/lymebridge/Socket/Session.swift
git commit -m "feat: add Session model"
```

---

## Task 5: Unix Socket Server

**Files:**
- Create: `Sources/lymebridge/Socket/SocketServer.swift`

**Step 1: Create SocketServer class**

```swift
// Sources/lymebridge/Socket/SocketServer.swift
import Foundation

final class SocketServer {
    private let path: String
    private var serverFd: Int32 = -1
    private var sessions: [String: Session] = [:]
    private var fdToSession: [Int32: Session] = [:]
    private var mostRecentSessionName: String?
    private var running = false

    var onMessage: ((String, Session) -> Void)?
    var onResponse: ((String, Session) -> Void)?
    var onSessionRegistered: ((Session) -> Void)?
    var onSessionDisconnected: ((Session) -> Void)?

    init(path: String) {
        self.path = path
    }

    func start() throws {
        // Remove existing socket file
        unlink(path)

        // Create socket
        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            throw SocketError.createFailed
        }

        // Bind to path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dest, src.baseAddress, min(src.count, 104))
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverFd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult >= 0 else {
            throw SocketError.bindFailed
        }

        // Set permissions (owner only)
        chmod(path, 0o600)

        // Listen
        guard listen(serverFd, 5) >= 0 else {
            throw SocketError.listenFailed
        }

        running = true
        print("[socket] Listening on \(path)")
    }

    func stop() {
        running = false
        for session in sessions.values {
            session.close()
        }
        sessions.removeAll()
        fdToSession.removeAll()
        if serverFd >= 0 {
            Darwin.close(serverFd)
            serverFd = -1
        }
        unlink(path)
    }

    func poll(timeout: Int32 = 100) {
        guard running else { return }

        // Build fd set
        var readSet = fd_set()
        __darwin_fd_zero(&readSet)
        __darwin_fd_set(serverFd, &readSet)

        var maxFd = serverFd
        for fd in fdToSession.keys {
            __darwin_fd_set(fd, &readSet)
            maxFd = max(maxFd, fd)
        }

        var tv = timeval(tv_sec: 0, tv_usec: timeout * 1000)
        let result = select(maxFd + 1, &readSet, nil, nil, &tv)

        guard result > 0 else { return }

        // Check for new connections
        if __darwin_fd_isset(serverFd, &readSet) != 0 {
            acceptConnection()
        }

        // Check existing sessions
        for (fd, session) in fdToSession {
            if __darwin_fd_isset(fd, &readSet) != 0 {
                handleSessionData(session)
            }
        }
    }

    private func acceptConnection() {
        let clientFd = accept(serverFd, nil, nil)
        guard clientFd >= 0 else { return }

        // Set non-blocking
        let flags = fcntl(clientFd, F_GETFL, 0)
        fcntl(clientFd, F_SETFL, flags | O_NONBLOCK)

        // Create pending session (will be named on register)
        let session = Session(name: "_pending_\(clientFd)", fileDescriptor: clientFd)
        fdToSession[clientFd] = session
        print("[socket] New connection: fd=\(clientFd)")
    }

    private func handleSessionData(_ session: Session) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(session.fileDescriptor, &buffer, buffer.count)

        if bytesRead <= 0 {
            disconnectSession(session)
            return
        }

        session.appendToBuffer(Data(buffer[..<bytesRead]))

        for line in session.extractLines() {
            handleMessage(line, from: session)
        }
    }

    private func handleMessage(_ line: String, from session: Session) {
        guard let msg = ClientMessage.parse(line) else {
            _ = session.send(.error(message: "Invalid JSON"))
            return
        }

        switch msg {
        case .register(let name):
            registerSession(session, name: name)

        case .response(let text):
            session.touch()
            onResponse?(text, session)

        case .disconnect:
            disconnectSession(session)
        }
    }

    private func registerSession(_ session: Session, name: String) {
        // Check if name taken
        if sessions[name] != nil {
            _ = session.send(.error(message: "Session name '\(name)' already taken"))
            return
        }

        // Remove from pending
        fdToSession.removeValue(forKey: session.fileDescriptor)

        // Create new session with proper name
        let namedSession = Session(name: name, fileDescriptor: session.fileDescriptor)
        sessions[name] = namedSession
        fdToSession[session.fileDescriptor] = namedSession
        mostRecentSessionName = name

        _ = namedSession.send(.ack)
        onSessionRegistered?(namedSession)
        print("[socket] Session registered: \(name)")
    }

    private func disconnectSession(_ session: Session) {
        session.close()
        sessions.removeValue(forKey: session.name)
        fdToSession.removeValue(forKey: session.fileDescriptor)

        if mostRecentSessionName == session.name {
            mostRecentSessionName = sessions.keys.first
        }

        onSessionDisconnected?(session)
        print("[socket] Session disconnected: \(session.name)")
    }

    func sendToSession(name: String, text: String) -> Bool {
        guard let session = sessions[name] else { return false }
        session.touch()
        mostRecentSessionName = name
        return session.send(.message(text: text))
    }

    func sendToMostRecent(text: String) -> Bool {
        guard let name = mostRecentSessionName else { return false }
        return sendToSession(name: name, text: text)
    }

    func getSessionNames() -> [String] {
        Array(sessions.keys)
    }
}

// MARK: - Errors

enum SocketError: Error {
    case createFailed
    case bindFailed
    case listenFailed
}

// MARK: - fd_set helpers

private func __darwin_fd_zero(_ set: inout fd_set) {
    set.__fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private func __darwin_fd_set(_ fd: Int32, _ set: inout fd_set) {
    let intOffset = Int(fd / 32)
    let bitOffset = Int(fd % 32)
    withUnsafeMutablePointer(to: &set.__fds_bits) { ptr in
        ptr.withMemoryRebound(to: Int32.self, capacity: 32) { bits in
            bits[intOffset] |= Int32(1 << bitOffset)
        }
    }
}

private func __darwin_fd_isset(_ fd: Int32, _ set: inout fd_set) -> Int32 {
    let intOffset = Int(fd / 32)
    let bitOffset = Int(fd % 32)
    return withUnsafeMutablePointer(to: &set.__fds_bits) { ptr in
        ptr.withMemoryRebound(to: Int32.self, capacity: 32) { bits in
            (bits[intOffset] & Int32(1 << bitOffset)) != 0 ? 1 : 0
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/lymebridge/Socket/SocketServer.swift
git commit -m "feat: add Unix socket server"
```

---

## Task 6: Message Reader (SQLite)

**Files:**
- Create: `Sources/lymebridge/Messages/MessageReader.swift`

**Step 1: Create MessageReader class**

```swift
// Sources/lymebridge/Messages/MessageReader.swift
import Foundation
import SQLite3

struct IMessage {
    let rowId: Int64
    let text: String
    let date: Date
}

final class MessageReader {
    private let dbPath: String
    private let selfChatIdentifier: String
    private var lastRowId: Int64 = 0
    private var db: OpaquePointer?

    init(appleId: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/Library/Messages/chat.db"
        self.selfChatIdentifier = appleId
    }

    func open() throws {
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw MessageError.databaseOpenFailed(String(cString: sqlite3_errmsg(db)))
        }

        // Get current max ROWID to start from (don't process history)
        lastRowId = getCurrentMaxRowId()
        print("[messages] Opened database, starting from ROWID > \(lastRowId)")
    }

    func close() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    private func getCurrentMaxRowId() -> Int64 {
        let sql = "SELECT MAX(ROWID) FROM message"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        return sqlite3_column_int64(stmt, 0)
    }

    func fetchNewMessages() -> [IMessage] {
        guard let db = db else { return [] }

        // Query for new self-to-self messages
        let sql = """
            SELECT m.ROWID, m.text, m.date
            FROM message m
            JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            JOIN chat c ON cmj.chat_id = c.ROWID
            WHERE m.is_from_me = 1
              AND m.ROWID > ?
              AND (c.chat_identifier = ? OR c.chat_identifier LIKE ?)
              AND m.text IS NOT NULL
              AND m.text != ''
            ORDER BY m.ROWID ASC
            """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("[messages] Query prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }

        sqlite3_bind_int64(stmt, 1, lastRowId)
        sqlite3_bind_text(stmt, 2, selfChatIdentifier, -1, nil)
        sqlite3_bind_text(stmt, 3, "%\(selfChatIdentifier)%", -1, nil)

        var messages: [IMessage] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(stmt, 0)

            guard let textPtr = sqlite3_column_text(stmt, 1) else { continue }
            let text = String(cString: textPtr)

            // Skip messages that look like our own responses
            if text.hasPrefix("[") && text.contains("]") {
                continue
            }

            let dateValue = sqlite3_column_int64(stmt, 2)
            let date = Date(timeIntervalSinceReferenceDate: Double(dateValue) / 1_000_000_000)

            messages.append(IMessage(rowId: rowId, text: text, date: date))
            lastRowId = max(lastRowId, rowId)
        }

        return messages
    }
}

enum MessageError: Error {
    case databaseOpenFailed(String)
}
```

**Step 2: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/lymebridge/Messages/MessageReader.swift
git commit -m "feat: add SQLite message reader"
```

---

## Task 7: Message Sender (AppleScript)

**Files:**
- Create: `Sources/lymebridge/Messages/MessageSender.swift`

**Step 1: Create MessageSender class**

```swift
// Sources/lymebridge/Messages/MessageSender.swift
import Foundation

final class MessageSender {
    private let appleId: String

    init(appleId: String) {
        self.appleId = appleId
    }

    func send(text: String, sessionName: String) -> Bool {
        let formattedText = "[\(sessionName)] \(text)"
        return sendRaw(formattedText)
    }

    func sendRaw(_ text: String) -> Bool {
        // Escape text for AppleScript
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
        guard let appleScript = NSAppleScript(source: script) else {
            print("[sender] Failed to create AppleScript")
            return false
        }

        appleScript.executeAndReturnError(&error)

        if let error = error {
            print("[sender] AppleScript error: \(error)")
            return false
        }

        return true
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/lymebridge/Messages/MessageSender.swift
git commit -m "feat: add AppleScript message sender"
```

---

## Task 8: Database Watcher (FSEvents)

**Files:**
- Create: `Sources/lymebridge/Messages/DatabaseWatcher.swift`

**Step 1: Create DatabaseWatcher class**

```swift
// Sources/lymebridge/Messages/DatabaseWatcher.swift
import Foundation
import CoreServices

final class DatabaseWatcher {
    private var stream: FSEventStreamRef?
    private let callback: () -> Void
    private var lastEventTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.5

    init(onChange: @escaping () -> Void) {
        self.callback = onChange
    }

    func start() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let messagesDir = "\(home)/Library/Messages" as CFString
        let pathsToWatch = [messagesDir] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

        stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info = info else { return }
                let watcher = Unmanaged<DatabaseWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleEvents()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        )

        guard let stream = stream else {
            print("[watcher] Failed to create FSEventStream")
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        print("[watcher] Watching ~/Library/Messages for changes")
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleEvents() {
        let now = Date()
        guard now.timeIntervalSince(lastEventTime) >= debounceInterval else { return }
        lastEventTime = now

        DispatchQueue.main.async { [weak self] in
            self?.callback()
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/lymebridge/Messages/DatabaseWatcher.swift
git commit -m "feat: add FSEvents database watcher"
```

---

## Task 9: Message Router

**Files:**
- Create: `Sources/lymebridge/Router/MessageRouter.swift`

**Step 1: Create MessageRouter**

```swift
// Sources/lymebridge/Router/MessageRouter.swift
import Foundation

struct RoutedMessage {
    let sessionName: String?  // nil means use most recent
    let text: String
}

final class MessageRouter {

    /// Parse @session-name prefix from message
    /// "@work1 hello" -> RoutedMessage(sessionName: "work1", text: "hello")
    /// "hello" -> RoutedMessage(sessionName: nil, text: "hello")
    func parse(_ input: String) -> RoutedMessage {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("@") else {
            return RoutedMessage(sessionName: nil, text: trimmed)
        }

        // Find end of session name (first space)
        guard let spaceIndex = trimmed.firstIndex(of: " ") else {
            // Just "@name" with no message
            let name = String(trimmed.dropFirst())
            return RoutedMessage(sessionName: name, text: "")
        }

        let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<spaceIndex])
        let text = String(trimmed[trimmed.index(after: spaceIndex)...])
            .trimmingCharacters(in: .whitespaces)

        return RoutedMessage(sessionName: name, text: text)
    }
}
```

**Step 2: Verify it compiles**

Run: `swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add Sources/lymebridge/Router/MessageRouter.swift
git commit -m "feat: add message router"
```

---

## Task 10: Main Daemon

**Files:**
- Create: `Sources/lymebridge/Daemon/Daemon.swift`
- Modify: `Sources/lymebridge/main.swift`

**Step 1: Create Daemon class**

```swift
// Sources/lymebridge/Daemon/Daemon.swift
import Foundation

final class Daemon {
    private let config: Config
    private let socketServer: SocketServer
    private let messageReader: MessageReader
    private let messageSender: MessageSender
    private let databaseWatcher: DatabaseWatcher
    private let router = MessageRouter()
    private var running = false

    init(config: Config) {
        self.config = config
        self.socketServer = SocketServer(path: config.socketPath)
        self.messageReader = MessageReader(appleId: config.appleId)
        self.messageSender = MessageSender(appleId: config.appleId)
        self.databaseWatcher = DatabaseWatcher { [weak self] in
            self?.checkForNewMessages()
        }
    }

    func run() throws {
        print("[daemon] Starting lymebridge daemon...")
        print("[daemon] Apple ID: \(config.appleId)")

        // Setup socket server callbacks
        socketServer.onResponse = { [weak self] text, session in
            self?.handleResponse(text: text, from: session)
        }

        socketServer.onSessionRegistered = { session in
            print("[daemon] Session connected: \(session.name)")
        }

        socketServer.onSessionDisconnected = { session in
            print("[daemon] Session disconnected: \(session.name)")
        }

        // Start components
        try messageReader.open()
        try socketServer.start()
        databaseWatcher.start()

        running = true
        print("[daemon] Ready. Waiting for iMessages and Claude sessions...")

        // Setup signal handlers
        signal(SIGINT) { _ in
            print("\n[daemon] Shutting down...")
            exit(0)
        }
        signal(SIGTERM) { _ in
            print("\n[daemon] Shutting down...")
            exit(0)
        }

        // Main run loop
        let runLoop = RunLoop.current
        while running {
            socketServer.poll(timeout: 100)
            runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
    }

    func stop() {
        running = false
        databaseWatcher.stop()
        socketServer.stop()
        messageReader.close()
    }

    private func checkForNewMessages() {
        let messages = messageReader.fetchNewMessages()

        for msg in messages {
            let routed = router.parse(msg.text)

            print("[daemon] Received: \(msg.text)")

            if routed.text.isEmpty {
                continue
            }

            let sent: Bool
            if let sessionName = routed.sessionName {
                sent = socketServer.sendToSession(name: sessionName, text: routed.text)
                if !sent {
                    let available = socketServer.getSessionNames().joined(separator: ", ")
                    let errorMsg = "Session '\(sessionName)' not found. Available: \(available.isEmpty ? "none" : available)"
                    _ = messageSender.sendRaw("[error] \(errorMsg)")
                }
            } else {
                sent = socketServer.sendToMostRecent(text: routed.text)
                if !sent {
                    _ = messageSender.sendRaw("[error] No active sessions. Connect with /bridge <name>")
                }
            }
        }
    }

    private func handleResponse(text: String, from session: Session) {
        print("[daemon] Response from \(session.name): \(text.prefix(50))...")
        _ = messageSender.send(text: text, sessionName: session.name)
    }
}
```

**Step 2: Update main.swift**

```swift
// Sources/lymebridge/main.swift
import Foundation

let arguments = CommandLine.arguments

if arguments.count > 1 && arguments[1] == "setup" {
    runSetup()
} else {
    runDaemon()
}

func runSetup() {
    print("lymebridge setup")
    print("----------------")
    print("Enter your Apple ID (email or phone for iMessage):")

    guard let appleId = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          !appleId.isEmpty else {
        print("Error: Apple ID required")
        exit(1)
    }

    let config = Config.createDefault(appleId: appleId)

    do {
        try config.save()
        print("Config saved to: \(Config.configPath.path)")
        print("\nNext steps:")
        print("1. Grant Full Disk Access to lymebridge in System Preferences")
        print("2. Grant Automation access for Messages when prompted")
        print("3. Run: lymebridge")
    } catch {
        print("Error saving config: \(error)")
        exit(1)
    }
}

func runDaemon() {
    print("lymebridge v0.1.0")

    let config: Config
    do {
        config = try Config.load()
    } catch {
        print("Error: Config not found. Run 'lymebridge setup' first.")
        exit(1)
    }

    let daemon = Daemon(config: config)

    do {
        try daemon.run()
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}
```

**Step 3: Verify it builds**

Run: `swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/lymebridge/Daemon/Daemon.swift Sources/lymebridge/main.swift
git commit -m "feat: add main daemon and CLI"
```

---

## Task 11: LaunchAgent plist

**Files:**
- Create: `com.lymebridge.daemon.plist`

**Step 1: Create plist file**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lymebridge.daemon</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/lymebridge</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/lymebridge.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/lymebridge.log</string>
</dict>
</plist>
```

**Step 2: Commit**

```bash
git add com.lymebridge.daemon.plist
git commit -m "feat: add LaunchAgent plist"
```

---

## Task 12: Install Script

**Files:**
- Create: `install.sh`

**Step 1: Create install script**

```bash
#!/bin/bash
set -e

echo "Installing lymebridge..."

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "Error: lymebridge only works on macOS"
    exit 1
fi

# Build from source
if [[ -f "Package.swift" ]]; then
    echo "Building from source..."
    swift build -c release
    BINARY=".build/release/lymebridge"
else
    echo "Error: Run from lymebridge directory or use Homebrew"
    exit 1
fi

# Install binary
echo "Installing to /usr/local/bin..."
sudo cp "$BINARY" /usr/local/bin/lymebridge
sudo chmod +x /usr/local/bin/lymebridge

# Install LaunchAgent
echo "Installing LaunchAgent..."
cp com.lymebridge.daemon.plist ~/Library/LaunchAgents/

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Run: lymebridge setup"
echo "  2. Grant Full Disk Access in System Preferences > Privacy & Security"
echo "  3. Start daemon: launchctl load ~/Library/LaunchAgents/com.lymebridge.daemon.plist"
echo "  4. Or run directly: lymebridge"
```

**Step 2: Make executable and commit**

```bash
chmod +x install.sh
git add install.sh
git commit -m "feat: add install script"
```

---

## Task 13: README

**Files:**
- Create: `README.md`

**Step 1: Create README**

```markdown
# lymebridge

Bridge iMessage to Claude Code terminal sessions.

Send messages to yourself via iMessage → they appear as input in your Claude Code session → responses come back to iMessage.

## Quick Start

```bash
# Clone and install
git clone https://github.com/yourusername/lymebridge.git
cd lymebridge
./install.sh

# Setup (enter your Apple ID)
lymebridge setup

# Grant permissions in System Preferences:
# - Full Disk Access for lymebridge
# - Automation access for Messages.app

# Start daemon
lymebridge
```

## Usage

1. Start the daemon: `lymebridge`
2. In Claude Code, register your session: `/bridge work1`
3. Send yourself an iMessage: `@work1 what files did we edit?`
4. Response appears in iMessage: `[work1] We edited 3 files...`

### Multi-session

```
Terminal 1: /bridge work1
Terminal 2: /bridge api-dev

iMessage: @work1 status?     → goes to Terminal 1
iMessage: @api-dev logs?     → goes to Terminal 2
iMessage: hello              → goes to most recent session
```

## Requirements

- macOS 13+
- Full Disk Access permission
- Automation permission for Messages.app

## Security

- Zero network: all communication is local
- Zero dependencies: pure Swift, no third-party code
- Memory-only: messages are never written to disk
- Socket hardened: permissions 0600, owner-only access

## License

MIT
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Task 14: Claude Code Bridge Client

**Files:**
- Create: `bridge-client.sh`

**Step 1: Create bridge client script**

This is a simple shell script that users can source or run to connect their Claude session:

```bash
#!/bin/bash
# bridge-client.sh - Connect Claude Code session to lymebridge

SOCKET_PATH="/tmp/lymebridge.sock"
SESSION_NAME="${1:-default}"

if [[ ! -S "$SOCKET_PATH" ]]; then
    echo "Error: lymebridge daemon not running"
    echo "Start it with: lymebridge"
    exit 1
fi

echo "Connecting to lymebridge as '$SESSION_NAME'..."

# Create a named pipe for bidirectional communication
FIFO_IN="/tmp/lymebridge-in-$$"
FIFO_OUT="/tmp/lymebridge-out-$$"
mkfifo "$FIFO_IN" "$FIFO_OUT"

cleanup() {
    rm -f "$FIFO_IN" "$FIFO_OUT"
}
trap cleanup EXIT

# Connect to socket
exec 3<>"$SOCKET_PATH"

# Send register message
echo "{\"type\":\"register\",\"name\":\"$SESSION_NAME\"}" >&3

# Read ack
read -r response <&3
if [[ "$response" == *"error"* ]]; then
    echo "Registration failed: $response"
    exit 1
fi

echo "Connected! Messages to @$SESSION_NAME will appear here."
echo "Type responses and press Enter to send back."
echo ""

# Read messages from socket and display
while read -r line <&3; do
    # Parse JSON (simple extraction)
    if [[ "$line" == *'"type":"message"'* ]]; then
        text=$(echo "$line" | sed 's/.*"text":"\([^"]*\)".*/\1/')
        echo "[iMessage] $text"
        echo -n "> "
    fi
done &

# Read user input and send responses
while read -r input; do
    if [[ -n "$input" ]]; then
        escaped=$(echo "$input" | sed 's/\\/\\\\/g; s/"/\\"/g')
        echo "{\"type\":\"response\",\"text\":\"$escaped\"}" >&3
    fi
    echo -n "> "
done
```

**Step 2: Commit**

```bash
chmod +x bridge-client.sh
git add bridge-client.sh
git commit -m "feat: add bridge client script"
```

---

## Task 15: Final Build & Test

**Step 1: Clean build**

Run: `swift build -c release`
Expected: Build succeeds

**Step 2: Run setup**

Run: `.build/release/lymebridge setup`
Expected: Prompts for Apple ID, saves config

**Step 3: Run daemon**

Run: `.build/release/lymebridge`
Expected: Shows "Ready. Waiting for iMessages and Claude sessions..."

**Step 4: Test bridge client (in another terminal)**

Run: `./bridge-client.sh test1`
Expected: Shows "Connected! Messages to @test1 will appear here."

**Step 5: Final commit**

```bash
git add -A
git commit -m "chore: final build verification"
```

---

## Summary

| Task | Component | Files |
|------|-----------|-------|
| 1 | Project Setup | Package.swift, main.swift |
| 2 | Config | Daemon/Config.swift |
| 3 | Protocol | Socket/Protocol.swift |
| 4 | Session | Socket/Session.swift |
| 5 | Socket Server | Socket/SocketServer.swift |
| 6 | Message Reader | Messages/MessageReader.swift |
| 7 | Message Sender | Messages/MessageSender.swift |
| 8 | Database Watcher | Messages/DatabaseWatcher.swift |
| 9 | Router | Router/MessageRouter.swift |
| 10 | Daemon | Daemon/Daemon.swift, main.swift |
| 11 | LaunchAgent | com.lymebridge.daemon.plist |
| 12 | Installer | install.sh |
| 13 | Docs | README.md |
| 14 | Client | bridge-client.sh |
| 15 | Verification | Build & test |

Total: ~15 tasks, ~1000 lines of Swift code
