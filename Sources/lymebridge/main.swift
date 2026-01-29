import Foundation

let arguments = CommandLine.arguments

if arguments.count > 1 {
    switch arguments[1] {
    case "setup":
        runSetup()
    case "daemon":
        runDaemon()
    case "connect":
        runConnect()
    case "version", "--version", "-v":
        print("lymebridge v0.1.0")
    case "help", "--help", "-h":
        printHelp()
    default:
        print("Unknown command: \(arguments[1])")
        printHelp()
        exit(1)
    }
} else {
    runDaemon()
}

func printHelp() {
    print("""
    lymebridge - Bridge iMessage/Telegram to Claude Code and Codex CLI

    Usage:
      lymebridge                            Run the daemon
      lymebridge daemon                     Run the daemon (explicit)
      lymebridge setup                      Interactive setup
      lymebridge connect <channel> <name>   Connect a session
      lymebridge version                    Show version
      lymebridge help                       Show this help

    Examples:
      lymebridge connect imessage work1     Connect session "work1" via iMessage
      lymebridge connect telegram api       Connect session "api" via Telegram

    Install:
      curl -fsSL https://raw.githubusercontent.com/DrHB/lymebridge/main/install.sh | bash
    """)
}

func runSetup() {
    print("")
    print("═══════════════════════════════════════")
    print("         lymebridge setup")
    print("═══════════════════════════════════════")
    print("")
    print("Which channel do you want to configure?")
    print("  1. iMessage (recommended for local use)")
    print("  2. Telegram (for remote access)")
    print("")
    print("Enter choice (1 or 2): ", terminator: "")

    guard let choice = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        print("Error: No input")
        exit(1)
    }

    let config: Config
    var needsFullDiskAccess = false

    switch choice {
    case "1":
        let appleId = promptForAppleId()
        config = Config.createDefault(appleId: appleId)
        needsFullDiskAccess = true

    case "2":
        print("")
        print("Enter your Telegram bot token (from @BotFather): ", terminator: "")
        guard let botToken = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !botToken.isEmpty else {
            print("Error: Bot token required")
            exit(1)
        }
        print("Enter your Telegram chat ID: ", terminator: "")
        guard let chatId = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !chatId.isEmpty else {
            print("Error: Chat ID required")
            exit(1)
        }
        config = Config.createWithTelegram(botToken: botToken, chatId: chatId)

    default:
        print("Invalid choice")
        exit(1)
    }

    do {
        try config.save()
        print("")
        print("✓ Config saved")
    } catch {
        print("✗ Error saving config: \(error)")
        exit(1)
    }

    if needsFullDiskAccess {
        setupFullDiskAccess()
    }

    print("")
    print("═══════════════════════════════════════")
    print("           Ready to Run")
    print("═══════════════════════════════════════")
    print("")
    print("To start the daemon:")
    print("  lymebridge")
    print("")
    print("To connect a Claude Code session:")
    print("  lymebridge connect imessage work1")
    print("")
}

func promptForAppleId() -> String {
    print("")
    print("How is your Apple ID registered?")
    print("  1. Email address")
    print("  2. Phone number")
    print("")
    print("Enter choice (1 or 2): ", terminator: "")

    guard let idType = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        print("Error: No input")
        exit(1)
    }

    switch idType {
    case "1":
        print("")
        print("Enter your email address: ", terminator: "")
        guard let email = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            print("Error: Email required")
            exit(1)
        }
        print("")
        print("✓ Apple ID: \(email)")
        return email

    case "2":
        print("")
        print("Country code (e.g., 1 for US, 44 for UK): ", terminator: "")
        guard let countryCode = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !countryCode.isEmpty else {
            print("Error: Country code required")
            exit(1)
        }
        print("Phone number: ", terminator: "")
        guard let phone = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !phone.isEmpty else {
            print("Error: Phone number required")
            exit(1)
        }
        let cleanCode = countryCode.replacingOccurrences(of: "+", with: "")
        let cleanPhone = phone.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        let fullNumber = "+\(cleanCode)\(cleanPhone)"
        print("")
        print("✓ Apple ID: \(fullNumber)")
        return fullNumber

    default:
        print("Invalid choice")
        exit(1)
    }
}

