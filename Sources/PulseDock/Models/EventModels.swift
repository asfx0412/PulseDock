import Foundation
import SwiftUI

enum TimelineCategory: String, Codable, CaseIterable, Sendable {
    case network, remote, quota, thermal, clash, pomodoro, system

    var label: String {
        switch self {
        case .network: "网络"
        case .remote: "远程设备"
        case .quota: "额度"
        case .thermal: "热风险"
        case .clash: "Clash"
        case .pomodoro: "专注"
        case .system: "系统"
        }
    }

    var symbol: String {
        switch self {
        case .network: "network"
        case .remote: "server.rack"
        case .quota: "gauge.with.dots.needle.67percent"
        case .thermal: "thermometer.high"
        case .clash: "bolt.horizontal.circle"
        case .pomodoro: "timer"
        case .system: "gearshape.2"
        }
    }
}

enum TimelineSeverity: String, Codable, Sendable {
    case info, healthy, warning, critical

    var color: Color {
        switch self {
        case .info: .secondary
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct TimelineEvent: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var key: String
    var category: TimelineCategory
    var severity: TimelineSeverity
    var title: String
    var evidence: String
    var source: String
    var startedAt: Date
    var recoveredAt: Date?

    var isActive: Bool { recoveredAt == nil && (severity == .warning || severity == .critical) }
    var durationLabel: String {
        let seconds = Int((recoveredAt ?? Date()).timeIntervalSince(startedAt))
        if seconds < 60 { return "\(max(0, seconds)) 秒" }
        if seconds < 3_600 { return "\(seconds / 60) 分钟" }
        return "\(seconds / 3_600) 小时 \((seconds % 3_600) / 60) 分"
    }
}

enum ThermalRiskLevel: String, Sendable {
    case normal, rising, high, critical

    var label: String {
        switch self {
        case .normal: "热状态正常"
        case .rising: "持续升温"
        case .high: "高热风险"
        case .critical: "系统热限制"
        }
    }

    var color: Color {
        switch self {
        case .normal: .green
        case .rising: .yellow
        case .high: .orange
        case .critical: .red
        }
    }
}

struct ThermalRiskSnapshot: Sendable {
    var level: ThermalRiskLevel = .normal
    var trendCelsiusPerMinute = 0.0
    var sustainedHighLoadSeconds = 0
    var evidence = "负载与温度稳定"
    var updatedAt: Date?
}
