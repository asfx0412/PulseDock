import Foundation
import SwiftUI

enum DiagnosticCheckState: String, Sendable {
    case waiting, running, passed, warning, failed

    var symbol: String {
        switch self {
        case .waiting: "circle.dotted"
        case .running: "arrow.triangle.2.circlepath"
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .waiting, .running: .secondary
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        }
    }
}

struct DiagnosticCheck: Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var state: DiagnosticCheckState
    var detail: String
    var latencyMS: Double?
}

enum AIServiceHealth: String, Sendable {
    case idle, checking, healthy, degraded, failed

    var label: String {
        switch self {
        case .idle: "尚未诊断"
        case .checking: "正在诊断"
        case .healthy: "AI 网络正常"
        case .degraded: "AI 路径较慢"
        case .failed: "AI 服务不可用"
        }
    }

    var color: Color {
        switch self {
        case .idle, .checking: .secondary
        case .healthy: .green
        case .degraded: .orange
        case .failed: .red
        }
    }
}

struct NetworkDiagnosticReport: Sendable, Equatable {
    var health: AIServiceHealth
    var summary: String
    var recommendation: String
    var checks: [DiagnosticCheck]
    var completedAt: Date?

    static let idle = NetworkDiagnosticReport(
        health: .idle,
        summary: "点击开始诊断",
        recommendation: "PulseDock 将逐层检查 DNS、代理、TLS、OpenAI 与 Codex。",
        checks: [],
        completedAt: nil
    )
}

struct HTTPSProbeResult: Sendable {
    var reachable: Bool
    var statusCode: Int?
    var latencyMS: Double?
    var errorCode: Int?
    var isTLSError: Bool
    var detail: String
}
