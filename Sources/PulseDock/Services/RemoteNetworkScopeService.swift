import Darwin
import Foundation
import Network

private final class RemoteTCPProbeCompletion: @unchecked Sendable {
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

struct RemoteLANAssessment: Sendable, Equatable {
    var shouldProbe: Bool
    var message: String
}

/// Resolves an SSH alias, then combines local subnet, physical-interface route
/// and bounded SSH-port evidence. It never uses the public/proxy exit IP: a
/// Clash node must not make a LAN host look locally reachable.
actor RemoteNetworkScopeService {
    func assessLocalLAN(alias: String) async -> RemoteLANAssessment {
        let subnetAssessment = await Task.detached(priority: .utility) {
            Self.assessLocalLANSync(alias: alias)
        }.value
        guard !subnetAssessment.shouldProbe,
              let endpoint = await Task.detached(priority: .utility, operation: { Self.sshEndpoint(alias: alias) }).value else { return subnetAssessment }
        let privateTargets = await Task.detached(priority: .utility) {
            Self.resolveIPv4(host: endpoint.host).filter(Self.isPrivateIPv4)
        }.value
        guard !privateTargets.isEmpty else { return subnetAssessment }

        // A dedicated route through a physical interface proves that the Mac
        // is on the office/robot network even while the robot is powered off.
        // A default route is deliberately rejected because every private IP
        // would otherwise look local on an unrelated home network.
        let hasLocalRoute = await Task.detached(priority: .utility) {
            privateTargets.contains(where: Self.hasSpecificPhysicalRoute)
        }.value
        if hasLocalRoute {
            return .init(
                shouldProbe: true,
                message: "目标不在当前本机子网，但存在经物理网卡的专用局域网路由；允许只读探测"
            )
        }

        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else { return subnetAssessment }

        // Private office and robot networks are often routed across VLANs:
        // 192.168.x on the Mac and 10.x on the robot can still be the same
        // physical LAN. A bounded TCP handshake to the SSH endpoint supplies
        // actual reachability evidence without authenticating or running any
        // remote command.
        let reachable = await tcpReachable(host: endpoint.host, port: port)
        if Self.permitsRoutedPrivateTarget(hasPrivateTarget: true, tcpReachable: reachable) {
            return .init(
                shouldProbe: true,
                message: "目标不在当前本机子网，但 SSH 端口可经当前局域网路由到达；允许只读探测"
            )
        }
        return subnetAssessment
    }

    nonisolated static func assessLocalLANSync(alias: String) -> RemoteLANAssessment {
        guard SSHMonitorService.validAlias(alias) else {
            return .init(shouldProbe: false, message: "局域网设备的 SSH 别名无效，已暂停探测")
        }
        let host = sshEndpoint(alias: alias)?.host ?? alias
        let targets = resolveIPv4(host: host)
        guard !targets.isEmpty else {
            return .init(shouldProbe: false, message: "局域网外或本地 DNS 不可用：无法解析目标 \(host)，已暂停 SSH 探测与告警")
        }
        let privateTargets = targets.filter(isPrivateIPv4)
        guard !privateTargets.isEmpty else {
            return .init(shouldProbe: false, message: "设备被标记为局域网，但目标解析为公网地址；请改为“公网”或检查 SSH HostName")
        }
        let networks = activeLocalNetworks()
        if privateTargets.contains(where: { target in networks.contains(where: { ($0.address & $0.mask) == (target & $0.mask) }) }) {
            return .init(shouldProbe: true, message: "当前本机子网包含该局域网目标")
        }
        let local = networks.map(\.description).prefix(3).joined(separator: "、")
        let target = privateTargets.compactMap(ipv4String).joined(separator: "、")
        let evidence = local.isEmpty ? "当前没有活动的私有 IPv4 子网" : "当前子网 \(local)"
        return .init(shouldProbe: false, message: "局域网范围不匹配：\(evidence)，目标 \(target)；已暂停 SSH 探测与告警")
    }

    struct IPv4Network: Equatable {
        var address: UInt32
        var mask: UInt32
        var name: String
        var description: String {
            let network = address & mask
            return "\(name) \(ipv4String(network) ?? "--")/\(mask.nonzeroBitCount)"
        }
    }

    nonisolated static func activeLocalNetworks() -> [IPv4Network] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var result: [IPv4Network] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let item = cursor?.pointee {
            defer { cursor = item.ifa_next }
            guard let address = item.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  let mask = item.ifa_netmask,
                  item.ifa_flags & UInt32(IFF_UP) != 0,
                  item.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  item.ifa_flags & UInt32(IFF_POINTOPOINT) == 0 else { continue }
            let name = String(cString: item.ifa_name)
            guard !name.hasPrefix("utun"), !name.hasPrefix("awdl"), !name.hasPrefix("llw") else { continue }
            let addr = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            guard isPrivateIPv4(addr) else { continue }
            result.append(.init(address: addr, mask: netmask, name: name))
        }
        return result
    }