func checkFullDiskAccess() -> Bool {
    let messagesDb = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Messages/chat.db")
    return FileManager.default.isReadableFile(atPath: messagesDb.path)
}

func setupFullDiskAccess() {
    print("")
    print("───────────────────────────────────────")
    print("       Granting Permissions")
    print("───────────────────────────────────────")
    print("")
    print("lymebridge needs Full Disk Access to read messages.")
    print("")

    if checkFullDiskAccess() {
        print("✓ Full Disk Access: already granted")
        return
    }

    var attempts = 0
    while !checkFullDiskAccess() {
        attempts += 1

        print("Opening System Settings...")
        print("")
        print("Steps:")
        print("  1. Click the + button")
        print("  2. Press Cmd+Shift+G and type: /usr/local/bin")
        print("  3. Select 'lymebridge' and click Open")
        print("  4. Ensure the toggle is ON")
        print("")

        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]
        try? task.run()
        task.waitUntilExit()

        print("Press Enter when done...", terminator: "")
        _ = readLine()
        print("")
        print("Checking permissions...")
        print("")

        if checkFullDiskAccess() {
            print("✓ Full Disk Access: granted")
            return
        }

        print("✗ Full Disk Access: not granted")
        print("")
        print("Would you like to:")
        print("  1. Try again (re-open Settings)")
        print("  2. Skip for now (you can grant later)")
        print("")
        print("Enter choice (1 or 2): ", terminator: "")

        guard let retry = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return
        }

        if retry != "1" {
            print("")
            print("Skipped. Remember to grant Full Disk Access before running lymebridge.")
            return
        }
        print("")
    }
}

