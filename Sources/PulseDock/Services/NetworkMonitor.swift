import Foundation
import Network
import SystemConfiguration

struct IPLookupResponse: Decodable, Sendable {
    struct Connection: Decodable, Sendable { let isp: String? }
    struct Timezone: Decodable, Sendable { let id: String? }
    let success: Bool?
    let ip: String?
    let country: String?
    let country_code: String?
    let region: String?
    let city: String?
    let timezone: Timezone?
    let connection: Connection?

    var identity: IPIdentity {
        IPIdentity(
            address: ip ?? "--",
            country: country ?? "未知",
            countryCode: country_code ?? "",
            region: region ?? "",
            city: city ?? "",
            isp: connection?.isp ?? "",
            timezone: timezone?.id ?? ""
        )
    }
}

final class PathObserver: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "PulseDock.NetworkPath")
    var onUpdate: (@Sendable (NWPath) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in self?.onUpdate?(path) }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
}

enum ProxyDetector {
    static func systemProxyEnabled() -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return false }
        let http = settings[kSCPropNetProxiesHTTPEnable as String] as? Int ?? 0
        let https = settings[kSCPropNetProxiesHTTPSEnable as String] as? Int ?? 0
        let socks = settings[kSCPropNetProxiesSOCKSEnable as String] as? Int ?? 0
        return http == 1 || https == 1 || socks == 1
    }
}

actor NetworkProbe {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    func latency(to url: URL = URL(string: "https://www.apple.com/library/test/success.html")!) async -> (Double?, String?) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let start = ContinuousClock.now
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = start.duration(to: .now)
            let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            guard let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) else {
                return (nil, "目标服务返回异常")
            }
            return (milliseconds, nil)
        } catch {
            return (nil, Self.describe(error))
        }
    }

    func lookupIP() async throws -> IPIdentity {
        let url = URL(string: "https://ipwho.is/")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(IPLookupResponse.self, from: data).identity
    }

    private static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return "网络请求失败" }
        return switch urlError.code {
        case .notConnectedToInternet: "没有可用网络"
        case .dnsLookupFailed, .cannotFindHost: "DNS 解析失败"
        case .cannotConnectToHost: "无法连接目标服务器"
        case .secureConnectionFailed, .serverCertificateUntrusted: "TLS 安全连接失败"
        case .timedOut: "连接超时"
        default: "网络请求失败（\(urlError.code.rawValue)）"
        }
    }
}
