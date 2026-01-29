import Foundation

// MARK: - Client -> Server Messages

enum ClientMessage: Codable {
    case register(name: String, channel: String)
    case response(text: String)
    case disconnect

    enum CodingKeys: String, CodingKey {
        case type, name, text, channel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "register":
            let name = try container.decode(String.self, forKey: .name)
            let channel = try container.decodeIfPresent(String.self, forKey: .channel) ?? "imessage"
            self = .register(name: name, channel: channel)
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
        case .register(let name, let channel):
            try container.encode("register", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(channel, forKey: .channel)
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
    case message(text: String, channel: String)
    case ack(channel: String)
    case error(message: String)

    enum CodingKeys: String, CodingKey {
        case type, text, message, channel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "message":
            let text = try container.decode(String.self, forKey: .text)
            let channel = try container.decodeIfPresent(String.self, forKey: .channel) ?? "imessage"
            self = .message(text: text, channel: channel)
        case "ack":
            let channel = try container.decodeIfPresent(String.self, forKey: .channel) ?? "imessage"
            self = .ack(channel: channel)
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
        case .message(let text, let channel):
            try container.encode("message", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(channel, forKey: .channel)
        case .ack(let channel):
            try container.encode("ack", forKey: .type)
            try container.encode(channel, forKey: .channel)
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
