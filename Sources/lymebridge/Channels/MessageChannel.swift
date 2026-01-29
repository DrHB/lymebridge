import Foundation

/// Represents an incoming message from any channel
struct IncomingMessage {
    let channelId: String      // e.g., "imessage", "slack", "telegram"
    let text: String
    let sender: String         // identifier for routing responses back
    let timestamp: Date

    init(channelId: String, text: String, sender: String, timestamp: Date = Date()) {
        self.channelId = channelId
        self.text = text
        self.sender = sender
        self.timestamp = timestamp
    }
}

/// Protocol that all messaging channels must implement
protocol MessageChannel: AnyObject {
    /// Unique identifier for this channel (e.g., "imessage", "slack")
    var id: String { get }

    /// Human-readable name for display
    var displayName: String { get }

    /// Whether the channel is currently running
    var isRunning: Bool { get }

    /// Called when a message is received from this channel
    var onMessage: ((IncomingMessage) -> Void)? { get set }

    /// Start listening for messages
    func start() throws

    /// Stop listening and clean up resources
    func stop()

    /// Send a message back through this channel
    /// - Parameters:
    ///   - text: The message text to send
    ///   - recipient: Channel-specific recipient identifier
    /// - Returns: true if sent successfully
    func send(text: String, to recipient: String) -> Bool
}

/// Errors that can occur when working with channels
enum ChannelError: Error {
    case notConfigured(String)
    case connectionFailed(String)
    case sendFailed(String)
    case permissionDenied(String)
}
