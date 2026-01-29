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
    private var lastEventTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.5

    var isRunning: Bool { _isRunning }
    var onMessage: ((IncomingMessage) -> Void)?

    init(appleId: String) {
        self.appleId = appleId
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/Library/Messages/chat.db"
    }

    func start() throws {
        // Open database read-only
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ChannelError.connectionFailed("Cannot open Messages database. Grant Full Disk Access.")
        }

        // Start from current position (don't process history)
        lastRowId = getCurrentMaxRowId()

        // Start watching for changes
        startWatching()
        _isRunning = true
        print("[imessage] Started, watching from ROWID > \(lastRowId)")
    }

    func stop() {
        stopWatching()
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
        _isRunning = false
        print("[imessage] Stopped")
    }

    func send(text: String, to recipient: String) -> Bool {
        // Escape for AppleScript
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")

        let script = """
            tell application "Messages"
                set targetService to 1st account whose service type = iMessage
                set targetBuddy to participant "\(appleId)" of targetService
                send "\(escaped)" to targetBuddy
            end tell
            """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            print("[imessage] Failed to create AppleScript")
            return false
        }

        appleScript.executeAndReturnError(&error)

        if let error = error {
            print("[imessage] AppleScript error: \(error)")
            return false
        }

        return true
    }

    // MARK: - Private: Database

    private func getCurrentMaxRowId() -> Int64 {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, "SELECT MAX(ROWID) FROM message", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        return sqlite3_column_int64(stmt, 0)
    }

    private func checkForNewMessages() {
        guard let db = db else { return }

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
            print("[imessage] Query prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }

        sqlite3_bind_int64(stmt, 1, lastRowId)
        sqlite3_bind_text(stmt, 2, appleId, -1, nil)
        sqlite3_bind_text(stmt, 3, "%\(appleId)%", -1, nil)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(stmt, 0)

            guard let textPtr = sqlite3_column_text(stmt, 1) else { continue }
            let text = String(cString: textPtr)

            // Skip messages that look like our own responses [session]
            if text.hasPrefix("[") && text.contains("]") {
                lastRowId = max(lastRowId, rowId)
                continue
            }

            lastRowId = max(lastRowId, rowId)

            let msg = IncomingMessage(
                channelId: id,
                text: text,
                sender: appleId
            )

            print("[imessage] New message: \(text.prefix(50))...")
            onMessage?(msg)
        }
    }

    // MARK: - Private: FSEvents Watching

    private func startWatching() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let messagesDir = "\(home)/Library/Messages" as CFString
        let pathsToWatch = [messagesDir] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

        stream = FSEventStreamCreate(
            nil,
            { (_, info, _, _, _, _) in
                guard let info = info else { return }
                let channel = Unmanaged<IMessageChannel>.fromOpaque(info).takeUnretainedValue()
                channel.handleFSEvent()
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        )

        guard let stream = stream else {
            print("[imessage] Failed to create FSEventStream")
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        print("[imessage] Watching ~/Library/Messages for changes")
    }

    private func stopWatching() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleFSEvent() {
        // Debounce rapid events
        let now = Date()
        guard now.timeIntervalSince(lastEventTime) >= debounceInterval else { return }
        lastEventTime = now

        DispatchQueue.main.async { [weak self] in
            self?.checkForNewMessages()
        }
    }
}
