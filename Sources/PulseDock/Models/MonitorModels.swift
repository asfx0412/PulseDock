import Foundation
import SwiftUI

enum ConnectionHealth: String, Sendable {
    case checking, healthy, degraded, offline

    var label: String {
        switch self {
        case .checking: "检测中"
        case .healthy: "网络良好"
        case .degraded: "网络波动"
        case .offline: "网络断开"
        }
    }

    var color: Color {
        switch self {
        case .checking: .secondary
        case .healthy: Color(red: 0.25, green: 0.86, blue: 0.58)
        case .degraded: Color(red: 1.0, green: 0.70, blue: 0.25)
        case .offline: Color(red: 1.0, green: 0.34, blue: 0.39)
        }
    }
}

enum CompactDensity: String, CaseIterable, Sendable {
    case minimal
    case balanced

    var label: String {
        switch self {
        case .minimal: "极简"
        case .balanced: "平衡"
        }
    }
}

enum AppLanguage: String, CaseIterable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"

    var label: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
}

enum FloatingTheme: String, CaseIterable, Codable, Sendable {
    case mist, ocean, lavender, matcha, forest, sunset, sand, midnight, graphite, win97, custom

    var label: String {
        switch self {
        case .mist: "云雾"
        case .ocean: "海盐蓝"
        case .lavender: "薰衣草"
        case .midnight: "午夜蓝"
        case .matcha: "抹茶"
        case .forest: "森林"
        case .sunset: "晚霞"
        case .sand: "暖沙"
        case .graphite: "石墨"
        case .win97: "Win97 复古"
        case .custom: "自定义"
        }
    }

    var background: Color {
        switch self {
        case .mist: Color(red: 0.88, green: 0.93, blue: 0.95)
        case .ocean: Color(red: 0.68, green: 0.84, blue: 0.92)
        case .lavender: Color(red: 0.83, green: 0.79, blue: 0.94)
        case .midnight: Color(red: 0.10, green: 0.16, blue: 0.27)
        case .matcha: Color(red: 0.79, green: 0.88, blue: 0.79)
        case .forest: Color(red: 0.22, green: 0.37, blue: 0.30)
        case .sunset: Color(red: 0.97, green: 0.83, blue: 0.76)
        case .sand: Color(red: 0.92, green: 0.84, blue: 0.70)
        case .graphite: Color(red: 0.22, green: 0.24, blue: 0.29)
        case .win97: Color(red: 0.75, green: 0.75, blue: 0.75)
        case .custom: .clear
        }
    }

    var accent: Color {
        switch self {
        case .mist: Color(red: 0.16, green: 0.45, blue: 0.86)
        case .ocean: Color(red: 0.04, green: 0.42, blue: 0.67)
        case .lavender: Color(red: 0.43, green: 0.30, blue: 0.78)
        case .midnight: Color(red: 0.42, green: 0.72, blue: 1.0)
        case .matcha: Color(red: 0.20, green: 0.50, blue: 0.30)
        case .forest: Color(red: 0.52, green: 0.86, blue: 0.60)
        case .sunset: Color(red: 0.88, green: 0.28, blue: 0.27)
        case .sand: Color(red: 0.62, green: 0.38, blue: 0.11)
        case .graphite: Color(red: 0.76, green: 0.80, blue: 0.88)
        case .win97: Color(red: 0.0, green: 0.0, blue: 0.50)
        case .custom: Color(red: 0.34, green: 0.56, blue: 0.96)
        }
    }

    var description: String {
        switch self {
        case .mist: "清爽的蓝灰工作台，适合白天。"
        case .ocean: "清凉海盐蓝，适合长时间编码。"
        case .lavender: "安静的紫灰色，适合夜间阅读。"
        case .midnight: "低亮度深蓝，适合夜间专注。"
        case .matcha: "柔和低饱和绿，减轻视觉疲劳。"
        case .forest: "沉静的深绿，适合深色桌面。"
        case .sunset: "温暖浅橙，突出下班与专注提醒。"
        case .sand: "低刺激的暖米色，适合白天办公。"
        case .graphite: "克制深灰，适合深色桌面。"
        case .win97: "原创经典桌面：灰色底、蓝色强调与立体边框；不含任何 Windows 资产。"
        case .custom: "使用你选择的背景色。"
        }
    }

