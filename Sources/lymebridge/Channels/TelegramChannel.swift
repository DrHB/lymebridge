import Foundation

final class TelegramChannel: MessageChannel {
    let id = "telegram"
    let displayName = "Telegram"

    private let botToken: String
    private let chatId: String
    private var lastUpdateId: Int = 0
    private var pollTimer: Timer?
    private var _isRunning = false
    private let session = URLSession.shared

    var isRunning: Bool { _isRunning }
    var onMessage: ((IncomingMessage) -> Void)?

    init(botToken: String, chatId: String) {
        self.botToken = botToken
        self.chatId = chatId
    }

    func start() throws {
        // Validate token format
        guard !botToken.isEmpty, botToken.contains(":") else {
            throw ChannelError.notConfigured("Invalid Telegram bot token")
        }

        guard !chatId.isEmpty else {
            throw ChannelError.notConfigured("Telegram chat ID required")
        }

        _isRunning = true
        startPolling()
        print("[telegram] Started polling for chat ID: \(chatId)")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        _isRunning = false
        print("[telegram] Stopped")
    }

    func send(text: String, to recipient: String) -> Bool {
        let urlString = "https://api.telegram.org/bot\(botToken)/sendMessage"
        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "chat_id": recipient.isEmpty ? chatId : recipient,
            "text": text
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return false
        }
        request.httpBody = jsonData

        let semaphore = DispatchSemaphore(value: 0)
        var success = false

        session.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                success = httpResponse.statusCode == 200
                if !success, let data = data, let body = String(data: data, encoding: .utf8) {
                    print("[telegram] Send failed: \(body)")
                }
            }
            if let error = error {
                print("[telegram] Send error: \(error)")
            }
            semaphore.signal()
        }.resume()

        _ = semaphore.wait(timeout: .now() + 10)
        return success
    }

    // MARK: - Private: Polling

    private func startPolling() {
        // Poll every 2 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollUpdates()
        }
        // Also poll immediately
        pollUpdates()
    }

    private func pollUpdates() {
        let urlString = "https://api.telegram.org/bot\(botToken)/getUpdates?offset=\(lastUpdateId + 1)&timeout=1&allowed_updates=[\"message\"]"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            self.processUpdates(data)
        }.resume()
    }

    private func processUpdates(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool, ok,
              let results = json["result"] as? [[String: Any]] else {
            return
        }

        for update in results {
            // Update the offset
            if let updateId = update["update_id"] as? Int {
                lastUpdateId = max(lastUpdateId, updateId)
            }

            // Process message
            guard let message = update["message"] as? [String: Any],
                  let text = message["text"] as? String,
                  let chat = message["chat"] as? [String: Any],
                  let msgChatId = chat["id"] as? Int else {
                continue
            }

            // Only process messages from our configured chat
            guard String(msgChatId) == chatId else {
                continue
            }

            // Skip our own responses (prefixed with [session])
            if text.hasPrefix("[") && text.contains("]") {
                continue
            }

            print("[telegram] New message: \(text.prefix(50))...")

            let msg = IncomingMessage(
                channelId: id,
                text: text,
                sender: String(msgChatId)
            )

            DispatchQueue.main.async { [weak self] in
                self?.onMessage?(msg)
            }
        }
    }
}
