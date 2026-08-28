import Foundation

enum MediaKind: String, CaseIterable, Sendable, Codable {
    case ambient
    case music
    case radio

    var label: String {
        switch self {
        case .ambient: "环境音"
        case .music: "工作音乐"
        case .radio: "网络广播"
        }
    }
}

enum MediaPlaybackState: String, Sendable {
    case idle
    case loading
    case playing
    case paused
    case stalled
    case failed
}

enum MediaNetworkMode: String, CaseIterable, Sendable {
    case smart
    case followSystem
    case directOnly

    var label: String {
        switch self {
        case .smart: "智能兼容"
        case .followSystem: "跟随系统"
        case .directOnly: "仅直连"
        }
    }
}

enum MediaRoute: String, Sendable {
    case system
    case smartDirect
    case direct

    var label: String {
        switch self {
        case .system: "系统路由"
        case .smartDirect: "智能直连"
        case .direct: "仅直连"
        }
    }
}

/// A reviewed visual identity for an ambient recording.  This is deliberately
/// explicit catalogue metadata rather than a guess made from a translated
/// title, so a cafe or fireplace recording can never silently fall back to an
/// unrelated generic animation.
enum AmbientSceneStyle: String, Sendable, Codable, CaseIterable, Hashable {
    case rainWindow
    case cityRain
    case thunderstorm
    case openWind
    case forestCanopy
    case oceanShore
    case forestCreek
    case underwater
    case fireplaceClose
    case hearthRoom
    case cafeInterior
    case libraryDesk
    case typingDesk
    case tramWindow
    case trainWindow
    case cityNight
    case nightNature
    case brownNoise

    var label: String {
        switch self {
        case .rainWindow: "窗边雨景"
        case .cityRain: "城市晚雨"
        case .thunderstorm: "远处雷雨"
        case .openWind: "旷野微风"
        case .forestCanopy: "森林树影"
        case .oceanShore: "海岸潮汐"
        case .forestCreek: "林间溪流"
        case .underwater: "水下光影"
        case .fireplaceClose: "近景壁炉"
        case .hearthRoom: "暖炉房间"
        case .cafeInterior: "街角咖啡馆"
        case .libraryDesk: "安静书桌"
        case .typingDesk: "书桌键盘"
        case .tramWindow: "有轨电车"
        case .trainWindow: "列车旅途"
        case .cityNight: "城市夜色"
        case .nightNature: "夜晚虫鸣"
        case .brownNoise: "模拟噪音"
        }
    }
}

enum MediaPlaybackMode: String, CaseIterable, Sendable, Codable {
    case repeatOne
    case listLoop
    case shuffle
    case fixedStation

    var label: String {
        switch self {
        case .repeatOne: "单条循环"
        case .listLoop: "顺序播放"
        case .shuffle: "随机播放"
        // Kept as a persisted raw value for users of earlier builds.  Live
        // radio is still a single stream, and the visible control must use
        // the standard repeat-one convention rather than a misleading pin.
        case .fixedStation: "单条循环"
        }
    }

    var symbol: String {
        switch self {
        case .repeatOne: "repeat.1"
        case .listLoop: "repeat"
        case .shuffle: "shuffle"
        case .fixedStation: "repeat.1"
        }
    }
}

struct MediaStreamItem: Identifiable, Sendable, Equatable, Codable {
    var id: String
    var kind: MediaKind
    var title: String
    var subtitle: String
    var symbol: String
    var streamURL: URL
    var sourcePage: URL
    var provider: String
    var license: String
    var country: String?
    var language: String?
    var codec: String?
    var bitrateKbps: Int?
    var isLive: Bool
}

struct MediaScene: Identifiable, Sendable, Equatable {
    var id: String
    var title: String
    var tag: String
    var symbol: String
    /// A geographic filter belongs to the scene, not to a translated label.
    /// `本地中文` therefore means Mainland China (CN), never merely any
    /// directory record whose language happens to include Chinese.
    var countryCodes: [String] = []
    /// Directory language metadata is often comma-separated and incomplete,
    /// therefore it is verified locally rather than trusted as a remote query.
    var languageTerms: [String] = []

    static let workMusic: [MediaScene] = [
        .init(id: "lofi", title: "Lo-fi", tag: "lofi", symbol: "headphones"),
        .init(id: "ambient", title: "氛围器乐", tag: "ambient", symbol: "sparkles"),
        .init(id: "jazz", title: "轻爵士", tag: "jazz", symbol: "music.note.list"),
        .init(id: "classical", title: "古典专注", tag: "classical", symbol: "pianokeys"),
        .init(id: "piano", title: "钢琴", tag: "piano", symbol: "music.quarternote.3"),
        .init(id: "instrumental", title: "无人声", tag: "instrumental", symbol: "waveform"),
        .init(id: "electronic", title: "电子氛围", tag: "electronic", symbol: "dot.radiowaves.left.and.right"),
        .init(id: "chillout", title: "舒缓 Chill", tag: "chillout", symbol: "cup.and.saucer"),
        .init(id: "soundtrack", title: "原声配乐", tag: "soundtrack", symbol: "film.stack"),
        .init(id: "study", title: "阅读写作", tag: "study", symbol: "book.closed")
    ]

    static let radio: [MediaScene] = [
        .init(id: "news", title: "新闻", tag: "news", symbol: "newspaper"),
        .init(id: "talk", title: "谈话", tag: "talk", symbol: "bubble.left.and.bubble.right"),
        .init(id: "culture", title: "文化", tag: "culture", symbol: "books.vertical"),
        .init(id: "world", title: "世界电台", tag: "international", symbol: "globe.asia.australia"),
        .init(id: "technology", title: "科技", tag: "technology", symbol: "cpu"),
        .init(id: "business", title: "财经", tag: "business", symbol: "chart.line.uptrend.xyaxis"),
        .init(id: "sports", title: "体育", tag: "sports", symbol: "sportscourt"),
        .init(id: "education", title: "语言学习", tag: "education", symbol: "character.book.closed"),
        .init(id: "classical-radio", title: "古典", tag: "classical", symbol: "pianokeys"),
        .init(id: "jazz-radio", title: "爵士", tag: "jazz", symbol: "music.note.list"),
        .init(id: "mainland-chinese", title: "大陆中文", tag: "", symbol: "location.fill", countryCodes: ["CN"], languageTerms: ["chinese", "mandarin", "cantonese", "zh"]),
        .init(id: "greater-china", title: "港澳台中文", tag: "", symbol: "location.circle", countryCodes: ["HK", "MO", "TW"], languageTerms: ["chinese", "mandarin", "cantonese", "zh"]),
        .init(id: "global-chinese", title: "全球中文", tag: "", symbol: "globe.asia.australia", countryCodes: ["CN", "HK", "MO", "TW", "SG", "MY", "US", "CA", "AU", "NZ", "GB"], languageTerms: ["chinese", "mandarin", "cantonese", "zh"])
    ]
}
