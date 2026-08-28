import AVFoundation
import Foundation

struct AmbientTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let streamURL: URL
    let sourcePage: URL
    let author: String
    let license: String
    /// Canonical license deed for audit/export. The source page remains the
    /// authority for the license attached to an individual recording.
    let licenseURL: URL
    /// Stable provider-qualified identifier; never inferred from a title.
    let sourceID: String
    /// Curated discovery tags. One recording may intentionally appear in more
    /// than one category (for example rain + city + night).
    let tags: Set<String>
    /// Reviewed visual treatment used by the lightweight scene renderer.
    /// Never inferred from the title, localisation or SF Symbol.
    let sceneStyle: AmbientSceneStyle
    let duration: TimeInterval
    /// ISO-8601 calendar date on which source page, license and preview URL were
    /// last checked. Kept as a string so catalogue tests are timezone-neutral.
    let lastVerified: String

    var mediaItem: MediaStreamItem {
        MediaStreamItem(
            id: id, kind: .ambient, title: title, subtitle: subtitle, symbol: symbol,
            streamURL: streamURL, sourcePage: sourcePage, provider: author,
            license: license, country: nil, language: nil, codec: "MP3",
            bitrateKbps: nil, isLive: false
        )
    }

    private static let cc0URL = URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!
    private static let verificationDate = "2026-08-25"

    private static func freesound(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        soundID: Int,
        previewPath: String,
        author: String,
        tags: Set<String>,
        sceneStyle: AmbientSceneStyle,
        duration: TimeInterval
    ) -> AmbientTrack {
        AmbientTrack(
            id: id,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            streamURL: URL(string: "https://cdn.freesound.org/previews/\(soundID / 1000)/\(previewPath)-hq.mp3")!,
            sourcePage: URL(string: "https://freesound.org/s/\(soundID)/")!,
            author: author,
            license: "CC0",
            licenseURL: cc0URL,
            sourceID: "freesound:\(soundID)",
            tags: tags,
            sceneStyle: sceneStyle,
            duration: duration,
            lastVerified: verificationDate
        )
    }

    /// A deliberately small, reviewable catalogue of distinct recordings.
    /// These are remote Freesound previews, not bundled or downloaded assets.
    static let catalog: [AmbientTrack] = [
        freesound(id: "rain-window", title: "窗边雨声", subtitle: "真实雨滴与室内混响", symbol: "cloud.rain.fill", soundID: 81818, previewPath: "81818_280284", author: "silencyo", tags: ["rain", "indoor", "focus"], sceneStyle: .rainWindow, duration: 81.8347),
        freesound(id: "wind", title: "旷野微风", subtitle: "自然风声，起伏柔和", symbol: "wind", soundID: 217506, previewPath: "217506_1661766", author: "felix.blume", tags: ["wind", "nature", "focus"], sceneStyle: .openWind, duration: 212.318),
        freesound(id: "leaves", title: "林间树叶", subtitle: "树叶摩擦与轻风", symbol: "leaf.fill", soundID: 457318, previewPath: "457318_9065275", author: "Stek59", tags: ["forest", "leaves", "wind", "nature"], sceneStyle: .forestCanopy, duration: 42.9135),
        freesound(id: "thunder", title: "远处雷雨", subtitle: "低频雷声与自然雨幕", symbol: "cloud.bolt.rain.fill", soundID: 316831, previewPath: "316831_2609215", author: "Boryslaw_Kozielski", tags: ["rain", "thunder", "night", "nature"], sceneStyle: .thunderstorm, duration: 187.155),
        freesound(id: "underwater", title: "水下空间", subtitle: "安静、深沉的水域声场", symbol: "water.waves", soundID: 482167, previewPath: "482167_4838691", author: "Tim_Verberne", tags: ["water", "underwater", "focus"], sceneStyle: .underwater, duration: 120),
        freesound(id: "brown-noise", title: "棕色噪音", subtitle: "低频均匀背景，音量宜低", symbol: "waveform", soundID: 171552, previewPath: "171552_3195672", author: "georgedyer", tags: ["noise", "focus", "indoor"], sceneStyle: .brownNoise, duration: 3600.05),

        freesound(id: "ocean-waves", title: "禅意海浪", subtitle: "有节奏的海浪拍岸", symbol: "water.waves", soundID: 456899, previewPath: "456899_9518146", author: "INNORECORDS", tags: ["water", "ocean", "waves", "nature", "focus"], sceneStyle: .oceanShore, duration: 95.779),
        freesound(id: "cafe-room", title: "街角咖啡馆", subtitle: "室内人声与轻柔空间底噪", symbol: "cup.and.saucer.fill", soundID: 706805, previewPath: "706805_13871294", author: "Vecera_999", tags: ["cafe", "indoor", "city", "people"], sceneStyle: .cafeInterior, duration: 192),
        freesound(id: "fireplace", title: "壁炉柴火", subtitle: "近距离木柴燃烧与爆裂声", symbol: "flame.fill", soundID: 263864, previewPath: "263864_4457609", author: "ceich93", tags: ["fire", "indoor", "night", "focus"], sceneStyle: .fireplaceClose, duration: 59.9607),
        freesound(id: "hearth-fire", title: "温暖炉火", subtitle: "平稳的壁炉噼啪声", symbol: "flame.circle.fill", soundID: 414767, previewPath: "414767_4955305", author: "samarobryn", tags: ["fire", "indoor", "night", "focus"], sceneStyle: .hearthRoom, duration: 60),
        freesound(id: "winter-birds", title: "冬日林鸟", subtitle: "可循环的森林鸟鸣", symbol: "bird.fill", soundID: 723913, previewPath: "723913_2008500", author: "Magnesus", tags: ["forest", "birds", "nature", "morning"], sceneStyle: .forestCanopy, duration: 27.0517),
        freesound(id: "forest-creek", title: "林间溪流", subtitle: "溪水、森林与远处鸟声", symbol: "drop.fill", soundID: 693851, previewPath: "693851_12869299", author: "bumbdoident", tags: ["water", "creek", "forest", "birds", "nature"], sceneStyle: .forestCreek, duration: 168.5),
        freesound(id: "tram-interior", title: "有轨电车车厢", subtitle: "行驶声与远处乘客交谈", symbol: "tram.fill", soundID: 580641, previewPath: "580641_4688703", author: "The_Runner_01", tags: ["transport", "train", "indoor", "people", "city"], sceneStyle: .tramWindow, duration: 390.838),
        freesound(id: "library-room", title: "安静图书馆", subtitle: "低声室内活动与空间氛围", symbol: "books.vertical.fill", soundID: 408514, previewPath: "408514_7117779", author: "PasekaM", tags: ["library", "indoor", "focus", "people"], sceneStyle: .libraryDesk, duration: 152),
        freesound(id: "city-night", title: "城市夜色", subtitle: "安静街道与远处车辆", symbol: "building.2.fill", soundID: 237329, previewPath: "237329_3435865", author: "Soundkrampf", tags: ["city", "night", "traffic", "outdoor"], sceneStyle: .cityNight, duration: 67.7168),
        freesound(id: "summer-crickets", title: "夏夜虫鸣", subtitle: "公园里的连续蟋蟀声", symbol: "moon.stars.fill", soundID: 436528, previewPath: "436528_8938826", author: "KikeVilaplana", tags: ["insects", "crickets", "night", "nature"], sceneStyle: .nightNature, duration: 51.0667),
        freesound(id: "typing-room", title: "书桌键盘", subtitle: "轻柔打字与点击声", symbol: "keyboard.fill", soundID: 851269, previewPath: "851269_16102858", author: "Sayaka04", tags: ["typing", "keyboard", "indoor", "focus"], sceneStyle: .typingDesk, duration: 135.321),
        freesound(id: "swedish-forest", title: "瑞典森林清晨", subtitle: "长段森林鸟鸣、昆虫与微风", symbol: "tree.fill", soundID: 488328, previewPath: "488328_8972317", author: "priesjensen", tags: ["forest", "birds", "insects", "wind", "nature", "morning"], sceneStyle: .forestCanopy, duration: 365.987),
        freesound(id: "train-interior", title: "列车行进", subtitle: "稳定的车厢与轨道背景", symbol: "train.side.front.car", soundID: 143205, previewPath: "143205_2051926", author: "bisanu6", tags: ["transport", "train", "indoor", "focus"], sceneStyle: .trainWindow, duration: 86.496),
        freesound(id: "cafe-espresso", title: "咖啡店早餐", subtitle: "交谈、餐具与咖啡机声", symbol: "cup.and.saucer.fill", soundID: 332271, previewPath: "332271_2367065", author: "evsecrets", tags: ["cafe", "indoor", "city", "people"], sceneStyle: .cafeInterior, duration: 150.584),
        freesound(id: "shore-waves", title: "海岸浪花", subtitle: "开阔海岸的自然浪声", symbol: "beach.umbrella.fill", soundID: 531015, previewPath: "531015_9818404", author: "Noted451", tags: ["water", "ocean", "waves", "nature"], sceneStyle: .oceanShore, duration: 70.8847),
        freesound(id: "country-crickets", title: "乡间夜虫", subtitle: "农舍花园里的蟋蟀声", symbol: "moon.haze.fill", soundID: 645863, previewPath: "645863_5902878", author: "BonnyOrbit", tags: ["insects", "crickets", "night", "nature", "countryside"], sceneStyle: .nightNature, duration: 97.3556),
        freesound(id: "quiet-night-city", title: "静谧城市夜晚", subtitle: "均匀而低调的城市空气声", symbol: "building.2.crop.circle", soundID: 427841, previewPath: "427841_4437257", author: "leonelmail", tags: ["city", "night", "noise", "focus"], sceneStyle: .cityNight, duration: 139.456),
        freesound(id: "city-rain", title: "城市晚雨", subtitle: "雨幕、车辆与街道回声", symbol: "cloud.rain.fill", soundID: 607228, previewPath: "607228_11069322", author: "RyanKingArt", tags: ["rain", "city", "night", "traffic"], sceneStyle: .cityRain, duration: 98.6151)
    ]

    struct Category: Identifiable, Equatable {
        let id: String
        let title: String
        let symbol: String
        let trackIDs: Set<String>
    }

    private static func ids(tag: String) -> Set<String> {
        Set(catalog.lazy.filter { $0.tags.contains(tag) }.map(\.id))
    }

    static let categories: [Category] = [
        .init(id: "rain", title: "雨声", symbol: "cloud.rain", trackIDs: ids(tag: "rain")),
        .init(id: "water", title: "海浪与溪流", symbol: "water.waves", trackIDs: ids(tag: "water")),
        .init(id: "forest", title: "森林与鸟鸣", symbol: "leaf", trackIDs: ids(tag: "forest")),
        .init(id: "night", title: "夜晚声景", symbol: "moon.stars", trackIDs: ids(tag: "night")),
        .init(id: "fire", title: "壁炉", symbol: "flame", trackIDs: ids(tag: "fire")),
        .init(id: "cafe", title: "咖啡馆", symbol: "cup.and.saucer", trackIDs: ids(tag: "cafe")),
        .init(id: "focus", title: "阅读专注", symbol: "text.book.closed", trackIDs: ids(tag: "focus")),
        .init(id: "transport", title: "列车旅途", symbol: "tram", trackIDs: ids(tag: "transport")),
        .init(id: "city", title: "城市空间", symbol: "building.2", trackIDs: ids(tag: "city"))
    ]

    static func sceneStyle(for mediaID: String) -> AmbientSceneStyle? {
        catalog.first(where: { $0.id == mediaID })?.sceneStyle
    }
}

