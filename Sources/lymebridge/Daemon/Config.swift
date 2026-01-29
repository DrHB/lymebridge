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