    nonisolated static func sameSubnet(local: UInt32, mask: UInt32, target: UInt32) -> Bool {
        (local & mask) == (target & mask)
    }

    nonisolated static func permitsRoutedPrivateTarget(hasPrivateTarget: Bool, tcpReachable: Bool) -> Bool {
        hasPrivateTarget && tcpReachable
    }

    nonisolated static func permitsSpecificPhysicalRoute(destination: String, interface: String, activeInterfaces: Set<String>) -> Bool {
        destination.lowercased() != "default"
            && destination != "0.0.0.0"
            && activeInterfaces.contains(interface)
    }

    nonisolated static func parseIPv4(_ value: String) -> UInt32? {
        var address = in_addr()
        guard inet_pton(AF_INET, value, &address) == 1 else { return nil }
        return address.s_addr
    }

    private nonisolated static func sshEndpoint(alias: String) -> (host: String, port: UInt16)? {
        let process = Process(); let output = Pipe(); let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = ["-G", alias]
        process.standardOutput = output; process.standardError = error
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile().prefix(256_000), as: UTF8.self)
        let lines = text.split(separator: "\n")
        guard let host = lines.first(where: { $0.lowercased().hasPrefix("hostname ") })
            .map({ String($0.dropFirst("hostname ".count)).trimmingCharacters(in: .whitespaces) }),
              !host.isEmpty else { return nil }
        let port = lines.first(where: { $0.lowercased().hasPrefix("port ") })
            .flatMap { UInt16($0.dropFirst("port ".count).trimmingCharacters(in: .whitespaces)) } ?? 22
        return (host, port)
    }

    private nonisolated static func hasSpecificPhysicalRoute(target: UInt32) -> Bool {
        guard let targetText = ipv4String(target) else { return false }
        let process = Process(); let output = Pipe(); let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", targetText]
        process.standardOutput = output; process.standardError = error
        do { try process.run(); process.waitUntilExit() } catch { return false }
        guard process.terminationStatus == 0 else { return false }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile().prefix(64_000), as: UTF8.self)
        var fields: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let parts = rawLine.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { fields[parts[0].lowercased()] = parts[1] }
        }
        guard let destination = fields["destination"], let interface = fields["interface"] else { return false }
        return permitsSpecificPhysicalRoute(
            destination: destination,
            interface: interface,
            activeInterfaces: Set(activeLocalNetworks().map(\.name))
        )
    }

    private func tcpReachable(host: String, port: NWEndpoint.Port) async -> Bool {
        await withCheckedContinuation { continuation in
            let completion = RemoteTCPProbeCompletion(continuation)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
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

    private nonisolated static func resolveIPv4(host: String) -> [UInt32] {
        if let literal = parseIPv4(host) { return [literal] }
        var hints = addrinfo(ai_flags: AI_ADDRCONFIG, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0 else { return [] }
        defer { freeaddrinfo(result) }
        var values: [UInt32] = []
        var cursor = result
        while let info = cursor?.pointee {
            if let raw = info.ai_addr, raw.pointee.sa_family == UInt8(AF_INET) {
                let value = raw.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                if !values.contains(value) { values.append(value) }
            }
            cursor = info.ai_next
        }
        return values
    }

    private nonisolated static func isPrivateIPv4(_ value: UInt32) -> Bool {
        guard let text = ipv4String(value) else { return false }
        let parts = text.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 169 && parts[1] == 254)
    }

    private nonisolated static func ipv4String(_ value: UInt32) -> String? {
        var address = in_addr(s_addr: value)
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
        return String(cString: buffer)
    }
}