/// Coordinates ambient recordings, work-music streams and Internet radio with
/// one AVPlayer. It never auto-plays, restores a prior stream or creates an
/// offline audio library. macOS may still keep a transient playback buffer.
@MainActor
final class AmbientSoundService: ObservableObject {
    /// The visible catalogue is independent from the currently playing stream.
    /// Otherwise changing tabs while a radio plays can make controls mutate the
    /// ambient mode, which is both confusing and incorrect.
    @Published var browserKind: MediaKind = .ambient
    @Published private(set) var selectedKind: MediaKind = .ambient
    @Published private(set) var selectedItem: MediaStreamItem?
    @Published private(set) var selectedTrackID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackState: MediaPlaybackState = .idle
    @Published private(set) var status = "未播放 · 默认静音"
    @Published private(set) var stopAt: Date?
    @Published private(set) var directoryItems: [MediaStreamItem] = []
    @Published private(set) var directoryLoading = false
    @Published private(set) var directoryStatus = "选择场景或搜索公开网络目录"
    @Published private(set) var directorySourceSummary = "来源：Radio Browser 公共目录"
    @Published private(set) var favoriteIDs: Set<String>
    @Published private(set) var favoriteItems: [MediaStreamItem]
    @Published var musicSearchQuery = ""
    @Published var radioSearchQuery = ""
    @Published private(set) var musicPage = 0
    @Published private(set) var radioPage = 0
    @Published private(set) var musicHasMoreCandidates = false
    @Published private(set) var radioHasMoreCandidates = false
    @Published private(set) var currentRoute: MediaRoute = .system
    @Published var networkMode: MediaNetworkMode {
        didSet { UserDefaults.standard.set(networkMode.rawValue, forKey: networkModeDefaultsKey) }
    }
    @Published var ambientPlaybackMode: MediaPlaybackMode = .repeatOne { didSet { persistPlaybackModes() } }
    @Published var musicPlaybackMode: MediaPlaybackMode = .listLoop { didSet { persistPlaybackModes() } }
    @Published var radioPlaybackMode: MediaPlaybackMode = .fixedStation { didSet { persistPlaybackModes() } }
    @Published var volume: Double = 0.32 {
        didSet {
            let normalized = min(0.8, max(0, volume))
            if normalized != volume { volume = normalized; return }
            if normalized > 0.01 { lastAudibleVolume = normalized }
            player?.volume = Float(normalized)
        }
    }

