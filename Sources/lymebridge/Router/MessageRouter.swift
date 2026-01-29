import Foundation

struct RoutedMessage {
    let sessionName: String?  // nil means use most recent
    let text: String
}

final class MessageRouter {

    /// Parse @session-name prefix from message
    /// "@work1 hello" -> RoutedMessage(sessionName: "work1", text: "hello")
    /// "hello" -> RoutedMessage(sessionName: nil, text: "hello")
    func parse(_ input: String) -> RoutedMessage {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("@") else {
            return RoutedMessage(sessionName: nil, text: trimmed)
        }

        // Find end of session name (first space)
        guard let spaceIndex = trimmed.firstIndex(of: " ") else {
            // Just "@name" with no message
            let name = String(trimmed.dropFirst())
            return RoutedMessage(sessionName: name, text: "")
        }

        let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<spaceIndex])
        let text = String(trimmed[trimmed.index(after: spaceIndex)...])
            .trimmingCharacters(in: .whitespaces)

        return RoutedMessage(sessionName: name, text: text)
    }
}
