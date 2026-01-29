import Foundation

// MARK: - Client -> Server Messages

enum ClientMessage: Codable {
    case register(name: String)
    case response(text: String)
    case disconnect

    enum CodingKeys: String, CodingKey {
        case type, name, text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "register":
            let name = try container.decode(String.self, forKey: .name)
            self = .register(name: name)
        case "response":
            let text = try container.decode(String.self, forKey: .text)
            self = .response(text: text)
        case "disconnect":
            self = .disconnect
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .register(let name):
            try container.encode("register", forKey: .type)
            try container.encode(name, forKey: .name)
        case .response(let text):
            try container.encode("response", forKey: .type)
            try container.encode(text, forKey: .text)
        case .disconnect:
            try container.encode("disconnect", forKey: .type)
        }
    }
}

// MARK: - Server -> Client Messages

enum ServerMessage: Codable {
    case message(text: String)
    case ack
    case error(message: String)

    enum CodingKeys: String, CodingKey {
        case type, text, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "message":
            let text = try container.decode(String.self, forKey: .text)
            self = .message(text: text)
        case "ack":
            self = .ack
        case "error":
            let msg = try container.decode(String.self, forKey: .message)
            self = .error(message: msg)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let text):
            try container.encode("message", forKey: .type)
            try container.encode(text, forKey: .text)
        case .ack:
            try container.encode("ack", forKey: .type)
        case .error(let msg):
            try container.encode("error", forKey: .type)
            try container.encode(msg, forKey: .message)
        }
    }
}

// MARK: - JSON Line Helpers

extension ClientMessage {
    static func parse(_ line: String) -> ClientMessage? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ClientMessage.self, from: data)
    }
}

extension ServerMessage {
    func toJSONLine() -> String? {
        guard let data = try? JSONEncoder().encode(self),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str + "\n"
    }
}
