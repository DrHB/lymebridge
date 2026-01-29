import Foundation

let arguments = CommandLine.arguments

if arguments.count > 1 {
    switch arguments[1] {
    case "setup":
        runSetup()
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
      lymebridge              Run the daemon
      lymebridge setup        Interactive setup
      lymebridge version      Show version
      lymebridge help         Show this help

    Bridge client:
      /bridge imessage work1  Connect session "work1" via iMessage
      /bridge telegram dev    Connect session "dev" via Telegram
    """)
}

func runSetup() {
    print("lymebridge setup")
    print("================")
    print("")
    print("Which channel do you want to configure?")
    print("1. iMessage (recommended for local use)")
    print("2. Telegram (for remote access)")
    print("")
    print("Enter choice (1 or 2):")

    guard let choice = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        print("Error: No input")
        exit(1)
    }

    let config: Config

    switch choice {
    case "1":
        print("")
        print("Enter your Apple ID (email or phone for iMessage):")
        guard let appleId = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !appleId.isEmpty else {
            print("Error: Apple ID required")
            exit(1)
        }
        config = Config.createDefault(appleId: appleId)

    case "2":
        print("")
        print("Enter your Telegram bot token (from @BotFather):")
        guard let botToken = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !botToken.isEmpty else {
            print("Error: Bot token required")
            exit(1)
        }
        print("")
        print("Enter your Telegram chat ID:")
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
        print("Config saved to: \(Config.configPath.path)")
        print("")
        print("Next steps:")
        if choice == "1" {
            print("1. Grant Full Disk Access to lymebridge in System Preferences")
            print("2. Grant Automation access for Messages when prompted")
        }
        print("3. Run: lymebridge")
    } catch {
        print("Error saving config: \(error)")
        exit(1)
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
