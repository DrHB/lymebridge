import Foundation

struct TelegramConfig: Codable {
    let botToken: String
    let chatId: String
}

struct Config: Codable {
    let socketPath: String
    let telegram: TelegramConfig

    static let defaultSocketPath = "/tmp/lymebridge.sock"
    static let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/lymebridge/config.json")

    init(socketPath: String = Config.defaultSocketPath, telegram: TelegramConfig) {
        self.socketPath = socketPath
        self.telegram = telegram
    }

    static func load() throws -> Config {
        let data = try Data(contentsOf: configPath)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    static func create(botToken: String, chatId: String) -> Config {
        Config(telegram: TelegramConfig(botToken: botToken, chatId: chatId))
    }

    func save() throws {
        let dir = Config.configPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(self).write(to: Config.configPath)
    }
}