    let tracks = AmbientTrack.catalog
    let ambientCategories = AmbientTrack.categories
    let musicScenes = MediaScene.workMusic
    let radioScenes = MediaScene.radio

    private let directory = InternetRadioDirectoryService()
    private let directRelay = DirectAudioRelay()
    private let preflight = AudioStreamPreflightService()
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var timerTask: Task<Void, Never>?
    private var directoryTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var preflightTask: Task<Void, Never>?
    private var musicTag: String?
    private var radioTag: String?
    private var musicCountryCodes: [String] = []
    private var radioCountryCodes: [String] = []
    private var musicLanguageTerms: [String] = []
    private var radioLanguageTerms: [String] = []
    private var systemRouteFailure: String?
    private var failureCooldowns: [String: (until: Date, detail: String)] = [:]
    private var successfulSources: [String: Date] = [:]
    private var playbackGeneration = 0
    private var lastAudibleVolume = 0.32
    private let favoriteDefaultsKey = "PulseDock.mediaFavoriteIDs"
    private let favoriteItemsDefaultsKey = "PulseDock.mediaFavoriteItems"
    private let networkModeDefaultsKey = "PulseDock.mediaNetworkMode"
    // Directory endpoints are queried in larger batches so that filtering out
    // unsafe/incompatible streams does not make a six-card page look empty.
    // The view intentionally renders only six items at a time.
    // Fetch a reasonably broad metadata slice, then render only six cards.
    // A strict region + language scene should not look empty merely because
    // the first 30 directory records use another stream format.
    private let directoryRequestSize = 120

