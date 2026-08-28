import Foundation

enum AudioPlaybackFailureKind: String, Sendable {
    case tls = "TLS/证书失败"
    case dns = "DNS 解析失败"
    case connection = "连接失败"
    case timeout = "首包超时"
    case interrupted = "直播流中断"
    case unsupported = "不支持的音频格式"
    case http = "源站 HTTP 错误"
    case unknown = "未知播放错误"
}

struct AudioStreamPreflightResult: Sendable {
    var reachable: Bool
    var kind: AudioPlaybackFailureKind?
    var detail: String
    var latencyMS: Double?
}

/// Reads at most the first response byte. This cannot promise long-term stream
/// health, but it prevents an already failed DNS/TLS/HTTP path from becoming an
/// unbounded AVPlayer loading spinner.
actor AudioStreamPreflightService {
    func inspect(_ url: URL, direct: Bool) async -> AudioStreamPreflightResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 7
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if direct { configuration.connectionProxyDictionary = [:] }
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        request.setValue("audio/*, application/vnd.apple.mpegurl, application/octet-stream;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("PulseDock/6.12.3", forHTTPHeaderField: "User-Agent")
        let start = ContinuousClock.now
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .init(reachable: false, kind: .unknown, detail: "源站未返回 HTTP 响应", latencyMS: nil)
            }
            guard (200..<400).contains(http.statusCode) else {
                return .init(reachable: false, kind: .http, detail: "源站返回 HTTP \(http.statusCode)", latencyMS: nil)
            }
            var iterator = bytes.makeAsyncIterator()
            guard try await iterator.next() != nil else {
                return .init(reachable: false, kind: .interrupted, detail: "连接成功但未收到音频首包", latencyMS: nil)
            }
            let elapsed = start.duration(to: .now)
            let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
            let mime = (http.value(forHTTPHeaderField: "Content-Type") ?? "未知格式").split(separator: ";").first.map(String.init) ?? "未知格式"
            return .init(reachable: true, kind: nil, detail: "首包可达 · HTTP \(http.statusCode) · \(mime) · \(Int(milliseconds)) ms", latencyMS: milliseconds)
        } catch {
            let urlError = error as? URLError
            let kind = Self.classify(urlError)
            return .init(reachable: false, kind: kind, detail: Self.detail(urlError), latencyMS: nil)
        }
    }

    nonisolated static func classify(_ error: URLError?) -> AudioPlaybackFailureKind {
        guard let error else { return .unknown }
        switch error.code {
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .clientCertificateRejected, .clientCertificateRequired: return .tls
        case .dnsLookupFailed, .cannotFindHost: return .dns
        case .cannotConnectToHost, .notConnectedToInternet: return .connection
        case .timedOut: return .timeout
        case .networkConnectionLost: return .interrupted
        case .cannotDecodeContentData, .cannotDecodeRawData, .unsupportedURL: return .unsupported
        default: return .unknown
        }
    }

    private nonisolated static func detail(_ error: URLError?) -> String {
        guard let error else { return "未知网络错误" }
        return "\(classify(error).rawValue)（\(error.code.rawValue)）"
    }
}
