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

        // Setup Telegram channel
        let channel = TelegramChannel(
            botToken: config.telegram.botToken,
            chatId: config.telegram.chatId
        )
        channelManager.register(channel)

        // Setup callbacks
        socketServer.onResponse = { [weak self] text, session in
            self?.handleResponse(text: text, from: session)
        }
        socketServer.onSessionRegistered = { session in
            print("[daemon] Session connected: \(session.name)")
        }
        socketServer.onSessionDisconnected = { session in
            print("[daemon] Session disconnected: \(session.name)")
        }
        channelManager.onMessage = { [weak self] msg in
            self?.handleIncomingMessage(msg)
        }

        // Start
        try channelManager.start()
        try socketServer.start()
        running = true

        print("[daemon] Ready. Listening for Telegram messages...")

        // Signal handlers
        signal(SIGINT) { _ in print("\n[daemon] Shutting down..."); exit(0) }
        signal(SIGTERM) { _ in print("\n[daemon] Shutting down..."); exit(0) }

        // Run loop
        let runLoop = RunLoop.current
        while running {
            socketServer.poll(timeout: 100)
            runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
        }
    }

    private func handleIncomingMessage(_ msg: IncomingMessage) {
        let routed = router.parse(msg.text)
        print("[daemon] Received: \(msg.text.prefix(50))...")

        if routed.text.isEmpty { return }

        let sent: Bool
        if let sessionName = routed.sessionName {
            sent = socketServer.sendToSession(name: sessionName, text: routed.text)
            if !sent {
                let available = socketServer.getSessionNames().joined(separator: ", ")
                _ = channelManager.send(
                    text: "[error] Session '\(sessionName)' not found. Available: \(available.isEmpty ? "none" : available)",
                    via: "telegram",
                    to: config.telegram.chatId
                )
            }
        } else {
            sent = socketServer.sendToMostRecent(text: routed.text)
            if !sent {
                _ = channelManager.send(
                    text: "[error] No active sessions. Connect with: lymebridge connect <name>",
                    via: "telegram",
                    to: config.telegram.chatId
                )
            }
        }
    }

    private func handleResponse(text: String, from session: Session) {
        print("[daemon] Response from \(session.name): \(text.prefix(50))...")
        let formattedText = "[\(session.name)] \(text)"
        _ = channelManager.send(text: formattedText, via: "telegram", to: config.telegram.chatId)
    }
}
