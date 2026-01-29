import Foundation

final class Session {
    let name: String
    let fileDescriptor: Int32
    var lastActive: Date

    private var buffer: String = ""

    init(name: String, fileDescriptor: Int32) {
        self.name = name
        self.fileDescriptor = fileDescriptor
        self.lastActive = Date()
    }

    func touch() {
        lastActive = Date()
    }

    func send(_ message: ServerMessage) -> Bool {
        guard let line = message.toJSONLine(),
              let data = line.data(using: .utf8) else { return false }

        return data.withUnsafeBytes { ptr in
            let written = write(fileDescriptor, ptr.baseAddress, data.count)
            return written == data.count
        }
    }

    func appendToBuffer(_ data: Data) {
        if let str = String(data: data, encoding: .utf8) {
            buffer += str
        }
    }

    func extractLines() -> [String] {
        var lines: [String] = []
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            lines.append(line)
            buffer.removeSubrange(..<range.upperBound)
        }
        return lines
    }

    func close() {
        Darwin.close(fileDescriptor)
    }
}
