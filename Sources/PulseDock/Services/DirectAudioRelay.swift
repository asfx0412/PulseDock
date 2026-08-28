import Foundation
import Network

/// A session-scoped loopback relay used only when an audio stream cannot be
/// reached through the system proxy. It never changes system or Clash
/// settings, accepts one opaque path on 127.0.0.1, and is destroyed on stop.
final class DirectAudioRelay: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum RelayError: LocalizedError {
        case invalidSource
        case listenerFailed(String)
        case upstreamFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidSource: "智能直连拒绝了不安全的音源地址"
            case .listenerFailed(let value): "无法启动会话级音频中转：\(value)"
            case .upstreamFailed(let value): "音频直连失败：\(value)"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.pulsedock.audio-relay")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connection: NWConnection?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var upstream: URL?
    private var token = ""
    private var responseStarted = false

    func start(upstream: URL) async throws -> URL {
        guard Self.isSafePublicHTTPS(upstream) else { throw RelayError.invalidSource }
        stop()
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let listener = try NWListener(using: .tcp, on: .any)
        self.upstream = upstream
        self.token = token
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }

        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            let gate = CompletionGate<NWEndpoint.Port>(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port { gate.resume(returning: port) }
                    else { gate.resume(throwing: RelayError.listenerFailed("未分配本机端口")) }
                case .failed(let error): gate.resume(throwing: RelayError.listenerFailed(error.localizedDescription))
                case .cancelled: gate.resume(throwing: RelayError.listenerFailed("监听已取消"))
                default: break
                }
            }
            listener.start(queue: queue)
        }
        guard let url = URL(string: "http://127.0.0.1:\(port.rawValue)/\(token)") else { throw RelayError.listenerFailed("本机地址无效") }
        return url
    }

    func stop() {
        lock.lock()
        let listener = self.listener
        let connection = self.connection
        let task = self.task
        let session = self.session
        self.listener = nil
        self.connection = nil
        self.task = nil
        self.session = nil
        self.upstream = nil
        self.token = ""
        self.responseStarted = false
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        connection?.cancel()
        listener?.cancel()
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        guard self.connection == nil else {
            lock.unlock()
            connection.cancel()
            return
        }
        self.connection = connection
        let expectedPath = "/\(token)"
        let upstream = self.upstream
        lock.unlock()
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data, data.count <= 16_384,
                  let request = String(data: data, encoding: .utf8),
                  request.hasPrefix("GET \(expectedPath) "),
                  let upstream else {
                self.sendFailure("400 Bad Request")
                return
            }
            self.beginUpstream(upstream)
        }
    }

    private func beginUpstream(_ url: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.setValue("PulseDock/6.8.0", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request)
        lock.lock(); self.session = session; self.task = task; lock.unlock()
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              Self.isSafePublicHTTPS(http.url) else {
            sendFailure("502 Bad Gateway")
            completionHandler(.cancel)
            return
        }
        let mime = response.mimeType?.prefix(96) ?? "audio/mpeg"
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        lock.lock(); responseStarted = true; let connection = self.connection; lock.unlock()
        connection?.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); let connection = self.connection; lock.unlock()
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(Self.isSafePublicHTTPS(request.url) ? request : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let started = responseStarted; let connection = self.connection; lock.unlock()
        if let error, !started { sendFailure("502 Bad Gateway", detail: error.localizedDescription) }
        else { connection?.send(content: nil, isComplete: true, completion: .contentProcessed { _ in }) }
    }

    private func sendFailure(_ status: String, detail: String? = nil) {
        let safeDetail = detail.map { String($0.prefix(160)) } ?? "Audio relay failed"
        let body = Data(safeDetail.utf8)
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        lock.lock(); let connection = self.connection; lock.unlock()
        connection?.send(content: Data(response.utf8) + body, isComplete: true, completion: .contentProcessed { _ in })
    }

    static func isSafePublicHTTPS(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), host.contains("."),
              host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local") else { return false }
        if host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") { return false }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) {
            let a = parts[0], b = parts[1]
            if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 168 { return false }
            if a == 100 && (64...127).contains(b) { return false }
        }
        return true
    }
}

private final class CompletionGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }

    func resume(returning value: Value) {
        lock.lock(); let continuation = self.continuation; self.continuation = nil; lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock(); let continuation = self.continuation; self.continuation = nil; lock.unlock()
        continuation?.resume(throwing: error)
    }
}
