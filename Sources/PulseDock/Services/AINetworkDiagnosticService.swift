import Foundation
import Network
import SystemConfiguration
import Darwin

private final class TCPProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let continuation: CheckedContinuation<Bool, Never>
    var connection: NWConnection?

    init(_ continuation: CheckedContinuation<Bool, Never>) { self.continuation = continuation }

    func finish(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        connection?.cancel()
        continuation.resume(returning: value)
    }
}

actor AINetworkDiagnosticService {
    private let ordinaryURL = URL(string: "https://www.apple.com/library/test/success.html")!
    private let chatGPTURL = URL(string: "https://chatgpt.com/")!
    private let apiURL = URL(string: "https://api.openai.com/v1/models")!

    func diagnose() async -> NetworkDiagnosticReport {
        var checks: [DiagnosticCheck] = []

        let ordinaryDNS = await resolve(host: ordinaryURL.host!)
        let openAIDNS = await resolve(host: apiURL.host!)
        checks.append(DiagnosticCheck(
            id: "dns-general", title: "普通网站 DNS", state: ordinaryDNS ? .passed : .failed,
            detail: ordinaryDNS ? "系统可以解析 Apple 域名" : "普通域名解析失败，优先检查 DNS 设置", latencyMS: nil
        ))
        checks.append(DiagnosticCheck(
            id: "dns-openai", title: "OpenAI DNS", state: openAIDNS ? .passed : .failed,
            detail: openAIDNS ? "api.openai.com 解析成功" : "OpenAI 域名无法解析，可能被 DNS 污染或拦截", latencyMS: nil
        ))

        if !ordinaryDNS {
            return report(.failed, "DNS 解析异常", "切换 DNS 或暂时关闭代理后重试；当前不是 Codex 服务自身故障。", checks)
        }

        let proxy = Self.systemProxyEndpoint()
        if let proxy {
            let localProxy = await connect(host: proxy.host, port: proxy.port)
            checks.append(DiagnosticCheck(
                id: "proxy-port", title: "本地代理端口", state: localProxy ? .passed : .failed,
                detail: localProxy ? "\(proxy.host):\(proxy.port) 可连接" : "系统代理已开启，但本地端口无法连接",
                latencyMS: nil
            ))
            if !localProxy {
                return report(.failed, "Clash 或代理核心不可用", "打开代理客户端、切换节点或关闭失效的系统代理。", checks)
            }
        } else {
            checks.append(DiagnosticCheck(id: "proxy-port", title: "系统代理", state: .warning, detail: "未检测到 HTTP/HTTPS/SOCKS 系统代理；TUN 模式仍可能生效", latencyMS: nil))
        }

        let ordinary = await multiProbe(ordinaryURL, direct: false, count: 3)
        checks.append(check(id: "https-general", title: "普通网站 TLS", result: ordinary))
        if !ordinary.reachable {
            let reason = ordinary.isTLSError ? "TLS 握手失败" : "普通互联网连接失败"
            return report(.failed, reason, ordinary.isTLSError ? "检查系统时间、证书、HTTPS 解密和代理证书设置。" : "检查 Wi‑Fi、DNS、Clash 节点和系统代理。", checks)
        }

        async let chatGPTTask = multiProbe(chatGPTURL, direct: false, count: 3)
        async let apiTask = multiProbe(apiURL, direct: false, count: 3)
        let (chatGPT, api) = await (chatGPTTask, apiTask)
        checks.append(check(id: "chatgpt", title: "ChatGPT 域名", result: chatGPT))
        checks.append(check(id: "openai-api", title: "OpenAI API 域名", result: api))

        if !chatGPT.reachable || !api.reachable {
            if chatGPT.isTLSError || api.isTLSError {
                return report(.failed, "OpenAI TLS 握手失败", "检查代理证书、HTTPS 解密、系统时间或切换 Clash 节点。", checks)
            }
            let direct = await httpsProbe(apiURL, direct: true)
            checks.append(check(id: "openai-direct", title: "OpenAI 直连对照", result: direct))
            if direct.reachable, proxy != nil {
                return report(.failed, "代理规则可能走错", "直连可访问、系统代理路径失败；检查 OpenAI 域名的 Clash 分流规则。", checks)
            }
            return report(.failed, "OpenAI 域名被阻断或节点不可用", "普通网站正常但 OpenAI 不可达；切换代理节点并检查 OpenAI/ChatGPT 规则。", checks)
        }

        if (chatGPT.statusCode ?? 0) >= 500 || (api.statusCode ?? 0) >= 500 {
            return report(.degraded, "OpenAI 服务返回服务器错误", "网络、DNS 与 TLS 均正常；更可能是远端服务暂时异常，请稍后重试。", checks)
        }

        if let ordinaryLatency = ordinary.latencyMS {
            let aiLatency = max(chatGPT.latencyMS ?? 0, api.latencyMS ?? 0)
            if aiLatency > max(800, ordinaryLatency * 3) {
                return report(.degraded, "AI 路径较慢，未发现服务不可用", "OpenAI 与 ChatGPT 均可达；当前采样比普通网站慢。若连续多次仍影响使用，再考虑切换 Clash 节点或检查分流规则。", checks)
            }
        }

        return report(.healthy, "网络与 OpenAI 连接正常", "若 Codex 仍然报错，请继续查看 Codex 本地服务检查。", checks)
    }

    private func report(_ health: AIServiceHealth, _ summary: String, _ recommendation: String, _ checks: [DiagnosticCheck]) -> NetworkDiagnosticReport {
        NetworkDiagnosticReport(health: health, summary: summary, recommendation: recommendation, checks: checks, completedAt: Date())
    }

    private func check(id: String, title: String, result: HTTPSProbeResult) -> DiagnosticCheck {
        DiagnosticCheck(
            id: id, title: title, state: result.reachable ? .passed : (result.isTLSError ? .failed : .warning),
            detail: result.detail, latencyMS: result.latencyMS
        )
    }

    private func resolve(host: String) async -> Bool {
        await Task.detached(priority: .utility) {
            var hints = addrinfo(ai_flags: AI_ADDRCONFIG, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, "443", &hints, &result)
            if let result { freeaddrinfo(result) }
            return status == 0
        }.value
    }

    private func connect(host: String, port: UInt16) async -> Bool {
        await withCheckedContinuation { continuation in
            let completion = TCPProbeCompletion(continuation)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            completion.connection = connection
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: completion.finish(true)
                case .failed, .cancelled: completion.finish(false)
                default: break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { completion.finish(false) }
        }
    }

    private func httpsProbe(_ url: URL, direct: Bool) async -> HTTPSProbeResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 7
        configuration.timeoutIntervalForResource = 8
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if direct { configuration.connectionProxyDictionary = [:] }
        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("PulseDock/4.0", forHTTPHeaderField: "User-Agent")
        let start = ContinuousClock.now
        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = start.duration(to: .now)
            let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
            let status = (response as? HTTPURLResponse)?.statusCode
            return HTTPSProbeResult(reachable: status.map { (100...599).contains($0) } ?? true, statusCode: status, latencyMS: milliseconds, errorCode: nil, isTLSError: false, detail: status.map { "HTTP \($0) · \(Int(milliseconds)) ms" } ?? "连接成功 · \(Int(milliseconds)) ms")
        } catch {
            let urlError = error as? URLError
            let tlsCodes: Set<URLError.Code> = [.secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .clientCertificateRejected, .clientCertificateRequired]
            let isTLS = urlError.map { tlsCodes.contains($0.code) } ?? false
            return HTTPSProbeResult(reachable: false, statusCode: nil, latencyMS: nil, errorCode: urlError?.code.rawValue, isTLSError: isTLS, detail: isTLS ? "TLS 握手或证书校验失败" : Self.errorDescription(urlError))
        }
    }

    /// Three bounded probes distinguish a consistently slow AI route from a
    /// single cold TLS connection. The median drives classification while the
    /// range remains visible evidence for unstable paths.
    private func multiProbe(_ url: URL, direct: Bool, count: Int) async -> HTTPSProbeResult {
        var results: [HTTPSProbeResult] = []
        for index in 0..<max(1, count) {
            try? Task.checkCancellation()
            results.append(await httpsProbe(url, direct: direct))
            if index + 1 < count { try? await Task.sleep(for: .milliseconds(350)) }
        }
        let reachable = results.filter(\.reachable)
        guard reachable.count >= (results.count / 2 + 1) else {
            let tlsFailures = results.filter(\.isTLSError).count
            let representative = results.last(where: { !$0.reachable }) ?? results[0]
            return HTTPSProbeResult(
                reachable: false,
                statusCode: representative.statusCode,
                latencyMS: nil,
                errorCode: representative.errorCode,
                isTLSError: tlsFailures >= (results.count / 2 + 1),
                detail: "三轮采样仅 \(reachable.count)/\(results.count) 次可达 · \(representative.detail)"
            )
        }
        let latencies = reachable.compactMap(\.latencyMS).sorted()
        let median = latencies.isEmpty ? nil : latencies[latencies.count / 2]
        let range = latencies.first.flatMap { low in latencies.last.map { high in "\(Int(low))–\(Int(high)) ms" } }
        let status = reachable.compactMap(\.statusCode).first
        let statusText = status.map { "HTTP \($0)" } ?? "连接成功"
        return HTTPSProbeResult(
            reachable: true,
            statusCode: status,
            latencyMS: median,
            errorCode: nil,
            isTLSError: false,
            detail: "\(statusText) · 中位 \(Int(median ?? 0)) ms · 范围 \(range ?? "--") · \(reachable.count)/\(results.count) 次可达"
        )
    }

    private nonisolated static func systemProxyEndpoint() -> (host: String, port: UInt16)? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return nil }
        let candidates = [
            (kSCPropNetProxiesHTTPEnable as String, kSCPropNetProxiesHTTPProxy as String, kSCPropNetProxiesHTTPPort as String),
            (kSCPropNetProxiesHTTPSEnable as String, kSCPropNetProxiesHTTPSProxy as String, kSCPropNetProxiesHTTPSPort as String),
            (kSCPropNetProxiesSOCKSEnable as String, kSCPropNetProxiesSOCKSProxy as String, kSCPropNetProxiesSOCKSPort as String)
        ]
        for (enabledKey, hostKey, portKey) in candidates where (settings[enabledKey] as? Int) == 1 {
            if let host = settings[hostKey] as? String,
               let number = settings[portKey] as? NSNumber,
               let port = UInt16(exactly: number.intValue) { return (host, port) }
        }
        return nil
    }

    private nonisolated static func errorDescription(_ error: URLError?) -> String {
        guard let error else { return "未知网络错误" }
        switch error.code {
        case .dnsLookupFailed, .cannotFindHost: return "DNS 解析失败"
        case .cannotConnectToHost: return "无法连接目标服务器"
        case .notConnectedToInternet: return "没有可用网络"
        case .timedOut: return "连接超时"
        case .networkConnectionLost: return "连接中途断开"
        default: return "网络错误（\(error.code.rawValue)）"
        }
    }
}
