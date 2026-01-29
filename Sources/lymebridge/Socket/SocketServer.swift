import Foundation

final class SocketServer {
    private let path: String
    private var serverFd: Int32 = -1
    private var sessions: [String: Session] = [:]
    private var fdToSession: [Int32: Session] = [:]
    private var mostRecentSessionName: String?
    private var running = false

    var onMessage: ((String, Session) -> Void)?
    var onResponse: ((String, Session) -> Void)?
    var onSessionRegistered: ((Session) -> Void)?
    var onSessionDisconnected: ((Session) -> Void)?

    init(path: String) {
        self.path = path
    }

    func start() throws {
        unlink(path)
        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else { throw SocketError.createFailed }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dest, src.baseAddress, min(src.count, 104))
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverFd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult >= 0 else { throw SocketError.bindFailed }

        chmod(path, 0o600)
        guard listen(serverFd, 5) >= 0 else { throw SocketError.listenFailed }

        running = true
        print("[socket] Listening on \(path)")
    }

    func stop() {
        running = false
        for session in sessions.values { session.close() }
        sessions.removeAll()
        fdToSession.removeAll()
        if serverFd >= 0 { Darwin.close(serverFd); serverFd = -1 }
        unlink(path)
    }

    func poll(timeout: Int32 = 100) {
        guard running else { return }

        var readSet = fd_set()
        __darwin_fd_zero(&readSet)
        __darwin_fd_set(serverFd, &readSet)

        var maxFd = serverFd
        for fd in fdToSession.keys {
            __darwin_fd_set(fd, &readSet)
            maxFd = max(maxFd, fd)
        }

        var tv = timeval(tv_sec: 0, tv_usec: timeout * 1000)
        let result = select(maxFd + 1, &readSet, nil, nil, &tv)
        guard result > 0 else { return }

        if __darwin_fd_isset(serverFd, &readSet) != 0 { acceptConnection() }

        for (fd, session) in fdToSession {
            if __darwin_fd_isset(fd, &readSet) != 0 { handleSessionData(session) }
        }
    }

    private func acceptConnection() {
        let clientFd = accept(serverFd, nil, nil)
        guard clientFd >= 0 else { return }
        let flags = fcntl(clientFd, F_GETFL, 0)
        _ = fcntl(clientFd, F_SETFL, flags | O_NONBLOCK)
        let session = Session(name: "_pending_\(clientFd)", channel: "unknown", fileDescriptor: clientFd)
        fdToSession[clientFd] = session
        print("[socket] New connection: fd=\(clientFd)")
    }

    private func handleSessionData(_ session: Session) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(session.fileDescriptor, &buffer, buffer.count)
        if bytesRead <= 0 { disconnectSession(session); return }
        session.appendToBuffer(Data(buffer[..<bytesRead]))
        for line in session.extractLines() { handleMessage(line, from: session) }
    }

    private func handleMessage(_ line: String, from session: Session) {
        guard let msg = ClientMessage.parse(line) else {
            _ = session.send(.error(message: "Invalid JSON"))
            return
        }
        switch msg {
        case .register(let name, let channel): registerSession(session, name: name, channel: channel)
        case .response(let text): session.touch(); onResponse?(text, session)
        case .disconnect: disconnectSession(session)
        }
    }

    private func registerSession(_ session: Session, name: String, channel: String) {
        if sessions[name] != nil {
            _ = session.send(.error(message: "Session name '\(name)' already taken"))
            return
        }
        fdToSession.removeValue(forKey: session.fileDescriptor)
        let namedSession = Session(name: name, channel: channel, fileDescriptor: session.fileDescriptor)
        sessions[name] = namedSession
        fdToSession[session.fileDescriptor] = namedSession
        mostRecentSessionName = name
        _ = namedSession.send(.ack(channel: channel))
        onSessionRegistered?(namedSession)
        print("[socket] Session registered: \(name) (channel: \(channel))")
    }

    private func disconnectSession(_ session: Session) {
        session.close()
        sessions.removeValue(forKey: session.name)
        fdToSession.removeValue(forKey: session.fileDescriptor)
        if mostRecentSessionName == session.name { mostRecentSessionName = sessions.keys.first }
        onSessionDisconnected?(session)
        print("[socket] Session disconnected: \(session.name)")
    }

    func sendToSession(name: String, text: String) -> Bool {
        guard let session = sessions[name] else { return false }
        session.touch()
        mostRecentSessionName = name
        return session.send(.message(text: text, channel: session.channel))
    }

    func sendToMostRecent(text: String) -> Bool {
        guard let name = mostRecentSessionName else { return false }
        return sendToSession(name: name, text: text)
    }

    func getSessionNames() -> [String] { Array(sessions.keys) }
}

enum SocketError: Error { case createFailed, bindFailed, listenFailed }

private func __darwin_fd_zero(_ set: inout fd_set) {
    set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private func __darwin_fd_set(_ fd: Int32, _ set: inout fd_set) {
    let intOffset = Int(fd / 32)
    let bitOffset = Int(fd % 32)
    withUnsafeMutablePointer(to: &set.fds_bits) { ptr in
        ptr.withMemoryRebound(to: Int32.self, capacity: 32) { bits in
            bits[intOffset] |= Int32(1 << bitOffset)
        }
    }
}

private func __darwin_fd_isset(_ fd: Int32, _ set: inout fd_set) -> Int32 {
    let intOffset = Int(fd / 32)
    let bitOffset = Int(fd % 32)
    return withUnsafeMutablePointer(to: &set.fds_bits) { ptr in
        ptr.withMemoryRebound(to: Int32.self, capacity: 32) { bits in
            (bits[intOffset] & Int32(1 << bitOffset)) != 0 ? 1 : 0
        }
    }
}
