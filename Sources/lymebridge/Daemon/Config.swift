import Foundation

// MARK: - Channel Configs

struct IMessageConfig: Codable {
    let enabled: Bool
    let appleId: String

    init(enabled: Bool = true, appleId: String) {
        self.enabled = enabled
        self.appleId = appleId
    }
}

struct TelegramConfig: Codable {
    let enabled: Bool
    let botToken: String
    let chatId: String

    init(enabled: Bool = false, botToken: String = "", chatId: String = "") {
        self.enabled = enabled
        self.botToken = botToken
        self.chatId = chatId
    }
}

struct ChannelsConfig: Codable {
    let imessage: IMessageConfig?
    let telegram: TelegramConfig?

    init(imessage: IMessageConfig? = nil, telegram: TelegramConfig? = nil) {
        self.imessage = imessage
        self.telegram = telegram
    }
}

// MARK: - Main Config

struct Config: Codable {
    let socketPath: String
    let logLevel: String
    let channels: ChannelsConfig

    static let defaultSocketPath = "/tmp/lymebridge.sock"
    static let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/lymebridge/config.json")

    init(socketPath: String = Config.defaultSocketPath,
         logLevel: String = "info",
         channels: ChannelsConfig) {
        self.socketPath = socketPath
        self.logLevel = logLevel
        self.channels = channels
    }

    static func load() throws -> Config {
        let data = try Data(contentsOf: configPath)
        let decoder = JSONDecoder()
        return try decoder.decode(Config.self, from: data)
    }

    static func createDefault(appleId: String) -> Config {
        Config(
            socketPath: defaultSocketPath,
            logLevel: "info",
            channels: ChannelsConfig(
                imessage: IMessageConfig(enabled: true, appleId: appleId),
                telegram: nil
            )
        )
    }

    static func createWithTelegram(botToken: String, chatId: String) -> Config {
        Config(
            socketPath: defaultSocketPath,
            logLevel: "info",
            channels: ChannelsConfig(
                imessage: nil,
                telegram: TelegramConfig(enabled: true, botToken: botToken, chatId: chatId)
            )
        )
    }

    func save() throws {
        let dir = Config.configPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Config.configPath)
    }

    // MARK: - Convenience

    var isIMessageEnabled: Bool {
        channels.imessage?.enabled ?? false
    }

    var isTelegramEnabled: Bool {
        channels.telegram?.enabled ?? false
    }

    var enabledChannelIds: [String] {
        var ids: [String] = []
        if isIMessageEnabled { ids.append("imessage") }
        if isTelegramEnabled { ids.append("telegram") }
        return ids
    }
}