func runConnect() {
    guard arguments.count >= 4 else {
        print("Usage: lymebridge connect <channel> <name>")
        print("")
        print("Examples:")
        print("  lymebridge connect imessage work1")
        print("  lymebridge connect telegram api")
        exit(1)
    }

    let channel = arguments[2]
    let sessionName = arguments[3]

    guard ["imessage", "telegram"].contains(channel) else {
        print("Error: Unknown channel '\(channel)'")
        print("Available channels: imessage, telegram")
        exit(1)
    }

    let socketPath = "/tmp/lymebridge.sock"

    // Check if socket exists
    guard FileManager.default.fileExists(atPath: socketPath) else {
        print("Error: lymebridge daemon not running")
        print("Start it with: lymebridge")
        exit(1)
    }

    // Connect to Unix socket
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        print("Error: Failed to create socket")
        exit(1)
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
            pathBytes.withUnsafeBufferPointer { src in
                memcpy(dest, src.baseAddress, min(src.count, 104))
            }
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectResult >= 0 else {
        print("Error: Failed to connect to daemon")
        exit(1)
    }

    // Send register message
    let registerMsg = "{\"type\":\"register\",\"name\":\"\(sessionName)\",\"channel\":\"\(channel)\"}\n"
    _ = registerMsg.withCString { ptr in
        write(fd, ptr, strlen(ptr))
    }

    print("Connecting to lymebridge...")
    print("  Channel: \(channel)")
    print("  Session: \(sessionName)")
    print("")

    // Set up signal handler for clean exit
    signal(SIGINT) { _ in
        print("\nDisconnecting...")
        exit(0)
    }

    // Read/write loop
    var buffer = [CChar](repeating: 0, count: 4096)
    var lineBuffer = ""

    // Set stdin to non-blocking for interleaved I/O
    let stdinFd = FileHandle.standardInput.fileDescriptor
    let oldFlags = fcntl(stdinFd, F_GETFL, 0)
    _ = fcntl(stdinFd, F_SETFL, oldFlags | O_NONBLOCK)

    var connected = false

    while true {
        // Check for data from socket
        var readSet = fd_set()
        fdZero(&readSet)
        fdSet(fd, &readSet)
        fdSet(stdinFd, &readSet)

        var tv = timeval(tv_sec: 0, tv_usec: 100000) // 100ms timeout
        let maxFd = max(fd, stdinFd)
        let selectResult = select(maxFd + 1, &readSet, nil, nil, &tv)

        if selectResult > 0 {
            // Check socket
            if fdIsSet(fd, &readSet) {
                let bytesRead = read(fd, &buffer, buffer.count - 1)
                if bytesRead <= 0 {
                    print("Connection closed by daemon")
                    break
                }
                buffer[bytesRead] = 0
                lineBuffer += String(cString: buffer)

                // Process complete lines
                while let range = lineBuffer.range(of: "\n") {
                    let line = String(lineBuffer[..<range.lowerBound])
                    lineBuffer.removeSubrange(..<range.upperBound)

                    // Parse JSON response
                    if line.contains("\"type\":\"ack\"") {
                        connected = true
                        print("Connected! Messages to @\(sessionName) will appear here.")
                        print("Type responses and press Enter to send back.")
                        print("")
                        print("> ", terminator: "")
                        fflush(stdout)
                    } else if line.contains("\"type\":\"message\"") {
                        // Extract text from JSON
                        if let textRange = line.range(of: "\"text\":\""),
                           let endRange = line.range(of: "\"", range: textRange.upperBound..<line.endIndex) {
                            var text = String(line[textRange.upperBound..<endRange.lowerBound])
                            text = text.replacingOccurrences(of: "\\n", with: "\n")
                            text = text.replacingOccurrences(of: "\\\"", with: "\"")
                            text = text.replacingOccurrences(of: "\\\\", with: "\\")
                            print("\n[\(channel)] \(text)")
                            print("> ", terminator: "")
                            fflush(stdout)
                        }
                    } else if line.contains("\"type\":\"error\"") {
                        if let msgRange = line.range(of: "\"message\":\""),
                           let endRange = line.range(of: "\"", range: msgRange.upperBound..<line.endIndex) {
                            let errorMsg = String(line[msgRange.upperBound..<endRange.lowerBound])
                            print("Error: \(errorMsg)")
                            exit(1)
                        }
                    }
                }
            }

            // Check stdin
            if connected && fdIsSet(stdinFd, &readSet) {
                if let inputLine = readLine() {
                    let trimmed = inputLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        // Escape for JSON
                        let escaped = trimmed
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "\"", with: "\\\"")
                            .replacingOccurrences(of: "\n", with: "\\n")
                        let responseMsg = "{\"type\":\"response\",\"text\":\"\(escaped)\"}\n"
                        _ = responseMsg.withCString { ptr in
                            write(fd, ptr, strlen(ptr))
                        }
                    }
                    print("> ", terminator: "")
                    fflush(stdout)
                }
            }
        }
    }

    Darwin.close(fd)
}

// MARK: - fd_set helpers for connect

private func fdZero(_ set: inout fd_set) {
    set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private func fdSet(_ fd: Int32, _ set: inout fd_set) {
    let intOffset = Int(fd / 32)
    let bitOffset = Int(fd % 32)
    withUnsafeMutablePointer(to: &set.fds_bits) { ptr in
        ptr.withMemoryRebound(to: Int32.self, capacity: 32) { bits in
            bits[intOffset] |= Int32(1 << bitOffset)
        }
    }
}

private func fdIsSet(_ fd: Int32, _ set: inout fd_set) -> Bool {
    let intOffset = Int(fd / 32)
    let bitOffset = Int(fd % 32)
    return withUnsafeMutablePointer(to: &set.fds_bits) { ptr in
        ptr.withMemoryRebound(to: Int32.self, capacity: 32) { bits in
            (bits[intOffset] & Int32(1 << bitOffset)) != 0
        }
    }
}

func runDaemon() {
    print("lymebridge v0.1.0")
    print("")

    let config: Config
    do {
        config = try Config.load()
    } catch {
        print("Error: Config not found. Run 'lymebridge setup' first.")
        print("       Config path: \(Config.configPath.path)")
        exit(1)
    }

    if config.enabledChannelIds.isEmpty {
        print("Error: No channels enabled in config.")
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
