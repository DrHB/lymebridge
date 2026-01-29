import Foundation

final class Daemon {
    private let config: Config
    private let channelManager = ChannelManager()
    private let socketServer: SocketServer
    private let router = MessageRouter()
    private var running = false

    init(config: Config) {
        self.config = config
        self.socketServer = SocketServer(path: config.socketPath)
    }

    func run() throws {
        print("[daemon] Starting lymebridge daemon...")

        // Setup channels based on config
        setupChannels()

        // Setup socket server callbacks
        setupSocketCallbacks()

        // Setup channel manager callback
        channelManager.onMessage = { [weak self] msg in
            self?.handleIncomingMessage(msg)
        }

        // Start everything
        try channelManager.start()
        try socketServer.start()

        running = true
        print("[daemon] Ready. Enabled channels: \(channelManager.getEnabledChannels().joined(separator: ", "))")
        print("[daemon] Waiting for messages...")

        // Setup signal handlers
        setupSignalHandlers()

        // Main run loop
        let runLoop = RunLoop.current
        while running {
            socketServer.poll(timeout: 100)
            runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
    }

    func stop() {
        running = false
        channelManager.stop()
        socketServer.stop()
        print("[daemon] Stopped")
    }

    // MARK: - Private Setup

    private func setupChannels() {
        // iMessage
        if let imsgConfig = config.channels.imessage, imsgConfig.enabled {
            let channel = IMessageChannel(appleId: imsgConfig.appleId)
            channelManager.register(channel)
        }

        // Telegram
        if let tgConfig = config.channels.telegram, tgConfig.enabled {
            let channel = TelegramChannel(botToken: tgConfig.botToken, chatId: tgConfig.chatId)
            channelManager.register(channel)
        }
    }

    private func setupSocketCallbacks() {
        socketServer.onResponse = { [weak self] text, session in
            self?.handleResponse(text: text, from: session)
        }

        socketServer.onSessionRegistered = { session in
            print("[daemon] Session connected: \(session.name) via \(session.channel)")
        }

        socketServer.onSessionDisconnected = { session in
            print("[daemon] Session disconnected: \(session.name)")
        }
    }

    private func setupSignalHandlers() {
        signal(SIGINT) { _ in
            print("\n[daemon] Received SIGINT, shutting down...")
            exit(0)
        }
        signal(SIGTERM) { _ in
            print("\n[daemon] Received SIGTERM, shutting down...")
            exit(0)
        }
    }

    // MARK: - Message Handling

    private func handleIncomingMessage(_ msg: IncomingMessage) {
        let routed = router.parse(msg.text)

        print("[daemon] Received from \(msg.channelId): \(msg.text.prefix(50))...")

        if routed.text.isEmpty {
            return
        }

        let sent: Bool
        if let sessionName = routed.sessionName {
            // Route to specific session
            sent = socketServer.sendToSession(name: sessionName, text: routed.text)
            if !sent {
                let available = socketServer.getSessionNames().joined(separator: ", ")
                let errorMsg = "Session '\(sessionName)' not found. Available: \(available.isEmpty ? "none" : available)"
                _ = channelManager.send(text: "[error] \(errorMsg)", via: msg.channelId, to: msg.sender)
            }
        } else {
            // Route to most recent session
            sent = socketServer.sendToMostRecent(text: routed.text)
            if !sent {
                _ = channelManager.send(
                    text: "[error] No active sessions. Connect with: /bridge <channel> <name>",
                    via: msg.channelId,
                    to: msg.sender
                )
            }
        }
    }

    private func handleResponse(text: String, from session: Session) {
        print("[daemon] Response from \(session.name): \(text.prefix(50))...")

        // Format with session name prefix
        let formattedText = "[\(session.name)] \(text)"

        // Send back through the same channel the session registered with
        // For now, we'll use the session's channel and a default recipient
        // The recipient is stored when we receive messages
        if let channel = channelManager.getChannel(session.channel) {
            // Use a simple recipient - for iMessage it's the appleId, for telegram it's chatId
            let recipient = getRecipientForChannel(session.channel)
            _ = channel.send(text: formattedText, to: recipient)
        }
    }

    private func getRecipientForChannel(_ channelId: String) -> String {
        switch channelId {
        case "imessage":
            return config.channels.imessage?.appleId ?? ""
        case "telegram":
            return config.channels.telegram?.chatId ?? ""
        default:
            return ""
        }
    }
}
