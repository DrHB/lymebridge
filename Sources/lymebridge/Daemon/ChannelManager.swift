import Foundation

final class ChannelManager {
    private var channels: [String: MessageChannel] = [:]
    var onMessage: ((IncomingMessage) -> Void)?

    func register(_ channel: MessageChannel) {
        channels[channel.id] = channel
        channel.onMessage = { [weak self] msg in
            self?.onMessage?(msg)
        }
        print("[channels] Registered channel: \(channel.id)")
    }

    func start() throws {
        for channel in channels.values where channel.isRunning == false {
            try channel.start()
        }
    }

    func stop() {
        for channel in channels.values {
            channel.stop()
        }
    }

    func send(text: String, via channelId: String, to recipient: String) -> Bool {
        guard let channel = channels[channelId] else {
            print("[channels] Channel not found: \(channelId)")
            return false
        }
        return channel.send(text: text, to: recipient)
    }

    func getChannel(_ id: String) -> MessageChannel? {
        channels[id]
    }

    func getEnabledChannels() -> [String] {
        channels.filter { $0.value.isRunning }.map { $0.key }
    }

    func isChannelEnabled(_ id: String) -> Bool {
        channels[id]?.isRunning ?? false
    }
}
