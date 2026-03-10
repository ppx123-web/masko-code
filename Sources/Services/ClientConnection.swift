import Foundation

/// BSD socket-based connection, drop-in replacement for NWConnection.
/// NWListener (Network framework) is broken on macOS 26 — all configurations
/// return POSIX 22. BSD sockets work fine.
final class ClientConnection {
    enum State { case ready, cancelled, failed }

    enum SendCompletion {
        case contentProcessed((Error?) -> Void)
        case idempotent
    }

    private let fd: Int32
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var _state: State = .ready

    var stateUpdateHandler: ((State) -> Void)?

    var state: State {
        lock.withLock { _state }
    }

    init(fd: Int32) {
        self.fd = fd
        self.queue = DispatchQueue(label: "com.masko.conn.\(fd)", qos: .userInitiated)
    }

    func send(content: Data?, completion: SendCompletion) {
        guard let data = content else {
            if case .contentProcessed(let cb) = completion { cb(nil) }
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            guard self.state == .ready else {
                if case .contentProcessed(let cb) = completion { cb(POSIXError(.EBADF)) }
                return
            }
            var remaining = data
            var writeError: Error?
            while !remaining.isEmpty {
                let n = remaining.withUnsafeBytes { Darwin.write(self.fd, $0.baseAddress!, $0.count) }
                if n <= 0 {
                    writeError = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    break
                }
                remaining = remaining.dropFirst(n)
            }
            if case .contentProcessed(let cb) = completion { cb(writeError) }
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self._state == .ready else { self.lock.unlock(); return }
            self._state = .cancelled
            self.lock.unlock()
            Darwin.close(self.fd)
            DispatchQueue.main.async { self.stateUpdateHandler?(.cancelled) }
        }
    }

    func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping (Data?, Any?, Bool, Error?) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, self.state == .ready else {
                DispatchQueue.main.async { completion(nil, nil, true, nil) }
                return
            }
            var buf = [UInt8](repeating: 0, count: maximumLength)
            let n = Darwin.recv(self.fd, &buf, maximumLength, 0)
            if n <= 0 {
                DispatchQueue.main.async { completion(nil, nil, true, nil) }
            } else {
                let data = Data(buf.prefix(n))
                DispatchQueue.main.async { completion(data, nil, false, nil) }
            }
        }
    }

    deinit {
        if state == .ready { Darwin.close(fd) }
    }
}