    init() {
        let loadedIDs = Set(UserDefaults.standard.stringArray(forKey: "PulseDock.mediaFavoriteIDs") ?? [])
        let loadedItems = UserDefaults.standard.data(forKey: "PulseDock.mediaFavoriteItems")
            .flatMap { try? JSONDecoder().decode([MediaStreamItem].self, from: $0) } ?? []
        favoriteIDs = loadedIDs
        favoriteItems = loadedItems.filter { loadedIDs.contains($0.id) }
        networkMode = MediaNetworkMode(rawValue: UserDefaults.standard.string(forKey: "PulseDock.mediaNetworkMode") ?? "") ?? .smart
        ambientPlaybackMode = MediaPlaybackMode(rawValue: UserDefaults.standard.string(forKey: "PulseDock.ambientPlaybackMode") ?? "") ?? .repeatOne
        musicPlaybackMode = MediaPlaybackMode(rawValue: UserDefaults.standard.string(forKey: "PulseDock.musicPlaybackMode") ?? "") ?? .listLoop
        radioPlaybackMode = MediaPlaybackMode(rawValue: UserDefaults.standard.string(forKey: "PulseDock.radioPlaybackMode") ?? "") ?? .fixedStation
    }

    func items(for kind: MediaKind) -> [MediaStreamItem] {
        guard kind != .ambient else { return tracks.map(\.mediaItem) }
        let now = Date()
        return directoryItems.filter { $0.kind == kind }.sorted { lhs, rhs in
            let leftSuccess = successfulSources[lhs.id] ?? .distantPast
            let rightSuccess = successfulSources[rhs.id] ?? .distantPast
            if leftSuccess != rightSuccess { return leftSuccess > rightSuccess }
            let leftCooling = (failureCooldowns[lhs.id]?.until ?? .distantPast) > now
            let rightCooling = (failureCooldowns[rhs.id]?.until ?? .distantPast) > now
            if leftCooling != rightCooling { return !leftCooling }
            return false
        }
    }

    func sourceAvailabilityNote(_ item: MediaStreamItem) -> String? {
        guard let failure = failureCooldowns[item.id], failure.until > Date() else { return nil }
        return "当前网络冷却中 · \(failure.detail)"
    }

    func toggle(_ track: AmbientTrack) { toggle(track.mediaItem) }

    func toggle(_ item: MediaStreamItem) {
        if selectedItem?.id == item.id, isPlaying { pause(); return }
        if selectedItem?.id == item.id, playbackState == .paused { resume(); return }
        play(item)
    }