    var isDark: Bool { self == .midnight || self == .graphite || self == .forest }
}

enum AppearanceBackgroundPlacement: String, CaseIterable, Codable, Sendable {
    case fill, fit, center
    var label: String { switch self { case .fill: "填充"; case .fit: "适应"; case .center: "居中" } }
}

enum AppearanceFrostStrength: String, CaseIterable, Codable, Sendable {
    case off, light, standard, strong
    var label: String { switch self { case .off: "关闭"; case .light: "轻度"; case .standard: "标准"; case .strong: "强" } }
    var opacity: Double { switch self { case .off: 0; case .light: 0.22; case .standard: 0.48; case .strong: 0.72 } }
}

/// Stored separately from transient panel state so background asset references
/// stay stable across launches while the original 6.14 color preferences can
/// migrate without losing the user's current appearance.
struct AppearanceProfile: Codable, Sendable, Equatable {
    var theme: FloatingTheme = .mist
    var expandedBackgroundAssetID: String?
    var compactBackgroundAssetID: String?
    var compactFollowsExpanded = true
    var placement: AppearanceBackgroundPlacement = .fill
    var dimming: Double = 0.15
    var frost: AppearanceFrostStrength = .standard
    var cardOpacity: Double = 0.045
    var borderStrength: Double = 0.26
    var automaticTextContrast = true

    static let `default` = AppearanceProfile()
}

enum CompactPriorityKind: Sendable {
    case network, remote, thermal, quota, clash, pomodoro, work
}

struct CompactPriority: Sendable {
    var kind: CompactPriorityKind
    var title: String
    var detail: String
    var symbol: String
    var color: Color
}

enum DataFreshness {
    static func label(_ updatedAt: Date?, now: Date = Date()) -> String {
        guard let updatedAt else { return "尚未更新" }
        let seconds = max(0, now.timeIntervalSince(updatedAt))
        if seconds < 60 { return "刚刚更新" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) 分钟前更新" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) 小时前更新" }
        return "\(Int(seconds / 86_400)) 天前更新"
    }
}

struct IPIdentity: Codable, Equatable, Sendable {
    var address = "--"
    var country = "未知"
    var countryCode = ""
    var region = ""
    var city = ""
    var isp = ""
    var timezone = ""

    var isMainlandChina: Bool { countryCode.uppercased() == "CN" }
    var scopeLabel: String {
        guard !countryCode.isEmpty else { return "定位中" }
        return isMainlandChina ? "中国大陆" : "境外出口"
    }
    var locationLine: String {
        let parts = [country, region, city].filter { !$0.isEmpty }
        return parts.isEmpty ? "未知位置" : parts.joined(separator: " · ")
    }
    var localizedCountry: String {
        guard !countryCode.isEmpty else { return country.isEmpty ? "未知国家" : country }
        return Locale(identifier: "zh_Hans_CN").localizedString(forRegionCode: countryCode.uppercased()) ?? country
    }
    var locationHeadline: String {
        let parts = [localizedCountry, city].filter { !$0.isEmpty && $0 != "未知国家" }
        return parts.isEmpty ? "出口位置未知" : parts.joined(separator: " · ")
    }
    var addressFamilyLabel: String {
        address.contains(":") ? "IPv6" : (address.contains(".") ? "IPv4" : "地址未知")
    }
}

struct DiagnosticEvent: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let title: String
    let detail: String
    let severity: ConnectionHealth
}

struct SpeedSample: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let download: Double
    let upload: Double
}

enum DisplayFormat {
    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return "0 KB/s" }
        if bytesPerSecond >= 1_000_000_000 { return String(format: "%.1f GB/s", bytesPerSecond / 1_000_000_000) }
        if bytesPerSecond >= 1_000_000 { return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) }
        return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", max(0, min(100, value)))
    }
}
