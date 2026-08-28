import Foundation
import SwiftUI

enum RemoteTaskDisclosureMode: String, Codable, CaseIterable, Sendable {
    case schedulerOnly
    case redactedCommand

    var label: String {
        switch self {
        case .schedulerOnly: "仅 Slurm / 调度器任务"
        case .redactedCommand: "显示脱敏启动命令"
        }
    }
}

enum RemoteNetworkScope: String, Codable, CaseIterable, Sendable {
    case automatic
    case localLAN
    case vpn
    case publicInternet

    var label: String {
        switch self {
        case .automatic: "自动判断"
        case .localLAN: "仅局域网"
        case .vpn: "需要 VPN"
        case .publicInternet: "公网可达"
        }
    }

    var shortLabel: String {
        switch self {
        case .automatic: "自动"
        case .localLAN: "局域网"
        case .vpn: "VPN"
        case .publicInternet: "公网"
        }
    }

    var symbol: String {
        switch self {
        case .automatic: "wand.and.stars"
        case .localLAN: "house.and.flag"
        case .vpn: "lock.shield"
        case .publicInternet: "globe"
        }
    }

    var color: Color {
        switch self {
        case .automatic: .secondary
        case .localLAN: .green
        case .vpn: .purple
        case .publicInternet: .blue
        }
    }
}

struct RemoteDeviceConfiguration: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    var name: String
    var sshAlias: String
    var enabled = true
    var intervalSeconds = 60
    var collectProcessOwners = false
    var collectSchedulerJobs = false
    var taskDisclosureMode: RemoteTaskDisclosureMode = .schedulerOnly
    var networkScope: RemoteNetworkScope = .automatic
    var pinned = false
    var sortOrder = 0

    enum CodingKeys: String, CodingKey { case id, name, sshAlias, enabled, intervalSeconds, collectProcessOwners, collectSchedulerJobs, taskDisclosureMode, networkScope, pinned, sortOrder }
    init(id: UUID = UUID(), name: String, sshAlias: String, enabled: Bool = true, intervalSeconds: Int = 60, collectProcessOwners: Bool = false, collectSchedulerJobs: Bool = false, taskDisclosureMode: RemoteTaskDisclosureMode = .schedulerOnly, networkScope: RemoteNetworkScope = .automatic, pinned: Bool = false, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.sshAlias = sshAlias; self.enabled = enabled; self.intervalSeconds = intervalSeconds
        self.collectProcessOwners = collectProcessOwners; self.collectSchedulerJobs = collectSchedulerJobs; self.taskDisclosureMode = taskDisclosureMode
        self.networkScope = networkScope; self.pinned = pinned; self.sortOrder = sortOrder
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name); sshAlias = try c.decode(String.self, forKey: .sshAlias)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        intervalSeconds = try c.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? 60
        collectProcessOwners = try c.decodeIfPresent(Bool.self, forKey: .collectProcessOwners) ?? false
        collectSchedulerJobs = try c.decodeIfPresent(Bool.self, forKey: .collectSchedulerJobs) ?? false
        taskDisclosureMode = try c.decodeIfPresent(RemoteTaskDisclosureMode.self, forKey: .taskDisclosureMode) ?? .schedulerOnly
        networkScope = try c.decodeIfPresent(RemoteNetworkScope.self, forKey: .networkScope) ?? .automatic
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}

enum RemoteHealth: String, Codable, Sendable {
    case waiting, healthy, degraded, offline, expectedOffline
    var label: String { switch self { case .waiting: "等待检测"; case .healthy: "健康"; case .degraded: "部分异常"; case .offline: "SSH 不可用"; case .expectedOffline: "当前网络暂停" } }
    var color: Color { switch self { case .waiting, .expectedOffline: .secondary; case .healthy: .green; case .degraded: .orange; case .offline: .red } }
}

struct RemoteGPUProcess: Identifiable, Codable, Sendable, Equatable {
    var id: Int { pid }
    var pid: Int
    var name: String
    var memoryMiB: Int
    var gpuIndices: [Int]
    var user: String?
    var elapsed: String?
    var redactedCommand: String?
}

struct RemoteGPU: Identifiable, Codable, Sendable, Equatable {
    var id: Int { index }
    var index: Int
    var uuid: String
    var name: String
    var utilizationPercent: Double?
    var memoryUsedMiB: Int
    var memoryTotalMiB: Int
    var temperatureCelsius: Double?
    var powerWatts: Double?
    var memoryPercent: Double { memoryTotalMiB > 0 ? max(0, min(100, Double(memoryUsedMiB) * 100 / Double(memoryTotalMiB))) : 0 }
}

struct RemoteScheduledJob: Identifiable, Codable, Sendable, Equatable {
    var id: String { jobID }
    var jobID: String
    var name: String
    var state: String
    var elapsed: String
    var timeLimit: String
    var expectedEnd: String
}

struct RemoteDeviceSnapshot: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var health: RemoteHealth = .waiting
    var hostName = "--"
    var latencyMS: Double?
    var load1: Double?
    var memoryUsedPercent: Double?
    var diskUsedPercent: Double?
    var codexFound = false
    var codexVersion: String?
    var codexPath: String?
    var codexDiscoveryDetail = "等待探测"
    var codexEndpointStatus: Int?
    var codexEndpointDetail = "等待端点探测"
    var diagnosticEvidence = ""
    var gpus: [RemoteGPU] = []
    var gpuProcesses: [RemoteGPUProcess] = []
    var taskCollectionDetail = "等待任务采集"
    var scheduledJobs: [RemoteScheduledJob] = []
    var schedulerCollectionDetail = "等待调度器采集"
    var checkedAt: Date?
    var message = "等待首次检测"

    var totalGPUUsedMiB: Int { Self.cappedSum(gpus.map(\.memoryUsedMiB)) }
    var totalGPUTotalMiB: Int { Self.cappedSum(gpus.map(\.memoryTotalMiB)) }
    var gpuMemorySummary: String {
        guard totalGPUTotalMiB > 0 else { return "--" }
        return String(format: "%.1f / %.1f GB", Double(totalGPUUsedMiB) / 1_024, Double(totalGPUTotalMiB) / 1_024)
    }

    private static func cappedSum(_ values: [Int]) -> Int {
        values.reduce(into: 0) { total, raw in
            let value = max(0, raw)
            total = total > Int.max - value ? Int.max : total + value
        }
    }
}
