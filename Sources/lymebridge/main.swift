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
        print("lymebridge v0.2.0")
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
    lymebridge - Bridge Telegram to Claude Code

    Usage:
      lymebridge              Run the daemon
      lymebridge setup        Interactive setup
      lymebridge connect <n>  Connect a session named <n>
      lymebridge version      Show version
      lymebridge help         Show this help

    Example:
      lymebridge connect work1

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
    print("Step 1: Create a Telegram bot")
    print("  1. Open Telegram and message @BotFather")
    print("  2. Send /newbot and follow the prompts")
    print("  3. Copy the bot token")
    print("")
    print("Enter your bot token: ", terminator: "")

    guard let botToken = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
          !botToken.isEmpty else {
        print("Error: Bot token required")
        exit(1)
    }

    print("")
    print("✓ Token received")
    print("")
    print("Step 2: Link your Telegram account")
    print("  Open Telegram and send any message to your bot.")
    print("")
    print("Waiting for your message", terminator: "")
    fflush(stdout)

    var chatId: String? = nil
    let startTime = Date()
    let timeout: TimeInterval = 120 // 2 minutes

    while chatId == nil {
        if Date().timeIntervalSince(startTime) > timeout {
            print("\n")
            print("Timeout waiting for message. Please try again.")
            exit(1)
        }

        print(".", terminator: "")
        fflush(stdout)

        chatId = pollForChatId(botToken: botToken)

        if chatId == nil {
            Thread.sleep(forTimeInterval: 2)
        }
    }

    print(" found!")
    print("")
    print("✓ Chat ID: \(chatId!)")

    let config = Config.create(botToken: botToken, chatId: chatId!)

    do {
        try config.save()
        print("✓ Config saved")
        print("")
        print("═══════════════════════════════════════")
        print("           Ready to Run")
        print("═══════════════════════════════════════")
        print("")
        print("Start the daemon:")
        print("  lymebridge")
        print("")
        print("Connect a Claude Code session:")
        print("  lymebridge connect work1")
        print("")
    } catch {
        print("✗ Error saving config: \(error)")
        exit(1)
    }
}

func pollForChatId(botToken: String) -> String? {
    let urlString = "https://api.telegram.org/bot\(botToken)/getUpdates?timeout=1"
    guard let url = URL(string: urlString) else { return nil }

    let semaphore = DispatchSemaphore(value: 0)
    var result: String? = nil

    let task = URLSession.shared.dataTask(with: url) { data, _, _ in
        defer { semaphore.signal() }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultArray = json["result"] as? [[String: Any]],
              let firstUpdate = resultArray.last,
              let message = firstUpdate["message"] as? [String: Any],
              let chat = message["chat"] as? [String: Any],
              let chatId = chat["id"] as? Int else {
            return
        }
        result = String(chatId)
    }
    task.resume()
    semaphore.wait()

    return result
}

func runConnect() {
    guard arguments.count >= 3 else {
        print("Usage: lymebridge connect <name>")
        print("Example: lymebridge connect work1")
        exit(1)
    }

    let sessionName = arguments[2]
    let socketPath = "/tmp/lymebridge.sock"

    guard FileManager.default.fileExists(atPath: socketPath) else {
        print("Error: lymebridge daemon not running")
        print("Start it with: lymebridge")
        exit(1)
    }

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        print("Error: Failed to create socket")
        exit(1)
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
            socketPath.utf8CString.withUnsafeBufferPointer { src in
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

    let registerMsg = "{\"type\":\"register\",\"name\":\"\(sessionName)\",\"channel\":\"telegram\"}\n"
    _ = registerMsg.withCString { ptr in write(fd, ptr, strlen(ptr)) }

    print("Connecting to lymebridge...")
    print("  Session: \(sessionName)")
    print("")

    signal(SIGINT) { _ in print("\nDisconnecting..."); exit(0) }

    var buffer = [CChar](repeating: 0, count: 4096)
    var lineBuffer = ""
    let stdinFd = FileHandle.standardInput.fileDescriptor
    let oldFlags = fcntl(stdinFd, F_GETFL, 0)
    _ = fcntl(stdinFd, F_SETFL, oldFlags | O_NONBLOCK)

    var connected = false

    while true {
        var readSet = fd_set()
        fdZero(&readSet)
        fdSet(fd, &readSet)
        fdSet(stdinFd, &readSet)

        var tv = timeval(tv_sec: 0, tv_usec: 100000)
        let maxFd = max(fd, stdinFd)

        if select(maxFd + 1, &readSet, nil, nil, &tv) > 0 {
            if fdIsSet(fd, &readSet) {
                let bytesRead = read(fd, &buffer, buffer.count - 1)
                if bytesRead <= 0 { print("Connection closed"); break }
                buffer[bytesRead] = 0
                lineBuffer += String(cString: buffer)

                while let range = lineBuffer.range(of: "\n") {
                    let line = String(lineBuffer[..<range.lowerBound])
                    lineBuffer.removeSubrange(..<range.upperBound)

                    if line.contains("\"type\":\"ack\"") {
                        connected = true
                        print("Connected! Messages to @\(sessionName) will appear here.")
                        print("Type responses and press Enter to send back.")
                        print("")
                        print("> ", terminator: "")
                        fflush(stdout)
                    } else if line.contains("\"type\":\"message\"") {
                        if let textRange = line.range(of: "\"text\":\""),
                           let endRange = line.range(of: "\"", range: textRange.upperBound..<line.endIndex) {
                            var text = String(line[textRange.upperBound..<endRange.lowerBound])
                            text = text.replacingOccurrences(of: "\\n", with: "\n")
                            text = text.replacingOccurrences(of: "\\\"", with: "\"")
                            text = text.replacingOccurrences(of: "\\\\", with: "\\")
                            print("\n[telegram] \(text)")
                            print("> ", terminator: "")
                            fflush(stdout)
                        }
                    } else if line.contains("\"type\":\"error\"") {
                        if let msgRange = line.range(of: "\"message\":\""),
                           let endRange = line.range(of: "\"", range: msgRange.upperBound..<line.endIndex) {
                            print("Error: \(String(line[msgRange.upperBound..<endRange.lowerBound]))")
                            exit(1)
                        }
                    }
                }
            }

            if connected && fdIsSet(stdinFd, &readSet) {
                if let inputLine = readLine() {
                    let trimmed = inputLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let escaped = trimmed
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "\"", with: "\\\"")
                            .replacingOccurrences(of: "\n", with: "\\n")
                        let responseMsg = "{\"type\":\"response\",\"text\":\"\(escaped)\"}\n"
                        _ = responseMsg.withCString { ptr in write(fd, ptr, strlen(ptr)) }
                    }
                    print("> ", terminator: "")
                    fflush(stdout)
                }
            }
        }
    }
    Darwin.close(fd)
}

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
    print("lymebridge v0.2.0")
    print("")

    let config: Config
    do {
        config = try Config.load()
    } catch {
        print("Error: Config not found. Run 'lymebridge setup' first.")
        exit(1)
    }

    do {
        try Daemon(config: config).run()
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}