    func play(_ item: MediaStreamItem) {
        guard item.streamURL.scheme?.lowercased() == "https" else {
            playbackState = .failed
            status = "已阻止不安全的 HTTP 音源"
            return
        }
        clearPlayer()
        playbackGeneration += 1
        let generation = playbackGeneration
        selectedItem = item
        selectedTrackID = item.id
        selectedKind = item.kind
        playbackState = .loading
        isPlaying = false
        status = "正在检查音频首包 · \(networkMode == .directOnly ? "仅直连" : "系统路由")"
        preflightTask = Task { [weak self] in
            guard let self else { return }
            let direct = self.networkMode == .directOnly
            let result = await self.preflight.inspect(item.streamURL, direct: direct)
            guard !Task.isCancelled, generation == self.playbackGeneration else { return }
            if result.reachable {
                self.status = "\(result.detail) · 正在交给播放器"
                if direct {
                    await self.startDirectPlayback(item, generation: generation, route: .direct)
                } else {
                    self.configurePlayer(item, url: item.streamURL, generation: generation, route: .system)
                    if self.networkMode == .smart { self.scheduleSmartFallback(item, generation: generation) }
                }
            } else if self.networkMode == .smart && !direct {
                self.systemRouteFailure = "\(result.kind?.rawValue ?? "预检失败")：\(result.detail)"
                self.status = "系统路由首包失败，正在尝试智能直连…"
                await self.startDirectPlayback(item, generation: generation, route: .smartDirect)
            } else {
                self.markFailure(item, kind: result.kind ?? .unknown, detail: result.detail)
            }
        }
    }

