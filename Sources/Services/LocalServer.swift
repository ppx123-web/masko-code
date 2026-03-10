import Foundation

/// HTTP server built on BSD sockets + GCD.
/// Replaces the NWListener-based implementation which fails with POSIX 22
/// on macOS 26 for all TCP configurations.
@Observable
final class LocalServer {
    private var serverFd: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private(set) var isRunning = false
    private(set) var port: UInt16 = Constants.serverPort
    private(set) var host: String = Constants.serverHost
    private var stopped = false

    var onEventReceived: ((ClaudeEvent) -> Void)?
    var onPermissionRequest: ((ClaudeEvent, ClientConnection) -> Void)?
    var onInputReceived: ((String, ConditionValue) -> Void)?

    private var retryCount = 0
    private static let maxRetries = 10

    func start() throws {
        stopped = false
        stopServer()

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            let err = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE)
            scheduleRetry(reason: "bind failed", error: err)
            return
        }

        guard listen(fd, 10) == 0 else {
            Darwin.close(fd)
            let err = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
            scheduleRetry(reason: "listen failed", error: err)
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(fd, $0, &len)
                }
            }
            guard clientFd >= 0 else { return }
            self?.handleConnection(ClientConnection(fd: clientFd))
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()

        serverFd = fd
        acceptSource = source
        isRunning = true
        retryCount = 0
        print("[masko-desktop] Server listening on \(host):\(port)")
    }

    private func stopServer() {
        acceptSource?.cancel()
        acceptSource = nil
        serverFd = -1
        isRunning = false
    }

    private func scheduleRetry(reason: String, error: Error) {
        guard !stopped else { return }
        guard retryCount < Self.maxRetries else {
            print("[masko-desktop] Server gave up after \(Self.maxRetries) retries (last: \(reason) — \(error))")
            return
        }
        retryCount += 1
        let delay = min(Double(2 << retryCount), 30.0)
        print("[masko-desktop] Server \(reason): \(error) — retry \(retryCount)/\(Self.maxRetries) in \(Int(delay))s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped else { return }
            try? self.start()
        }
    }

    private func handleConnection(_ connection: ClientConnection) {
        var receivedData = Data()

        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                if let data { receivedData.append(data) }
                if self?.hasCompleteHTTPRequest(receivedData) == true || isComplete || error != nil {
                    self?.processRequest(receivedData, connection: connection)
                } else {
                    readMore()
                }
            }
        }

        readMore()
    }

    private func hasCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let str = String(data: data, encoding: .utf8) else { return false }

        if str.hasPrefix("GET ") { return str.contains("\r\n\r\n") }

        guard let separatorRange = str.range(of: "\r\n\r\n") else { return false }
        let headers = str[str.startIndex..<separatorRange.lowerBound]
        let body = str[separatorRange.upperBound...]

        if let clRange = headers.range(of: "Content-Length: ", options: .caseInsensitive) {
            let afterCL = headers[clRange.upperBound...]
            if let lineEnd = afterCL.firstIndex(of: "\r"),
               let contentLength = Int(afterCL[afterCL.startIndex..<lineEnd]) {
                return body.utf8.count >= contentLength
            }
        }
        return true
    }

    private func processRequest(_ data: Data, connection: ClientConnection) {
        guard let httpString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Bad Request")
            return
        }

        let firstLine = httpString.components(separatedBy: "\r\n").first ?? ""

        if firstLine.contains("GET /health") {
            sendResponse(connection: connection, status: "200 OK", body: "ok")
            return
        }

        guard let bodyRange = httpString.range(of: "\r\n\r\n") else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "No body")
            return
        }
        let bodyString = String(httpString[bodyRange.upperBound...])
        guard let bodyData = bodyString.data(using: .utf8) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Invalid body")
            return
        }

        if firstLine.contains("POST /hook") {
            let decoder = JSONDecoder()
            if let event = try? decoder.decode(ClaudeEvent.self, from: bodyData) {
                print("[masko-desktop] Hook received: \(event.hookEventName)")
                if event.eventType == .permissionRequest, let handler = onPermissionRequest {
                    DispatchQueue.main.async { handler(event, connection) }
                    DispatchQueue.main.async { [weak self] in self?.onEventReceived?(event) }
                    return
                }
                DispatchQueue.main.async { [weak self] in self?.onEventReceived?(event) }
            } else {
                print("[masko-desktop] Hook received but failed to decode JSON")
            }
            sendResponse(connection: connection, status: "200 OK", body: "OK")
            return
        }

        if firstLine.contains("POST /input") {
            if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
               let name = json["name"] as? String {
                let conditionValue: ConditionValue
                if let b = json["value"] as? Bool { conditionValue = .bool(b) }
                else if let n = json["value"] as? Double { conditionValue = .number(n) }
                else if let n = json["value"] as? Int { conditionValue = .number(Double(n)) }
                else {
                    sendResponse(connection: connection, status: "400 Bad Request", body: "value must be bool or number")
                    return
                }
                print("[masko-desktop] Input received: \(name) = \(json["value"] ?? "nil")")
                DispatchQueue.main.async { [weak self] in self?.onInputReceived?(name, conditionValue) }
                sendResponse(connection: connection, status: "200 OK", body: "OK")
            } else {
                sendResponse(connection: connection, status: "400 Bad Request", body: "Expected {\"name\":\"...\",\"value\":...}")
            }
            return
        }

        sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
    }

    private func sendResponse(connection: ClientConnection, status: String, body: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    func restart(port newPort: UInt16) {
        stop()
        Constants.setServerPort(newPort)
        port = newPort
        retryCount = 0
        try? HookInstaller.install()
        try? start()
    }

    func stop() {
        stopped = true
        stopServer()
    }

    deinit { stopServer() }
}
