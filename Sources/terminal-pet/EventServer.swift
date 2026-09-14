import Foundation

/// Tiny newline-delimited text protocol over a Unix domain socket.
/// The zsh plugin connects, writes one line such as `precmd 0`, and closes.
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
    private let handler: (String) -> Void
    private let queue = DispatchQueue(label: "terminal-pet.events")
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?

    init(path: String, handler: @escaping (String) -> Void) {
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
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while data.count < 64 * 1024 {
            let n = read(client, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
        }
        guard let text = String(data: data, encoding: .utf8) else { return }
        let handler = self.handler
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { DispatchQueue.main.async { handler(line) } }
        }
    }

    /// Client side, used by `terminal-pet send ...`.
    static func send(_ message: String, path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard var addr = try? makeAddress(path) else { return false }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard rc == 0 else { return false }
        let bytes = Array((message + "\n").utf8)
        return write(fd, bytes, bytes.count) == bytes.count
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