    private func configurePlayer(_ item: MediaStreamItem, url: URL, generation: Int, route: MediaRoute) {
        guard generation == playbackGeneration else { return }
        clearPlayerObjects()
        currentRoute = route
        if route == .system { systemRouteFailure = nil }
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.volume = Float(volume)
        player = newPlayer
        isPlaying = false
        playbackState = .loading
        status = "正在缓冲 \(item.title)… · \(route.label)"

        itemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self, weak playerItem] _, _ in
            Task { @MainActor in
                guard let self, generation == self.playbackGeneration, let playerItem else { return }
                switch playerItem.status {
                case .readyToPlay:
                    if self.player?.timeControlStatus == .playing {
                        self.isPlaying = true
                        self.playbackState = .playing
                        self.status = "正在播放 \(item.title) · \(self.currentRoute.label)"
                    }
                case .failed:
                    self.isPlaying = false
                    self.playbackState = .failed
                    let reason = String((playerItem.error?.localizedDescription ?? "音源暂时不可用").prefix(160))
                    if route == .system {
                        self.systemRouteFailure = reason
                        self.status = self.networkMode == .smart ? "系统路由失败：\(reason) · 将尝试智能直连" : "系统路由播放失败：\(reason)"
                        if self.networkMode != .smart {
                            self.markFailure(item, kind: Self.failureKind(from: playerItem.error), detail: reason)
                        }
                    } else {
                        self.status = self.combinedPlaybackFailure(reason, route: route)
                        self.markFailure(item, kind: Self.failureKind(from: playerItem.error), detail: reason)
                    }
                case .unknown:
                    self.playbackState = .loading
                @unknown default:
                    self.playbackState = .failed
                    self.status = "播放器返回了未知状态"
                }
            }
        }
        timeControlObserver = newPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, generation == self.playbackGeneration else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.fallbackTask?.cancel()
                    self.fallbackTask = nil
                    self.isPlaying = true
                    self.playbackState = .playing
                    self.status = "正在播放 \(item.title) · \(item.isLive ? "网络直播" : "网络流") · \(self.currentRoute.label)"
                    self.successfulSources[item.id] = Date()
                    self.failureCooldowns.removeValue(forKey: item.id)
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                    self.playbackState = .stalled
                    self.status = "网络缓冲中 · \(item.title)"
                case .paused:
                    if self.playbackState != .failed && self.playbackState != .loading {
                        self.isPlaying = false
                        self.playbackState = .paused
                    }
                @unknown default: break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, generation == self.playbackGeneration else { return }
                if item.kind == .ambient {
                    if self.mode(for: item.kind) == .repeatOne {
                        self.player?.seek(to: .zero)
                        self.player?.play()
                    } else { self.next() }
                } else if item.kind == .music {
                    if self.mode(for: item.kind) == .fixedStation { self.play(item) }
                    else { self.next() }
                } else {
                    if self.mode(for: item.kind) == .fixedStation { self.play(item) }
                    else if self.mode(for: item.kind) == .listLoop || self.mode(for: item.kind) == .shuffle { self.next() }
                    else {
                        self.isPlaying = false
                        self.playbackState = .failed
                        self.status = "广播流已结束，可重新连接"
                    }
                }
            }
        }
        newPlayer.play()
    }

    private func scheduleSmartFallback(_ item: MediaStreamItem, generation: Int) {
        fallbackTask?.cancel()
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled, let self, generation == self.playbackGeneration,
                  !self.isPlaying, self.networkMode == .smart else { return }
            await self.startDirectPlayback(item, generation: generation, route: .smartDirect)
        }
    }

    private func startDirectPlayback(_ item: MediaStreamItem, generation: Int, route: MediaRoute) async {
        guard generation == playbackGeneration else { return }
        let codec = item.codec?.uppercased() ?? ""
        guard !codec.contains("HLS"), !item.streamURL.path.lowercased().hasSuffix(".m3u8") else {
            markFailure(item, kind: .unsupported, detail: "该 HLS 音源暂不支持智能直连，请换用同台 MP3/AAC 音源")
            return
        }
        playbackState = .loading
        isPlaying = false
        status = route == .smartDirect ? "系统路由缓冲超时，正在尝试智能直连…" : "正在建立仅限本次播放的直连…"
        do {
            let localURL = try await directRelay.start(upstream: item.streamURL)
            guard generation == playbackGeneration else { directRelay.stop(); return }
            configurePlayer(item, url: localURL, generation: generation, route: route)
        } catch {
            guard generation == playbackGeneration else { return }
            let reason = String(error.localizedDescription.prefix(180))
            markFailure(item, kind: Self.failureKind(from: error), detail: combinedPlaybackFailure(reason, route: route))
        }
    }

    private func markFailure(_ item: MediaStreamItem, kind: AudioPlaybackFailureKind, detail: String) {
        let concise = String(detail.prefix(140))
        failureCooldowns[item.id] = (Date().addingTimeInterval(5 * 60), "\(kind.rawValue)：\(concise)")
        playbackState = .failed
        isPlaying = false
        status = "播放失败 · \(kind.rawValue) · \(concise) · 该来源冷却 5 分钟"
    }

    private nonisolated static func failureKind(from error: Error?) -> AudioPlaybackFailureKind {
        AudioStreamPreflightService.classify(error as? URLError)
    }

    private func combinedPlaybackFailure(_ reason: String, route: MediaRoute) -> String {
        if route == .smartDirect, let systemRouteFailure {
            return "播放失败：系统路由（\(systemRouteFailure)）；智能直连（\(reason)）"
        }
        return "播放失败（\(route.label)）：\(reason)"
    }

    func pause() {
        fallbackTask?.cancel()
        fallbackTask = nil
        player?.pause()
        isPlaying = false
        playbackState = selectedItem == nil ? .idle : .paused
        status = selectedItem == nil ? "未播放 · 默认静音" : "已暂停"
    }

    func toggleMute() {
        if volume <= 0.01 {
            volume = max(0.08, lastAudibleVolume)
        } else {
            lastAudibleVolume = volume
            volume = 0
        }
    }

    func resume() {
        guard player != nil else { return }
        playbackState = .loading
        status = "正在恢复网络播放…"
        player?.play()
        if networkMode == .smart, currentRoute == .system, let selectedItem {
            scheduleSmartFallback(selectedItem, generation: playbackGeneration)
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        stopAt = nil
        clearPlayer()
        selectedItem = nil
        selectedTrackID = nil
        isPlaying = false
        playbackState = .idle
        status = "已停止 · 未建立离线音频库"
    }

    func next() { step(by: 1) }
    func previous() { step(by: -1) }

    private func step(by offset: Int) {
        let queueKind = selectedItem?.kind ?? browserKind
        let catalog = items(for: queueKind)
        guard !catalog.isEmpty else { return }
        let current = selectedItem.flatMap { item in catalog.firstIndex(where: { $0.id == item.id }) } ?? (offset > 0 ? -1 : 0)
        let next: Int
        if mode(for: queueKind) == .shuffle, catalog.count > 1 {
            var candidate = Int.random(in: catalog.indices)
            if candidate == current { candidate = (candidate + 1) % catalog.count }
            next = candidate
        } else {
            next = (current + offset + catalog.count) % catalog.count
        }
        play(catalog[next])
    }

    func toggleFavorite(_ item: MediaStreamItem) {
        if favoriteIDs.contains(item.id) {
            favoriteIDs.remove(item.id)
            favoriteItems.removeAll { $0.id == item.id }
        } else {
            favoriteIDs.insert(item.id)
            favoriteItems.removeAll { $0.id == item.id }
            favoriteItems.append(item)
        }
        UserDefaults.standard.set(Array(favoriteIDs).sorted(), forKey: favoriteDefaultsKey)
        if let data = try? JSONEncoder().encode(favoriteItems) { UserDefaults.standard.set(data, forKey: favoriteItemsDefaultsKey) }
    }

    func mode(for kind: MediaKind) -> MediaPlaybackMode {
        switch kind {
        case .ambient: ambientPlaybackMode
        case .music: musicPlaybackMode
        case .radio: radioPlaybackMode
        }
    }

    func setMode(_ mode: MediaPlaybackMode, for kind: MediaKind) {
        switch kind {
        case .ambient: ambientPlaybackMode = mode
        case .music: musicPlaybackMode = mode
        case .radio: radioPlaybackMode = mode
        }
    }

    func cycleMode(for kind: MediaKind) {
        let choices = availableModes(for: kind)
        guard let index = choices.firstIndex(of: mode(for: kind)) else {
            if let first = choices.first { setMode(first, for: kind) }
            return
        }
        setMode(choices[(index + 1) % choices.count], for: kind)
    }

    func availableModes(for kind: MediaKind) -> [MediaPlaybackMode] {
        switch kind {
        case .ambient: [.repeatOne, .listLoop, .shuffle]
        case .music: [.fixedStation, .listLoop, .shuffle]
        case .radio: [.fixedStation, .listLoop, .shuffle]
        }
    }

    private func persistPlaybackModes() {
        UserDefaults.standard.set(ambientPlaybackMode.rawValue, forKey: "PulseDock.ambientPlaybackMode")
        UserDefaults.standard.set(musicPlaybackMode.rawValue, forKey: "PulseDock.musicPlaybackMode")
        UserDefaults.standard.set(radioPlaybackMode.rawValue, forKey: "PulseDock.radioPlaybackMode")
    }

    func load(scene: MediaScene, for kind: MediaKind) {
        setPage(0, for: kind)
        setQuery("", for: kind)
        setTag(scene.tag, for: kind)
        setCountryCodes(scene.countryCodes, for: kind)
        setLanguageTerms(scene.languageTerms, for: kind)
        fetch(kind: kind, query: "", tag: scene.tag, countryCodes: scene.countryCodes, languageTerms: scene.languageTerms, page: 0)
    }

    func search(kind: MediaKind) {
        setPage(0, for: kind)
        setTag(nil, for: kind)
        setCountryCodes([], for: kind)
        setLanguageTerms([], for: kind)
        fetch(kind: kind, query: query(for: kind), tag: nil, countryCodes: [], languageTerms: [], page: 0)
    }

    func query(for kind: MediaKind) -> String { kind == .music ? musicSearchQuery : radioSearchQuery }

    func setQuery(_ value: String, for kind: MediaKind) {
        if kind == .music { musicSearchQuery = value } else if kind == .radio { radioSearchQuery = value }
    }

    func page(for kind: MediaKind) -> Int { kind == .music ? musicPage : radioPage }

    func canGoForward(for kind: MediaKind) -> Bool {
        kind == .music ? musicHasMoreCandidates : radioHasMoreCandidates
    }

    func changePage(by offset: Int, kind: MediaKind) {
        let target = max(0, page(for: kind) + offset)
        guard target != page(for: kind) else { return }
        setPage(target, for: kind)
        fetch(kind: kind, query: query(for: kind), tag: tag(for: kind), countryCodes: countryCodes(for: kind), languageTerms: languageTerms(for: kind), page: target)
    }

    func goToPage(_ page: Int, kind: MediaKind) {
        let target = max(0, page)
        guard target != self.page(for: kind) else { return }
        setPage(target, for: kind)
        fetch(kind: kind, query: query(for: kind), tag: tag(for: kind), countryCodes: countryCodes(for: kind), languageTerms: languageTerms(for: kind), page: target)
    }

    private func setPage(_ value: Int, for kind: MediaKind) {
        if kind == .music { musicPage = value } else if kind == .radio { radioPage = value }
    }

    private func tag(for kind: MediaKind) -> String? { kind == .music ? musicTag : radioTag }

    private func setTag(_ value: String?, for kind: MediaKind) {
        if kind == .music { musicTag = value } else if kind == .radio { radioTag = value }
    }

    private func countryCodes(for kind: MediaKind) -> [String] { kind == .music ? musicCountryCodes : radioCountryCodes }
    private func setCountryCodes(_ value: [String], for kind: MediaKind) {
        if kind == .music { musicCountryCodes = value } else if kind == .radio { radioCountryCodes = value }
    }
    private func languageTerms(for kind: MediaKind) -> [String] { kind == .music ? musicLanguageTerms : radioLanguageTerms }
    private func setLanguageTerms(_ value: [String], for kind: MediaKind) {
        if kind == .music { musicLanguageTerms = value } else if kind == .radio { radioLanguageTerms = value }
    }

    private func fetch(kind: MediaKind, query: String, tag: String?, countryCodes: [String], languageTerms: [String], page: Int) {
        guard kind != .ambient else { return }
        directoryTask?.cancel()
        directoryLoading = true
        directoryStatus = "正在读取第三方公开目录…"
        directoryTask = Task { [weak self] in
            guard let self else { return }
            do {
                // A visible page needs six safe cards.  Directory records can
                // be discarded after HTTPS/codec/content verification, so a
                // sparse first raw batch is not a valid end-of-results signal.
                // Read two bounded follow-up batches before reporting a truly
                // small regional catalogue to the user.
                let initialOffset = page * 6
                var result = try await directory.searchPage(kind: kind, query: query, tag: tag, countryCodes: countryCodes, languageTerms: languageTerms, limit: directoryRequestSize, offset: initialOffset)
                var values = result.items
                var seen = Set(values.map(\.id))
                var nextOffset = initialOffset + directoryRequestSize
                var extraBatches = 0
                while values.count < 6 && result.hasMoreCandidates && extraBatches < 2 {
                    try Task.checkCancellation()
                    result = try await directory.searchPage(kind: kind, query: query, tag: tag, countryCodes: countryCodes, languageTerms: languageTerms, limit: directoryRequestSize, offset: nextOffset)
                    for item in result.items where seen.insert(item.id).inserted { values.append(item) }
                    nextOffset += directoryRequestSize
                    extraBatches += 1
                }
                // Previously audited favourites are a safe local supplement
                // when the public directory temporarily omits the same
                // regional station. No unknown stream is invented here.
                let localSupplement = favoriteItems.filter {
                    $0.kind == kind && Self.matchesScene($0, countryCodes: countryCodes, languageTerms: languageTerms)
                }
                for item in localSupplement where seen.insert(item.id).inserted { values.append(item) }
                guard !Task.isCancelled else { return }
                directoryItems.removeAll { $0.kind == kind }
                directoryItems.append(contentsOf: values)
                if kind == .music { musicHasMoreCandidates = result.hasMoreCandidates }
                else { radioHasMoreCandidates = result.hasMoreCandidates }
                directoryLoading = false
                let providerNames = Set(values.map(\.provider)).sorted()
                let localCount = localSupplement.filter { item in values.contains(where: { $0.id == item.id }) }.count
                directorySourceSummary = "来源：\(providerNames.isEmpty ? "Radio Browser" : providerNames.joined(separator: "、")) · 中文语言补充索引\(localCount > 0 ? " · 本机收藏补充 \(localCount) 条" : "")"
                directoryStatus = values.isEmpty
                    ? (kind == .music ? "没有找到符合工作音乐语义的结果 · 已排除 FM/谈话电台" : "没有找到结果 · 可尝试台名、城市或其他分类")
                    : "第 \(page + 1) 页 · 已筛出 \(values.count) 个安全 HTTPS 音源 · 点击后才连接音频"
            } catch {
                guard !Task.isCancelled else { return }
                directoryLoading = false
                directoryStatus = error.localizedDescription
            }
        }
    }

    private nonisolated static func matchesScene(_ item: MediaStreamItem, countryCodes: [String], languageTerms: [String]) -> Bool {
        let country = (item.country ?? "").lowercased()
        let countryNames: [String: [String]] = [
            "CN": ["china", "中国"], "HK": ["hong kong", "香港"], "MO": ["macao", "macau", "澳门", "澳門"],
            "TW": ["taiwan", "台湾", "台灣"], "SG": ["singapore", "新加坡"], "MY": ["malaysia", "马来西亚", "馬來西亞"],
            "US": ["united states", "usa", "美国", "美國"], "CA": ["canada", "加拿大"], "AU": ["australia", "澳大利亚", "澳洲"],
            "NZ": ["new zealand", "新西兰", "紐西蘭"], "GB": ["united kingdom", "英国", "英國"]
        ]
        let countryOK = countryCodes.isEmpty || countryCodes.contains { code in
            countryNames[code, default: []].contains(where: country.contains)
        }
        let language = (item.language ?? "").lowercased()
        let languageOK = languageTerms.isEmpty || languageTerms.contains { language.contains($0.lowercased()) }
        return countryOK && languageOK
    }

    func scheduleStop(minutes: Int?) {
        timerTask?.cancel()
        timerTask = nil
        guard let minutes, minutes > 0 else { stopAt = nil; return }
        let deadline = Date().addingTimeInterval(Double(minutes * 60))
        stopAt = deadline
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func clearPlayer() {
        playbackGeneration += 1
        preflightTask?.cancel()
        preflightTask = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        directRelay.stop()
        clearPlayerObjects()
    }

    private func clearPlayerObjects() {
        player?.pause()
        player = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}
