import Foundation

/// Tiny newline-delimited text protocol over a Unix domain socket.
/// A client connects, writes one line such as `precmd 0` or `pet ghost`, and gets one
/// reply line back per request. The zsh hooks close without reading the reply, which is fine.
final class EventServer {
    enum Error: Swift.Error, CustomStringConvertible {
        case pathTooLong(String)
        case syscall(String, Int32)

        var description: String {
            switch self {
            case let .pathTooLong(p): return "socket path too long: \(p)"
            case let .syscall(name, code): return "\(name) failed: \(String(cString: strerror(code)))"
            }
        }
    }

    static var defaultPath: String {
        if let p = ProcessInfo.processInfo.environment["TERMINAL_PET_SOCKET"], !p.isEmpty { return p }
        return "/tmp/terminal-pet-\(getuid()).sock"
    }

    private let path: String
    private let handler: (String) -> String
    private let queue = DispatchQueue(label: "terminal-pet.events")
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?

    init(path: String, handler: @escaping (String) -> String) {
        self.path = path
        self.handler = handler
    }

    deinit { stop() }

    func start() throws {
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Error.syscall("socket", errno) }
        var addr = try Self.makeAddress(path)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard bound == 0 else { throw Error.syscall("bind", errno) }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { throw Error.syscall("listen", errno) }

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptClient() }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd); fd = -1 }
        unlink(path)
    }

    private func acceptClient() {
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        Self.configure(client, timeoutSeconds: 2)

        var pending: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 4096)
        while pending.count < 64 * 1024 {
            let n = read(client, &buf, buf.count)
            if n <= 0 { break }
            pending.append(contentsOf: buf[0..<n])
            while let nl = pending.firstIndex(of: 10) {
                let lineBytes = Array(pending[0..<nl])
                pending.removeFirst(nl + 1)
                respond(client, to: lineBytes)
            }
        }
        if !pending.isEmpty { respond(client, to: pending) }
    }

    private func respond(_ client: Int32, to bytes: [UInt8]) {
        guard let line = String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else { return }
        let handler = self.handler
        let reply = DispatchQueue.main.sync { handler(line) }
        let out = Array((reply + "\n").utf8)
        _ = out.withUnsafeBufferPointer { write(client, $0.baseAddress, $0.count) }
    }

    /// Never raise SIGPIPE when the peer has gone away, and don't block forever.
    private static func configure(_ sock: Int32, timeoutSeconds: Int) {
        var one: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Client side, used by `terminal-pet send ...` and the flag shortcuts.
    /// Returns the reply line, or nil when no pet is listening.
    static func send(_ message: String, path: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard var addr = try? makeAddress(path) else { return nil }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard rc == 0 else { return nil }
        configure(fd, timeoutSeconds: 5)
        let bytes = Array((message + "\n").utf8)
        guard write(fd, bytes, bytes.count) == bytes.count else { return nil }

        var reply: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 1024)
        while !reply.contains(10), reply.count < 64 * 1024 {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            reply.append(contentsOf: buf[0..<n])
        }
        return String(bytes: reply, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func makeAddress(_ path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < capacity else { throw Error.pathTooLong(path) }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                _ = path.withCString { strncpy(dst, $0, capacity - 1) }
            }
        }
        return addr
    }
}
