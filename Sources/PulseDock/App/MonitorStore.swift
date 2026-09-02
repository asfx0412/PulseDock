import AppKit
import CoreLocation
import Foundation
import Network
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MonitorStore: ObservableObject {
    @Published var cpuUsage = 0.0
    @Published var memoryUsage = 0.0
    @Published var gpuUsage = 0.0
    @Published var downloadSpeed = 0.0
    @Published var uploadSpeed = 0.0
    @Published var latency: Double?
    @Published var health: ConnectionHealth = .checking
    @Published var interfaceLabel = "正在检测"
    @Published var vpnActive = false
    @Published var proxyActive = false
    @Published var ip = IPIdentity()
    @Published var temperature: Double?
    @Published var temperatureSource = "芯片温度"
    @Published var thermalState = "正常"
    @Published var batteryPercent: Double?
    @Published private(set) var mainThreadResponsiveness = MainThreadResponsivenessSnapshot.idle
    @Published private(set) var metricsCollectionDurationMilliseconds = 0.0
    @Published var events: [DiagnosticEvent] = []
    @Published var timelineEvents: [TimelineEvent]
    @Published var thermalRisk = ThermalRiskSnapshot()
    @Published var speedHistory: [SpeedSample] = []
    @Published var lastIPUpdate: Date?
    @Published var codexQuota = QuotaSnapshot.locked
    @Published var codexCommunityReset = CodexCommunityResetSnapshot.loading
    @Published var weather = WeatherSnapshot.unconfigured
    @Published var weatherLocation: WeatherLocation? { didSet { persistWeatherLocation(); refreshWeather() } }
    @Published var citySearchQuery = ""
    @Published var citySearchResults: [WeatherLocation] = []
    @Published var citySearchInProgress = false
    @Published var weatherLocationInProgress = false
    @Published var weatherLocationStatus = ""
    /// A safe technical breadcrumb for help/diagnostics.  UI status remains
    /// actionable and never exposes Core Location's raw error domain/code.
    @Published private(set) var weatherLocationDiagnostic = ""
    @Published var weatherLocationMode: WeatherLocationMode {
        didSet {
            UserDefaults.standard.set(weatherLocationMode.rawValue, forKey: PreferenceKey.weatherLocationMode)
            if weatherLocationMode == .automatic {
                requestAutomaticWeatherLocation(force: true)
            } else {
                cancelAutomaticWeatherLocationRetry(resetFailureCount: true)
                if weatherLocationInProgress { cancelCurrentWeatherLocation() }
            }
        }
    }
    @Published private(set) var lastWeatherLocationCheck: Date?
    @Published private(set) var isRefreshingQuota = false
    @Published private(set) var isRefreshingClash = false
    @Published private(set) var isRefreshingWeather = false
    @Published private(set) var isRefreshingCommunityReset = false
    @Published private(set) var isRefreshingIP = false

    @Published var diagnosticReport = NetworkDiagnosticReport.idle
    @Published var clashQuota = ClashQuotaSnapshot.locked
    @Published var clashSubscriptions: [ClashQuotaSnapshot] = []
    @Published var selectedClashIdentifier: String { didSet { UserDefaults.standard.set(selectedClashIdentifier, forKey: PreferenceKey.selectedClash) ; applySelectedClash() } }
    @Published var clashControllerEnabled: Bool { didSet { UserDefaults.standard.set(clashControllerEnabled, forKey: PreferenceKey.clashControllerEnabled) } }
    @Published var clashControllerURL: String { didSet { UserDefaults.standard.set(clashControllerURL, forKey: PreferenceKey.clashControllerURL) } }
    @Published var clashControllerSecret: String
    @Published var clashSyncEvidence = "仅重读本地订阅元数据"
    @Published var isCheckingClashController = false
    @Published var clashCredentialStatus = "凭据保险库尚未解锁"

    @Published var remoteDevices: [RemoteDeviceConfiguration] { didSet { persistRemoteDevices() } }
    @Published var remoteSnapshots: [UUID: RemoteDeviceSnapshot] = [:]
    @Published var newRemoteName = ""
    @Published var newRemoteAlias = ""
    @Published private(set) var isRefreshingRemoteDevices = false
    @Published private(set) var refreshingRemoteDeviceIDs: Set<UUID> = []
    @Published private(set) var remoteActionFeedback: [UUID: String] = [:]

    @Published var feishuAlertsEnabled: Bool { didSet { UserDefaults.standard.set(feishuAlertsEnabled, forKey: PreferenceKey.feishuAlertsEnabled) } }
    @Published var feishuWebhook: String
    @Published var feishuSigningSecret: String
    @Published var alertCooldownMinutes: Int { didSet { UserDefaults.standard.set(alertCooldownMinutes, forKey: PreferenceKey.alertCooldownMinutes) } }
    @Published var feishuTestStatus = "尚未测试"
    @Published var feishuCredentialStatus = "凭据保险库尚未解锁"
    @Published var apiConnectors: [APIConnectorConfiguration] { didSet { persistAPIConnectors() } }
    @Published var apiConnectorSnapshots: [UUID: APIConnectorSnapshot] = [:]
    @Published var newAPIConnectorName = ""
    @Published var newAPIConnectorKind: APIConnectorKind = .customRateLimit
    @Published var newAPIConnectorEndpoint = ""
    @Published var newAPIConnectorKey = ""
    @Published private(set) var isRefreshingAPIConnectors = false
    @Published private(set) var credentialVaultUnlocked = false
    @Published private(set) var credentialVaultStatus = "已锁定；本次运行尚未读取任何凭据"
    @Published var pomodoroPhase: PomodoroPhase = .idle
    @Published var pomodoroSecondsRemaining = 25 * 60
    @Published var focusMinutes: Int { didSet { persistProductivitySettings(); resetPomodoroIfIdle() } }
    @Published var breakMinutes: Int { didSet { persistProductivitySettings() } }
    @Published var longBreakMinutes: Int { didSet { persistProductivitySettings() } }
    @Published var sessionsBeforeLongBreak: Int { didSet { persistProductivitySettings() } }
    @Published var completedFocusToday: Int
    @Published var skippedToday: Int
    @Published var focusSecondsToday: Int

    @Published var workStartMinutes: Int { didSet { persistProductivitySettings(); updateWorkStatus() } }
    @Published var workEndMinutes: Int { didSet { persistProductivitySettings(); updateWorkStatus() } }
    @Published var lunchStartMinutes: Int { didSet { persistProductivitySettings(); updateWorkStatus() } }
    @Published var lunchEndMinutes: Int { didSet { persistProductivitySettings(); updateWorkStatus() } }
    @Published var workWeekdays: Set<Int> { didSet { persistProductivitySettings(); updateWorkStatus() } }
    @Published var manualDayOverride: Int { didSet { persistProductivitySettings(); updateWorkStatus() } }
    @Published var overtimeActive: Bool { didSet { persistProductivitySettings(); updateWorkStatus() } }
    @Published var includeBrowsers: Bool { didSet { persistProductivitySettings() } }
    @Published var includeCommunication: Bool { didSet { persistProductivitySettings() } }
    @Published var workStatus: WorkStatus = .working
    @Published var activeApplication = ActiveApplicationSnapshot()
    @Published var activeWorkSecondsToday = 0
    @Published var activityRankings: [AppActivityRanking] = []
    @Published var activityRangeDays = 1 { didSet { refreshActivityRankings() } }
    @Published var idleThresholdSeconds: Int { didSet { persistProductivitySettings() } }
    @Published var excludedApplicationIDs: Set<String> { didSet { persistProductivitySettings(); refreshActivityRankings() } }
    @Published var now = Date()

    private let systemMetricsSampler = SystemMetricsSampler()
    private let mainThreadResponsivenessMonitor = MainThreadResponsivenessMonitor()
    private let pathObserver = PathObserver()
    private let probe = NetworkProbe()
    private let quotaService = CodexQuotaService()
    private let communityResetService = CodexCommunityResetService()
    private let weatherService = WeatherService()
    private let currentLocationService = CurrentLocationService()
    private let clashService = ClashQuotaService()
    private let clashControllerService = ClashControllerService()
    private let clashWatcher = ClashProfilesWatcher()
    private let diagnosticService = AINetworkDiagnosticService()
    private let activityTracker = AppActivityTracker()
    private let sshMonitorService = SSHMonitorService()
    private let remoteNetworkScopeService = RemoteNetworkScopeService()
    private let feishuAlertService = FeishuAlertService()
    private let apiConnectorService = APIConnectorService()
    let ambientSound = AmbientSoundService()
    private var apiConnectorKeyCache: [UUID: String] = [:]
    private var apiConnectorRefreshGeneration: [UUID: Int] = [:]
    private var quotaAccessGeneration = 0
    private var credentialVault = CredentialVault()
    private let eventLedger: EventLedger
    var timelineStorageError: String? { eventLedger.lastWriteError }
    var timelineStoragePath: String { eventLedger.storageDescription }
    private var metricTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var quotaTask: Task<Void, Never>?
    private var communityResetTask: Task<Void, Never>?
    private var weatherTask: Task<Void, Never>?
    private var weatherReadTask: Task<Void, Never>?
    private var weatherReadLocationID: String?
    private var weatherLocationRetryTask: Task<Void, Never>?
    private var quotaRetryTask: Task<Void, Never>?
    private var weatherRetryTask: Task<Void, Never>?
    private var apiConnectorRetryTasks: [UUID: Task<Void, Never>] = [:]
    private var clashTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var remoteTask: Task<Void, Never>?
    private var apiConnectorTask: Task<Void, Never>?
    private var lastError: String?
    private var pathSatisfied = false
    private var pathInitialized = false
    private var phaseBeforePause: PomodoroPhase = .focus
    private var pomodoroDeadline: Date?
    private var previousWorkStatus: WorkStatus?
    private var currentDayKey: String
    private var sessionActive = true
    private var workspaceObservers: [NSObjectProtocol] = []
    private var thermalSamples: [(date: Date, temperature: Double, load: Double)] = []
    private var lastAlertAt: [String: Date] = [:]
    private var lastRemoteProbeAt: [UUID: Date] = [:]
    private var remoteObservationUntil: [UUID: Date] = [:]
    private var remoteFailureStreak: [UUID: Int] = [:]
    private var remoteNetworkGraceUntil: Date?
    private var weatherSelectionGeneration = 0
    private var weatherRefreshGeneration = 0
    private var automaticWeatherLocationFailureCount = 0
    private var panelShownObserver: NSObjectProtocol?
    private var citySearchGeneration = 0

    private enum PreferenceKey {
        static let focusMinutes = "PulseDock.focusMinutes"
        static let breakMinutes = "PulseDock.breakMinutes"
        static let longBreakMinutes = "PulseDock.longBreakMinutes"
        static let sessionsBeforeLongBreak = "PulseDock.sessionsBeforeLongBreak"
        static let workStart = "PulseDock.workStartMinutes"
        static let workEnd = "PulseDock.workEndMinutes"
        static let lunchStart = "PulseDock.lunchStartMinutes"
        static let lunchEnd = "PulseDock.lunchEndMinutes"
        static let workWeekdays = "PulseDock.workWeekdays"
        static let dayOverride = "PulseDock.manualDayOverride"
        static let dayOverrideDate = "PulseDock.manualDayOverrideDate"
        static let overtime = "PulseDock.overtimeActive"
        static let overtimeDate = "PulseDock.overtimeDate"
        static let includeBrowsers = "PulseDock.includeBrowsers"
        static let includeCommunication = "PulseDock.includeCommunication"
        static let selectedClash = "PulseDock.selectedClashIdentifier"
        static let customClashPath = "PulseDock.customClashMetadataPath"
        static let statsDate = "PulseDock.productivityStatsDate"
        static let completed = "PulseDock.completedFocusToday"
        static let skipped = "PulseDock.skippedToday"
        static let focusSeconds = "PulseDock.focusSecondsToday"
        static let activeSeconds = "PulseDock.activeWorkSecondsToday"
        static let idleThreshold = "PulseDock.activityIdleThresholdSeconds"
        static let excludedApplications = "PulseDock.excludedApplicationIDs"
        static let weatherLocation = "PulseDock.weatherLocation"
        static let weatherLocationMode = "PulseDock.weatherLocationMode"
        static let lastWeatherLocationCheck = "PulseDock.lastWeatherLocationCheck"
        static let clashControllerEnabled = "PulseDock.clashControllerEnabled"
        static let clashControllerURL = "PulseDock.clashControllerURL"
        static let remoteDevices = "PulseDock.remoteDevices"
        static let feishuAlertsEnabled = "PulseDock.feishuAlertsEnabled"
        static let alertCooldownMinutes = "PulseDock.alertCooldownMinutes"
        static let apiConnectors = "PulseDock.apiConnectors"
    }

    init() {
        let defaults = UserDefaults.standard
        let ledger = EventLedger()
        eventLedger = ledger
        if ledger.events.isEmpty {
            ledger.append(category: .system, severity: .info, title: "时间线已开始记录", evidence: "PulseDock 已启动本地事件账本；普通信息会去重，异常与恢复将保留证据。", source: "PulseDock 本机")
        }
        timelineEvents = ledger.events
        let today = ChinaHolidayCalendar.dateKey(Date())
        currentDayKey = today
        focusMinutes = max(1, defaults.object(forKey: PreferenceKey.focusMinutes) as? Int ?? 25)
        breakMinutes = max(1, defaults.object(forKey: PreferenceKey.breakMinutes) as? Int ?? 5)
        longBreakMinutes = max(1, defaults.object(forKey: PreferenceKey.longBreakMinutes) as? Int ?? 20)
        sessionsBeforeLongBreak = max(1, defaults.object(forKey: PreferenceKey.sessionsBeforeLongBreak) as? Int ?? 4)
        workStartMinutes = defaults.object(forKey: PreferenceKey.workStart) as? Int ?? 9 * 60
        workEndMinutes = defaults.object(forKey: PreferenceKey.workEnd) as? Int ?? 18 * 60
        lunchStartMinutes = defaults.object(forKey: PreferenceKey.lunchStart) as? Int ?? 12 * 60
        lunchEndMinutes = defaults.object(forKey: PreferenceKey.lunchEnd) as? Int ?? 13 * 60
        workWeekdays = Set(defaults.array(forKey: PreferenceKey.workWeekdays) as? [Int] ?? [2, 3, 4, 5, 6])
        manualDayOverride = defaults.string(forKey: PreferenceKey.dayOverrideDate) == today ? defaults.integer(forKey: PreferenceKey.dayOverride) : 0
        overtimeActive = defaults.string(forKey: PreferenceKey.overtimeDate) == today && defaults.bool(forKey: PreferenceKey.overtime)
        includeBrowsers = defaults.object(forKey: PreferenceKey.includeBrowsers) as? Bool ?? true
        includeCommunication = defaults.object(forKey: PreferenceKey.includeCommunication) as? Bool ?? false
        selectedClashIdentifier = defaults.string(forKey: PreferenceKey.selectedClash) ?? ""
        clashControllerEnabled = defaults.bool(forKey: PreferenceKey.clashControllerEnabled)
        clashControllerURL = defaults.string(forKey: PreferenceKey.clashControllerURL) ?? "127.0.0.1:9090"
        // Never read Keychain during launch: a locked login keychain can queue
        // several system prompts after the UI is already visible.
        clashControllerSecret = ""
        remoteDevices = Self.sanitizeRemoteConfigurations(defaults.data(forKey: PreferenceKey.remoteDevices).flatMap { try? JSONDecoder().decode([RemoteDeviceConfiguration].self, from: $0) } ?? [])
        feishuAlertsEnabled = defaults.bool(forKey: PreferenceKey.feishuAlertsEnabled)
        feishuWebhook = ""
        feishuSigningSecret = ""
        alertCooldownMinutes = max(5, defaults.object(forKey: PreferenceKey.alertCooldownMinutes) as? Int ?? 30)
        apiConnectors = Self.sanitizeAPIConfigurations(defaults.data(forKey: PreferenceKey.apiConnectors).flatMap { try? JSONDecoder().decode([APIConnectorConfiguration].self, from: $0) } ?? [])
        let statsAreToday = defaults.string(forKey: PreferenceKey.statsDate) == today
        completedFocusToday = statsAreToday ? defaults.integer(forKey: PreferenceKey.completed) : 0
        skippedToday = statsAreToday ? defaults.integer(forKey: PreferenceKey.skipped) : 0
        focusSecondsToday = statsAreToday ? defaults.integer(forKey: PreferenceKey.focusSeconds) : 0
        activeWorkSecondsToday = statsAreToday ? defaults.integer(forKey: PreferenceKey.activeSeconds) : 0
        idleThresholdSeconds = max(30, defaults.object(forKey: PreferenceKey.idleThreshold) as? Int ?? 120)
        excludedApplicationIDs = Set(defaults.stringArray(forKey: PreferenceKey.excludedApplications) ?? [])
        weatherLocation = defaults.data(forKey: PreferenceKey.weatherLocation).flatMap { try? JSONDecoder().decode(WeatherLocation.self, from: $0) }
        weatherLocationMode = WeatherLocationMode(rawValue: defaults.string(forKey: PreferenceKey.weatherLocationMode) ?? "") ?? .fixed
        lastWeatherLocationCheck = defaults.object(forKey: PreferenceKey.lastWeatherLocationCheck) as? Date
        pomodoroSecondsRemaining = focusMinutes * 60

        pathObserver.onUpdate = { [weak self] path in Task { @MainActor in self?.apply(path: path) } }
        clashWatcher.onChange = { [weak self] in Task { @MainActor in self?.refreshClashQuota() } }
        updateWorkStatus(notify: false)
        refreshActivityRankings()
        // Persist configuration migrations (including the built-in Codex
        // connector) immediately, without touching the credential vault.
        persistAPIConnectors()
    }

    func start() {
        guard metricTask == nil else { return }
        pathObserver.start()
        clashWatcher.start()
        mainThreadResponsivenessMonitor.start()
        observeWorkspaceSession()
        panelShownObserver = NotificationCenter.default.addObserver(forName: .pulseDockPanelShown, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.requestAutomaticWeatherLocation(force: false) }
        }
        PulseDockNotifications.requestAuthorization()
        refreshIP()
        refreshWeather()
        // Remote probes begin after NWPathMonitor has delivered its first
        // authoritative path. The pre-callback state is not an offline state.
        // API credentials are unlocked only after an explicit settings action.
        metricTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snapshot = await self.systemMetricsSampler.sample()
                guard !Task.isCancelled else { return }
                self.applySystemMetrics(snapshot)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        probeTask = Task { [weak self] in
            while !Task.isCancelled { await self?.runProbe(); try? await Task.sleep(for: .seconds(8)) }
        }
        quotaTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.credentialVaultUnlocked {
                    self.refreshQuota()
                }
                try? await Task.sleep(for: .seconds(300))
            }
        }
        communityResetTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.codexCommunityReset = await self.communityResetService.read()
                try? await Task.sleep(for: .seconds(1_800))
            }
        }
        weatherTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1_800))
                self?.refreshWeather()
                self?.requestAutomaticWeatherLocation(force: false)
            }
        }
        clashTask = Task { [weak self] in
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(300)); await self?.refreshClashQuotaAsync() }
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); self?.tickClock() }
        }
        remoteTask = Task { [weak self] in
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(5)); await self?.refreshRemoteDevicesAsync(force: false) }
        }
        apiConnectorTask = Task { [weak self] in
            // Usage data is useful only when it stays reasonably fresh. All connector
            // probes are read-only and are deliberately throttled to a five-minute cadence.
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(300)); await self?.refreshAPIConnectorsAsync() }
        }
    }

    func stop() {
        // Invalidate every pending Core Location/MapKit callback before the
        // app tears down its periodic tasks.  A late result must never revive
        // a stopped store or overwrite a later manual selection.
        weatherSelectionGeneration += 1
        currentLocationService.cancelCurrentRequest()
        weatherLocationInProgress = false
        [metricTask, probeTask, quotaTask, communityResetTask, weatherTask, weatherReadTask, weatherLocationRetryTask, quotaRetryTask, weatherRetryTask, clashTask, clockTask, remoteTask, apiConnectorTask].forEach { $0?.cancel() }
        apiConnectorRetryTasks.values.forEach { $0.cancel() }
        apiConnectorRetryTasks.removeAll()
        if let panelShownObserver { NotificationCenter.default.removeObserver(panelShownObserver); self.panelShownObserver = nil }
        metricTask = nil; probeTask = nil; quotaTask = nil; communityResetTask = nil; weatherTask = nil; weatherReadTask = nil; weatherLocationRetryTask = nil; quotaRetryTask = nil; weatherRetryTask = nil; clashTask = nil; clockTask = nil; remoteTask = nil; apiConnectorTask = nil
        clashWatcher.stop(); pathObserver.stop()
        mainThreadResponsivenessMonitor.stop()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        activityTracker.save()
        ambientSound.stop()
        lockCredentialVault()
    }

    func refreshIP() {
        guard !isRefreshingIP else { return }
        isRefreshingIP = true
        Task { [weak self] in
            guard let self else { return }
            do { self.ip = try await probe.lookupIP(); self.lastIPUpdate = Date() }
            catch { self.record(title: "公网 IP 查询失败", detail: "将在稍后自动重试", severity: .degraded) }
            self.isRefreshingIP = false
        }
    }

    func refreshQuota() {
        guard credentialVaultUnlocked, !isRefreshingQuota else { return }
        isRefreshingQuota = true
        let generation = quotaAccessGeneration
        let previous = codexQuota
        if previous.hasDisplayPayload {
            codexQuota.refresh.status = .refreshing
        } else {
            codexQuota = .loading
        }
        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.quotaService.read()
            guard self.credentialVaultUnlocked, generation == self.quotaAccessGeneration else {
                self.isRefreshingQuota = false
                return
            }
            self.applyQuotaRefresh(snapshot, previous: previous, generation: generation)
            self.isRefreshingQuota = false
            self.evaluateQuotaState()
        }
    }

    func refreshCommunityReset() {
        guard !isRefreshingCommunityReset else { return }
        isRefreshingCommunityReset = true
        codexCommunityReset = .loading
        Task { [weak self] in
            guard let self else { return }
            self.codexCommunityReset = await self.communityResetService.read()
            self.isRefreshingCommunityReset = false
        }
    }

    func openCommunityResetSource() {
        guard let url = codexCommunityReset.sourceURL else { return }
        NSWorkspace.shared.open(url)
    }

    func searchWeatherCities() {
        let query = citySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { citySearchResults = []; return }
        citySearchGeneration += 1
        let generation = citySearchGeneration
        citySearchInProgress = true
        Task { [weak self] in
            guard let self else { return }
            let results = await self.weatherService.searchCities(query)
            guard generation == self.citySearchGeneration,
                  query == self.citySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            self.citySearchResults = results
            self.citySearchInProgress = false
        }
    }

    func selectWeatherLocation(_ location: WeatherLocation) {
        // A manual choice always wins over an older Core Location callback.
        weatherSelectionGeneration += 1
        cancelAutomaticWeatherLocationRetry(resetFailureCount: true)
        if weatherLocationInProgress {
            currentLocationService.cancelCurrentRequest()
            weatherLocationInProgress = false
        }
        weatherLocationMode = .fixed
        applyWeatherLocation(location)
    }

    private func applyWeatherLocation(_ location: WeatherLocation) {
        weatherLocation = location
        citySearchResults = []
        citySearchQuery = location.name
    }

    func useCurrentWeatherLocation() {
        if weatherLocationInProgress {
            cancelCurrentWeatherLocation()
            return
        }
        weatherSelectionGeneration += 1
        cancelAutomaticWeatherLocationRetry(resetFailureCount: true)
        let generation = weatherSelectionGeneration
        weatherLocationInProgress = true
        weatherLocationDiagnostic = ""
        weatherLocationStatus = "正在获取当前位置（最长 20 秒）…"
        currentLocationService.requestCurrentCity { [weak self] result in
            guard let self else { return }
            guard generation == self.weatherSelectionGeneration else { return }
            self.weatherLocationInProgress = false
            switch result {
            case .success(let location):
                self.weatherLocationDiagnostic = ""
                self.weatherLocationStatus = "已使用当前位置：\(location.displayName)"
                self.applyWeatherLocation(location)
            case .failure(let error):
                self.weatherLocationDiagnostic = error.diagnosticDescription
                self.weatherLocationStatus = "未能使用当前位置：\(error.localizedDescription)"
            }
        }
    }

    func setWeatherLocationMode(_ mode: WeatherLocationMode) {
        weatherLocationMode = mode
        if mode == .fixed, weatherLocationInProgress { cancelCurrentWeatherLocation() }
    }

    func requestAutomaticWeatherLocation(force: Bool) {
        guard weatherLocationMode == .automatic, !weatherLocationInProgress else { return }
        let windowVisible = NSApp.windows.contains(where: \.isVisible)
        let minimumInterval: TimeInterval = windowVisible ? 1_800 : 7_200
        if !force, let lastWeatherLocationCheck, Date().timeIntervalSince(lastWeatherLocationCheck) < minimumInterval { return }
        weatherLocationRetryTask?.cancel()
        weatherLocationRetryTask = nil
        weatherSelectionGeneration += 1
        let generation = weatherSelectionGeneration
        weatherLocationInProgress = true
        weatherLocationDiagnostic = ""
        weatherLocationStatus = "正在检查当前位置（最长 20 秒）…"
        lastWeatherLocationCheck = Date()
        UserDefaults.standard.set(lastWeatherLocationCheck, forKey: PreferenceKey.lastWeatherLocationCheck)
        currentLocationService.requestCurrentCity { [weak self] result in
            guard let self, generation == self.weatherSelectionGeneration else { return }
            self.weatherLocationInProgress = false
            switch result {
            case .success(let candidate):
                guard self.weatherLocationMode == .automatic else { return }
                self.cancelAutomaticWeatherLocationRetry(resetFailureCount: true)
                self.weatherLocationDiagnostic = ""
                if let existing = self.weatherLocation {
                    guard WeatherLocationPolicy.shouldUpdate(current: existing, candidate: candidate) else {
                        self.weatherLocationStatus = "位置未发生有效变化 · 上次检查 \(Date().formatted(date: .omitted, time: .shortened))"
                        return
                    }
                }
                self.weatherLocationStatus = "已自动更新：\(candidate.displayName)"
                self.applyWeatherLocation(candidate)
            case .failure(let error):
                self.weatherLocationDiagnostic = error.diagnosticDescription
                self.handleAutomaticWeatherLocationFailure(error, generation: generation)
            }
        }
    }

    func cancelCurrentWeatherLocation() {
        guard weatherLocationInProgress else { return }
        weatherSelectionGeneration += 1
        cancelAutomaticWeatherLocationRetry(resetFailureCount: true)
        currentLocationService.cancelCurrentRequest()
        weatherLocationInProgress = false
        weatherLocationDiagnostic = "Core Location: request cancelled by user"
        weatherLocationStatus = "已取消当前位置请求"
    }

    /// `locationUnknown` and a short-session timeout are recoverable on
    /// laptops: networking may be healthy while macOS is still resolving a
    /// Wi-Fi based position.  Keep the existing city/weather, retry only three
    /// times, then fall back to the normal 30-minute check.  Permission and
    /// service states deliberately do not retry.
    private func handleAutomaticWeatherLocationFailure(_ error: CurrentLocationError, generation: Int) {
        let retainedLocation = weatherLocation != nil
        let prefix = retainedLocation ? "暂时无法确定当前位置，已保留原地点" : "暂时无法确定当前位置"
        guard error.supportsAutomaticRetry else {
            automaticWeatherLocationFailureCount = 0
            weatherLocationRetryTask?.cancel()
            weatherLocationRetryTask = nil
            weatherLocationStatus = "\(prefix)：\(error.localizedDescription)；请检查系统定位服务和 PulseDock 的位置权限"
            return
        }

        automaticWeatherLocationFailureCount += 1
        guard let delay = WeatherLocationRetryPolicy.delay(forFailureCount: automaticWeatherLocationFailureCount) else {
            weatherLocationRetryTask?.cancel()
            weatherLocationRetryTask = nil
            weatherLocationStatus = "\(prefix)；已完成本轮自动重试，将在下次常规检查时再试"
            return
        }

        weatherLocationStatus = "\(prefix)；将在\(locationRetryDelayLabel(delay))自动重试"
        weatherLocationRetryTask?.cancel()
        weatherLocationRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self,
                  self.weatherLocationMode == .automatic,
                  self.weatherSelectionGeneration == generation,
                  !self.weatherLocationInProgress else { return }
            self.requestAutomaticWeatherLocation(force: true)
        }
    }

    private func cancelAutomaticWeatherLocationRetry(resetFailureCount: Bool) {
        weatherLocationRetryTask?.cancel()
        weatherLocationRetryTask = nil
        if resetFailureCount { automaticWeatherLocationFailureCount = 0 }
    }

    private func locationRetryDelayLabel(_ delay: TimeInterval) -> String {
        switch delay {
        case ..<60: "\(Int(delay)) 秒后"
        default: "\(Int(delay / 60)) 分钟后"
        }
    }

    func refreshWeather() {
        guard let location = weatherLocation else { weather = .unconfigured; return }
        // A city change supersedes the in-flight request.  Without clearing
        // this flag, the old request fails its generation/location guard and
        // leaves `isRefreshingWeather` stuck true, blocking the new city.
        if isRefreshingWeather, weatherReadLocationID != location.id {
            weatherRefreshGeneration += 1
            weatherReadTask?.cancel()
            weatherReadTask = nil
            weatherReadLocationID = nil
            isRefreshingWeather = false
        }
        guard !isRefreshingWeather else { return }
        weatherRefreshGeneration += 1
        let generation = weatherRefreshGeneration
        let previous = weather
        isRefreshingWeather = true
        weatherReadLocationID = location.id
        if weather.hasDisplayPayload {
            weather.refresh.status = .refreshing
        } else {
            weather.state = .loading
            weather.location = location
            weather.message = "正在读取天气"
            weather.refresh.status = .refreshing
        }
        weatherReadTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.weatherService.read(location: location)
            guard generation == self.weatherRefreshGeneration else { return }
            guard !Task.isCancelled, self.weatherLocation?.id == location.id else {
                self.isRefreshingWeather = false
                self.weatherReadTask = nil
                self.weatherReadLocationID = nil
                return
            }
            self.applyWeatherRefresh(result, previous: previous, generation: generation)
            self.isRefreshingWeather = false
            self.weatherReadTask = nil
            self.weatherReadLocationID = nil
        }
    }

    /// Applies a Codex read without allowing one transient process/network
    /// failure to erase the last official local snapshot.
    private func applyQuotaRefresh(_ fresh: QuotaSnapshot, previous: QuotaSnapshot, generation: Int) {
        guard credentialVaultUnlocked, generation == quotaAccessGeneration else { return }
        if fresh.state == .available {
            var current = fresh
            current.refresh = .fresh(at: fresh.updatedAt ?? Date())
            codexQuota = current
            quotaRetryTask?.cancel()
            quotaRetryTask = nil
            return
        }

        let failures = previous.refresh.failureCount + 1
        var retained = fresh
        if retained.copyDisplayPayload(from: previous) {
            retained.refresh = RefreshMetadata(
                status: .stale,
                lastSuccessAt: previous.refresh.lastSuccessAt ?? previous.updatedAt,
                lastFailureAt: Date(),
                failureMessage: fresh.message,
                failureCount: failures
            )
        } else {
            retained.refresh = RefreshMetadata(
                status: .initialFailure,
                lastFailureAt: Date(),
                failureMessage: fresh.message,
                failureCount: failures
            )
        }
        codexQuota = retained
        scheduleQuotaRetry(afterFailureCount: failures, generation: generation)
    }

    private func scheduleQuotaRetry(afterFailureCount failures: Int, generation: Int) {
        guard credentialVaultUnlocked, generation == quotaAccessGeneration else { return }
        quotaRetryTask?.cancel()
        let delay = RetryPolicy.delay(forFailureCount: failures)
        codexQuota.refresh.nextRetryAt = Date().addingTimeInterval(delay)
        quotaRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.credentialVaultUnlocked,
                  self.quotaAccessGeneration == generation else { return }
            self.refreshQuota()
        }
    }

    private func applyWeatherRefresh(_ fresh: WeatherSnapshot, previous: WeatherSnapshot, generation: Int) {
        guard generation == weatherRefreshGeneration else { return }
        if fresh.state == .available {
            var current = fresh
            current.refresh = .fresh(at: fresh.updatedAt ?? Date())
            weather = current
            weatherRetryTask?.cancel()
            weatherRetryTask = nil
            return
        }

        let failures = previous.refresh.failureCount + 1
        var retained = fresh
        if retained.copyDisplayPayload(from: previous) {
            retained.state = .available
            retained.refresh = RefreshMetadata(
                status: .stale,
                lastSuccessAt: previous.refresh.lastSuccessAt ?? previous.updatedAt,
                lastFailureAt: Date(),
                failureMessage: fresh.failure?.label ?? fresh.message,
                failureCount: failures
            )
        } else {
            retained.refresh = RefreshMetadata(
                status: .initialFailure,
                lastFailureAt: Date(),
                failureMessage: fresh.failure?.label ?? fresh.message,
                failureCount: failures
            )
        }
        weather = retained
        scheduleWeatherRetry(afterFailureCount: failures, generation: generation, locationID: fresh.location?.id)
    }

    private func scheduleWeatherRetry(afterFailureCount failures: Int, generation: Int, locationID: String?) {
        weatherRetryTask?.cancel()
        let delay = RetryPolicy.delay(forFailureCount: failures)
        weather.refresh.nextRetryAt = Date().addingTimeInterval(delay)
        weatherRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self,
                  self.weatherRefreshGeneration == generation,
                  self.weatherLocation?.id == locationID else { return }
            self.refreshWeather()
        }
    }

    func runAIDiagnostics() {
        guard diagnosticReport.health != .checking else { return }
        diagnosticReport = NetworkDiagnosticReport(health: .checking, summary: "正在进行三轮分层采样", recommendation: "通常需要 10–30 秒；以中位数判断，单次冷连接不会直接触发换节点建议。", checks: [], completedAt: nil)
        Task { [weak self] in
            guard let self else { return }
            var report = await diagnosticService.diagnose()
            // A diagnostic never bypasses the vault: background/keyless
            // startup must perform zero Codex reads until the user unlocks.
            // When unlocked, reuse the governed refresh path (single-flight,
            // generation guard, stale-value retention) rather than writing a
            // second raw snapshot from the diagnostic task.
            let codexCheck: DiagnosticCheck
            if self.credentialVaultUnlocked {
                let generation = self.quotaAccessGeneration
                self.refreshQuota()
                let snapshot = self.codexQuota
                let codexOK = snapshot.hasDisplayPayload || snapshot.state == .available
                codexCheck = DiagnosticCheck(
                    id: "codex-service", title: "Codex 本地服务", state: codexOK ? .passed : .running,
                    detail: codexOK ? "已使用受控额度刷新；显示最近有效快照" : "已安排受控额度读取；等待 app-server 初始化", latencyMS: nil
                )
                // A lock during network diagnosis changes the generation and
                // intentionally leaves the diagnostic neutral instead of
                // restoring or exposing an old quota result.
                if generation != self.quotaAccessGeneration || !self.credentialVaultUnlocked {
                    report.checks.append(DiagnosticCheck(id: "codex-service", title: "Codex 本地服务", state: .waiting, detail: "凭据保险库已锁定；未读取额度", latencyMS: nil))
                } else {
                    report.checks.append(codexCheck)
                }
            } else {
                report.checks.append(DiagnosticCheck(id: "codex-service", title: "Codex 本地服务", state: .waiting, detail: "凭据保险库未解锁；未读取额度", latencyMS: nil))
            }
            let codexFailed = report.checks.last?.state == .failed
            if report.health == .healthy, codexFailed {
                report.health = .failed
                report.summary = "网络正常，但 Codex 本地服务异常"
                report.recommendation = "重启 ChatGPT/Codex 并确认已经登录；若仍失败，请更新或重新安装 Codex。"
            }
            diagnosticReport = report
            eventLedger.append(category: .network, severity: report.health == .healthy ? .info : .warning, title: "AI 网络诊断：\(report.summary)", evidence: report.recommendation, source: "手动深度诊断")
            timelineEvents = eventLedger.events
        }
    }

    func refreshClashQuota() {
        guard credentialVaultUnlocked, !isRefreshingClash else { return }
        isRefreshingClash = true
        let generation = quotaAccessGeneration
        Task { [weak self] in
            guard let self else { return }
            // Local YAML parsing can finish within a single render pass. Yield
            // and retain the state briefly so a manual refresh has visible,
            // trustworthy feedback instead of looking like a dead button.
            await Task.yield()
            if self.clashControllerEnabled {
                let sync = await self.clashControllerService.synchronize(baseURL: self.clashControllerURL, secret: self.clashControllerSecret)
                self.clashSyncEvidence = sync.evidence
                self.eventLedger.append(category: .clash, severity: sync.success ? .healthy : .warning, title: sync.success ? "Clash 已请求同步" : "Clash 同步失败", evidence: sync.evidence, source: "Mihomo 本地控制器")
                self.timelineEvents = self.eventLedger.events
            } else {
                self.clashSyncEvidence = "控制器同步未启用，仅重读本地订阅元数据"
            }
            await self.refreshClashQuotaAsync(expectedGeneration: generation)
            try? await Task.sleep(for: .milliseconds(450))
            self.isRefreshingClash = false
        }
    }

    func inspectClashController() {
        guard !isCheckingClashController else { return }
        isCheckingClashController = true
        clashSyncEvidence = "正在检测本机 Mihomo 控制器…"
        Task { [weak self] in
            guard let self else { return }
            let result = await self.clashControllerService.inspect(baseURL: self.clashControllerURL, secret: self.clashControllerSecret)
            self.clashSyncEvidence = result.evidence
            self.isCheckingClashController = false
        }
    }

    func autoDiscoverClashController() {
        guard !isCheckingClashController else { return }
        isCheckingClashController = true
        clashSyncEvidence = "正在查找 Clash Verge/Mihomo 的实际本机监听端口…"
        Task { [weak self] in
            guard let self else { return }
            let result = await self.clashControllerService.discover(preferred: self.clashControllerURL, secret: self.clashControllerSecret)
            if let address = result.address {
                self.clashControllerURL = address.replacingOccurrences(of: "http://", with: "")
                self.clashControllerEnabled = true
            }
            self.clashSyncEvidence = result.evidence
            self.isCheckingClashController = false
            if result.inspection?.reachable == true { self.refreshClashQuota() }
        }
    }

    /// One explicit user action unlocks one vault Keychain item. No feature is
    /// allowed to read a secret by itself afterwards.
    func unlockCredentialVault() {
        switch CredentialVaultService.unlock() {
        case let .unlocked(vault):
            credentialVault = vault
            applyCredentialVault()
            credentialVaultUnlocked = true
            quotaAccessGeneration += 1
            credentialVaultStatus = "已解锁；本次运行只读取一次统一保险库"
            refreshClashQuota()
            refreshQuota()
            refreshAPIConnectors()
        case .missing:
            credentialVault = CredentialVault()
            applyCredentialVault()
            credentialVaultUnlocked = true
            quotaAccessGeneration += 1
            credentialVaultStatus = "新保险库已解锁；旧版分散凭据不会自动读取"
            refreshClashQuota()
            refreshQuota()
            refreshAPIConnectors()
        case .interactionRequired:
            credentialVaultStatus = "钥匙串未允许读取；可在钥匙串访问中删除旧 PulseDock 项目后重新保存"
        case let .failed(status):
            credentialVaultStatus = "凭据保险库读取失败（OSStatus \(status)）"
        }
    }

    /// Explicit compatibility action. All legacy reads are non-interactive, so
    /// this can never enqueue a series of macOS password dialogs.
    func importReadableLegacyCredentials() {
        guard credentialVaultUnlocked else {
            credentialVaultStatus = "请先解锁统一凭据保险库"
            return
        }
        let migration = migrateLegacyCredentials()
        applyCredentialVault()
        credentialVaultStatus = migration.status(defaultText: "没有发现可静默读取的旧版凭据")
    }

    func lockCredentialVault() {
        // All quota sources share the same explicit session gate, including
        // local Codex/Cursor/Clash readers. No amount remains visible before
        // the user unlocks once during this launch.
        quotaAccessGeneration += 1
        quotaRetryTask?.cancel()
        quotaRetryTask = nil
        apiConnectorRetryTasks.values.forEach { $0.cancel() }
        apiConnectorRetryTasks.removeAll()
        for connector in apiConnectors {
            apiConnectorRefreshGeneration[connector.id, default: 0] += 1
            apiConnectorSnapshots[connector.id] = waitingUnlockSnapshot(id: connector.id, previous: nil)
        }
        codexQuota = .locked
        clashQuota = .locked
        clashSubscriptions = []
        isRefreshingQuota = false
        isRefreshingClash = false
        credentialVault = CredentialVault()
        apiConnectorKeyCache.removeAll()
        clashControllerSecret = ""
        feishuWebhook = ""
        feishuSigningSecret = ""
        credentialVaultUnlocked = false
        credentialVaultStatus = "已锁定；退出前内存凭据已清空"
        clashCredentialStatus = "凭据保险库已锁定"
        feishuCredentialStatus = "凭据保险库已锁定；告警暂停"
    }

    func saveCredentialVault() {
        guard credentialVaultUnlocked else {
            credentialVaultStatus = "请先解锁凭据保险库"
            return
        }
        credentialVault["clash-controller-secret"] = clashControllerSecret
        credentialVault["feishu-webhook"] = feishuWebhook
        credentialVault["feishu-signing-secret"] = feishuSigningSecret
        for (id, key) in apiConnectorKeyCache { credentialVault[apiCredentialKey(id)] = key }
        switch CredentialVaultService.saveAfterUnlock(credentialVault) {
        case .saved:
            credentialVaultStatus = "已保存全部变更；本次运行不会再次请求钥匙串"
            clashCredentialStatus = "使用统一凭据保险库"
            feishuCredentialStatus = "使用统一凭据保险库"
        case .removed:
            credentialVaultStatus = "保险库已清除"
        case .interactionRequired:
            credentialVaultStatus = "本次会话仍可使用，但钥匙串拒绝静默保存；请重新解锁后再保存"
        case let .failed(status):
            credentialVaultStatus = "凭据保险库保存失败（OSStatus \(status)）"
        }
    }

    func clearCredentialVault() {
        guard confirmCredentialRemoval("清除 PulseDock 统一凭据保险库？") else { return }
        switch CredentialVaultService.remove() {
        case .removed:
            lockCredentialVault()
            credentialVaultStatus = "已清除统一凭据保险库；不影响其他应用"
            feishuAlertsEnabled = false
        case .interactionRequired:
            credentialVaultStatus = "钥匙串未允许清除；请在钥匙串访问中修复 PulseDock 项目"
        case let .failed(status):
            credentialVaultStatus = "凭据保险库清除失败（OSStatus \(status)）"
        case .saved:
            break
        }
    }

    func openKeychainAccess() {
        let candidates = [
            "/System/Applications/Utilities/Keychain Access.app",
            "/System/Library/CoreServices/Applications/Keychain Access.app"
        ]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            feishuCredentialStatus = "未找到“钥匙串访问”；可在 Spotlight 中搜索并打开"
            return
        }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }

    private func confirmCredentialRemoval(_ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "只会删除服务名为 com.pulsedock.monitor 的对应 PulseDock 凭据，不会影响其他应用。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func applyCredentialVault() {
        clashControllerSecret = credentialVault["clash-controller-secret"]
        feishuWebhook = credentialVault["feishu-webhook"]
        feishuSigningSecret = credentialVault["feishu-signing-secret"]
        var restoredKeys: [UUID: String] = [:]
        for connector in apiConnectors {
            let key = credentialVault[apiCredentialKey(connector.id)]
            if !key.isEmpty { restoredKeys[connector.id] = key }
        }
        apiConnectorKeyCache = restoredKeys
        clashCredentialStatus = "使用统一凭据保险库"
        feishuCredentialStatus = "使用统一凭据保险库"
    }

    private func apiCredentialKey(_ id: UUID) -> String { "api-connector-\(id.uuidString)" }

    private struct LegacyMigration {
        var imported: [String] = []
        var blocked: [String] = []

        func status(defaultText: String) -> String {
            if !imported.isEmpty {
                let blockedText = blocked.isEmpty ? "" : "；另有 \(blocked.count) 项旧凭据需重新填写"
                return "已恢复旧版凭据：\(imported.joined(separator: "、"))\(blockedText)"
            }
            if !blocked.isEmpty { return "已解锁；\(blocked.count) 项旧凭据无法静默迁移，请在对应卡片重新填写一次" }
            return defaultText
        }
    }

    /// 6.4.0 moved several Keychain records into one vault but did not import
    /// existing records. Migration is deliberately non-interactive: it either
    /// restores a readable legacy value or asks for a one-time re-entry, never a
    /// queue of per-connector password sheets.
    private func migrateLegacyCredentials() -> LegacyMigration {
        var result = LegacyMigration()
        var accounts: [(key: String, label: String)] = [
            ("clash-controller-secret", "Mihomo Secret"),
            ("feishu-webhook", "飞书 Webhook"),
            ("feishu-signing-secret", "飞书签名密钥")
        ]
        accounts += apiConnectors.filter(\.kind.requiresAPIKey).map { (apiCredentialKey($0.id), $0.name) }

        for item in accounts where credentialVault[item.key].isEmpty {
            switch SecretStore.read(item.key) {
            case let .value(value) where !value.isEmpty:
                credentialVault[item.key] = value
                result.imported.append(item.label)
            case .interactionRequired:
                result.blocked.append(item.label)
            default:
                break
            }
        }
        if !result.imported.isEmpty {
            _ = CredentialVaultService.saveAfterUnlock(credentialVault)
        }
        return result
    }

    func apiKeyDraft(for id: UUID) -> String { apiConnectorKeyCache[id] ?? "" }

    func setAPIKeyDraft(_ value: String, for id: UUID) {
        guard credentialVaultUnlocked else { return }
        apiConnectorKeyCache[id] = value
        credentialVault[apiCredentialKey(id)] = value
    }

    var orderedRemoteDevices: [RemoteDeviceConfiguration] {
        remoteDevices.enumerated().sorted { lhs, rhs in
            if lhs.element.pinned != rhs.element.pinned { return lhs.element.pinned && !rhs.element.pinned }
            if lhs.element.sortOrder != rhs.element.sortOrder { return lhs.element.sortOrder < rhs.element.sortOrder }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    var orderedAPIConnectors: [APIConnectorConfiguration] {
        apiConnectors.enumerated().sorted { lhs, rhs in
            if lhs.element.pinned != rhs.element.pinned { return lhs.element.pinned && !rhs.element.pinned }
            if lhs.element.sortOrder != rhs.element.sortOrder { return lhs.element.sortOrder < rhs.element.sortOrder }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// One unified *presentation* list. Sources keep their own refresh and
    /// units; this deliberately never sums or averages provider percentages.
    var quotaPresentations: [QuotaPresentation] {
        guard credentialVaultUnlocked else { return [] }
        return orderedAPIConnectors.filter(\.enabled).map { connector in
            if connector.kind == .codexLocalQuota {
                return QuotaPresentation.codex(id: connector.id, snapshot: codexQuota, isRefreshing: isRefreshingQuota, now: now)
            }
            return QuotaPresentation.connector(
                connector,
                snapshot: apiConnectorSnapshots[connector.id] ?? APIConnectorSnapshot(id: connector.id),
                now: now,
                isRefreshing: isRefreshingAPIConnectors || apiConnectorSnapshots[connector.id]?.state == .loading
            )
        }
    }

    var dashboardQuotaPresentations: [QuotaPresentation] {
        quotaPresentations.filter { presentation in
            apiConnectors.first(where: { $0.id == presentation.id })?.showOnDashboard == true
        }
    }

    var compactPinnedQuotaPresentation: QuotaPresentation? {
        quotaPresentations.first { presentation in
            apiConnectors.first(where: { $0.id == presentation.id })?.pinned == true
        }
    }

    func quotaPresentation(for connector: APIConnectorConfiguration) -> QuotaPresentation {
        if connector.kind == .codexLocalQuota {
            return .codex(id: connector.id, snapshot: codexQuota, isRefreshing: isRefreshingQuota, now: now)
        }
        let snapshot = apiConnectorSnapshots[connector.id] ?? APIConnectorSnapshot(id: connector.id)
        return .connector(connector, snapshot: snapshot, now: now, isRefreshing: isRefreshingAPIConnectors || snapshot.state == .loading)
    }

    func apiConnectorSnapshot(for connector: APIConnectorConfiguration) -> APIConnectorSnapshot {
        guard credentialVaultUnlocked else {
            return APIConnectorSnapshot(id: connector.id, state: .waitingUnlock, message: "解锁凭据保险库后读取额度")
        }
        guard connector.kind == .codexLocalQuota else {
            return apiConnectorSnapshots[connector.id] ?? APIConnectorSnapshot(id: connector.id)
        }
        let windows = codexQuota.windows.map {
            APIUsageWindow(id: $0.id, title: $0.title, windowNumber: nil, usedPercent: $0.usedPercent, resetAt: $0.resetLabel)
        }
        return APIConnectorSnapshot(
            id: connector.id,
            state: codexQuota.state,
            remainingTokens: codexQuota.riskRemainingLabel,
            resetAt: codexQuota.resetDateTimeLabel,
            updatedAt: codexQuota.updatedAt,
            message: "Codex 官方本机 app-server（只读，不使用 API Key）",
            usageWindows: windows
        )
    }

    func addRemoteDevice() {
        let alias = newRemoteAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SSHMonitorService.validAlias(alias), !remoteDevices.contains(where: { $0.sshAlias == alias }) else { return }
        let name = newRemoteName.trimmingCharacters(in: .whitespacesAndNewlines)
        remoteDevices.append(RemoteDeviceConfiguration(name: name.isEmpty ? alias : name, sshAlias: alias, sortOrder: remoteDevices.count))
        newRemoteName = ""; newRemoteAlias = ""
        refreshRemoteDevices()
    }

    func removeRemoteDevice(_ id: UUID) {
        remoteDevices.removeAll { $0.id == id }; remoteSnapshots[id] = nil
        eventLedger.recover(key: "remote.\(id.uuidString)", evidence: "设备已从监控中移除")
        timelineEvents = eventLedger.events
    }

    func toggleRemoteProcessOwners(_ id: UUID) {
        guard let index = remoteDevices.firstIndex(where: { $0.id == id }) else { return }
        remoteDevices[index].collectProcessOwners.toggle(); refreshRemoteDevices()
    }

    func toggleRemoteSchedulerJobs(_ id: UUID) {
        guard let index = remoteDevices.firstIndex(where: { $0.id == id }) else { return }
        remoteDevices[index].collectSchedulerJobs.toggle(); refreshRemoteDevices()
    }

    func setRemoteTaskDisclosureMode(_ id: UUID, _ mode: RemoteTaskDisclosureMode) {
        guard let index = remoteDevices.firstIndex(where: { $0.id == id }) else { return }
        remoteDevices[index].taskDisclosureMode = mode
        remoteDevices[index].collectProcessOwners = mode == .redactedCommand
        refreshRemoteDevices()
    }

    func setRemoteNetworkScope(_ id: UUID, _ scope: RemoteNetworkScope) {
        guard let index = remoteDevices.firstIndex(where: { $0.id == id }) else { return }
        remoteDevices[index].networkScope = scope
        remoteFailureStreak[id] = 0
        remoteSnapshots[id] = RemoteDeviceSnapshot(
            id: id,
            health: .waiting,
            checkedAt: Date(),
            message: "正在根据当前网络判断设备可达范围…"
        )
        refreshRemoteDevices()
    }

    func toggleRemotePinned(_ id: UUID) {
        guard let index = remoteDevices.firstIndex(where: { $0.id == id }) else { return }
        remoteDevices[index].pinned.toggle()
        normalizeRemoteOrder()
    }

    func moveRemoteDevice(_ id: UUID, direction: Int) {
        guard let selected = remoteDevices.first(where: { $0.id == id }) else { return }
        var group = orderedRemoteDevices.filter { $0.pinned == selected.pinned }
        guard let index = group.firstIndex(where: { $0.id == id }) else { return }
        let target = index + direction
        guard group.indices.contains(target) else { return }
        group.swapAt(index, target)
        for (order, device) in group.enumerated() {
            if let raw = remoteDevices.firstIndex(where: { $0.id == device.id }) { remoteDevices[raw].sortOrder = order }
        }
    }

    private func normalizeRemoteOrder() {
        for pinned in [true, false] {
            for (order, device) in orderedRemoteDevices.filter({ $0.pinned == pinned }).enumerated() {
                if let raw = remoteDevices.firstIndex(where: { $0.id == device.id }) { remoteDevices[raw].sortOrder = order }
            }
        }
    }

    func observeRemoteDevice(_ id: UUID) {
        remoteObservationUntil[id] = Date().addingTimeInterval(120)
        remoteActionFeedback[id] = "已开启 2 分钟实时观察（每 5 秒刷新）"
        refreshRemoteDevices()
    }

    func refreshRemoteDevices() { Task { [weak self] in await self?.refreshRemoteDevicesAsync(force: true) } }

    func refreshRemoteDevice(_ id: UUID) {
        guard let device = remoteDevices.first(where: { $0.id == id }), !refreshingRemoteDeviceIDs.contains(id) else { return }
        refreshingRemoteDeviceIDs.insert(id)
        remoteActionFeedback[id] = "正在判断设备网络范围…"
        Task { [weak self] in
            guard let self else { return }
            if let reason = await self.remoteScopeUnavailableReason(device) {
                self.remoteSnapshots[id] = RemoteDeviceSnapshot(id: id, health: .expectedOffline, checkedAt: Date(), message: reason)
                self.refreshingRemoteDeviceIDs.remove(id)
                self.remoteFailureStreak[id] = 0
                self.remoteActionFeedback[id] = "当前不在设备网络范围，已暂停探测"
                return
            }
            self.remoteActionFeedback[id] = "正在重新连接 SSH…"
            let snapshot = await self.sshMonitorService.probe(device)
            if let currentDevice = self.remoteDevices.first(where: { $0.id == id }),
               let reason = await self.remoteScopeUnavailableReason(currentDevice) {
                self.remoteSnapshots[id] = RemoteDeviceSnapshot(id: id, health: .expectedOffline, checkedAt: Date(), message: reason)
                self.remoteFailureStreak[id] = 0
            } else {
                self.applyRemoteSnapshot(snapshot)
            }
            self.refreshingRemoteDeviceIDs.remove(id)
            let applied = self.remoteSnapshots[id] ?? snapshot
            self.remoteActionFeedback[id] = applied.health == .expectedOffline
                ? "网络范围已变化，设备探测已暂停"
                : (applied.health == .healthy ? "刷新完成：SSH 与端点正常" : "刷新完成：\(applied.message)")
        }
    }

    func copyRemoteDiagnostic(_ id: UUID) {
        guard let snapshot = remoteSnapshots[id] else { return }
        let text = "[远程设备] \(snapshot.hostName)\n检测：\(snapshot.checkedAt?.formatted(date: .numeric, time: .standard) ?? "--")\nSSH：\(snapshot.latencyMS.map { "\(Int($0)) ms" } ?? "--")\nCodex 发现：\(snapshot.codexDiscoveryDetail)\n端点：\(snapshot.codexEndpointDetail)\n证据：\(snapshot.diagnosticEvidence)"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        remoteActionFeedback[id] = "诊断信息已复制到剪贴板"
    }

    func copyTimelineEvent(_ event: TimelineEvent) {
        let recovered = event.recoveredAt?.formatted(date: .numeric, time: .standard) ?? "尚未恢复"
        let text = "[\(event.category.label)] \(event.title)\n开始：\(event.startedAt.formatted(date: .numeric, time: .standard))\n恢复：\(recovered)\n持续：\(event.durationLabel)\n来源：\(event.source)\n证据：\(event.evidence)"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }

    func clearResolvedTimelineEvents() { eventLedger.clearResolved(); timelineEvents = eventLedger.events }

    func testFeishuAlert() {
        feishuTestStatus = "正在发送测试消息…"
        Task { [weak self] in
            guard let self else { return }
            let result = await self.feishuAlertService.send(webhook: self.feishuWebhook, signingSecret: self.feishuSigningSecret, title: "连接测试", body: "飞书告警连接正常。此消息不包含设备或账户秘密。")
            self.feishuTestStatus = result.evidence
        }
    }

    func addAPIConnector() {
        let name = newAPIConnectorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = newAPIConnectorKind == .cursorLocalUsage ? newAPIConnectorKind.defaultEndpoint : newAPIConnectorEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !newAPIConnectorKind.isBuiltInSingleton,
              (newAPIConnectorKind == .cursorLocalUsage || URL(string: endpoint)?.scheme == "https") else { return }
        let connector = APIConnectorConfiguration(name: name, kind: newAPIConnectorKind, endpoint: endpoint, sortOrder: apiConnectors.count)
        apiConnectors.append(connector)
        if newAPIConnectorKind.requiresAPIKey {
            guard credentialVaultUnlocked else {
                apiConnectorSnapshots[connector.id] = APIConnectorSnapshot(
                    id: connector.id,
                    state: .unavailable,
                    updatedAt: Date(),
                    message: "已添加；请先解锁统一凭据保险库，再填写并保存 API Key"
                )
                newAPIConnectorName = ""; newAPIConnectorEndpoint = ""; newAPIConnectorKey = ""; newAPIConnectorKind = .customRateLimit
                return
            }
            apiConnectorKeyCache[connector.id] = newAPIConnectorKey
            credentialVault[apiCredentialKey(connector.id)] = newAPIConnectorKey
            saveCredentialVault()
        }
        newAPIConnectorName = ""; newAPIConnectorEndpoint = ""; newAPIConnectorKey = ""; newAPIConnectorKind = .customRateLimit
        refreshAPIConnectors()
    }

    func removeAPIConnector(_ id: UUID) {
        guard apiConnectors.first(where: { $0.id == id })?.kind.isBuiltInSingleton != true else { return }
        apiConnectors.removeAll { $0.id == id }; apiConnectorSnapshots[id] = nil
        apiConnectorKeyCache[id] = nil
        if credentialVaultUnlocked {
            credentialVault[apiCredentialKey(id)] = ""
            saveCredentialVault()
        }
    }

    func toggleAPIConnectorPinned(_ id: UUID) {
        guard let index = apiConnectors.firstIndex(where: { $0.id == id }) else { return }
        let willPin = !apiConnectors[index].pinned
        for item in apiConnectors.indices { apiConnectors[item].pinned = false }
        apiConnectors[index].pinned = willPin
        normalizeAPIConnectorOrder()
    }

    func toggleAPIConnectorDashboard(_ id: UUID) {
        guard let index = apiConnectors.firstIndex(where: { $0.id == id }) else { return }
        apiConnectors[index].showOnDashboard.toggle()
    }

    func moveAPIConnector(_ id: UUID, direction: Int) {
        guard let selected = apiConnectors.first(where: { $0.id == id }) else { return }
        var group = orderedAPIConnectors.filter { $0.pinned == selected.pinned }
        guard let index = group.firstIndex(where: { $0.id == id }) else { return }
        let target = index + direction
        guard group.indices.contains(target) else { return }
        group.swapAt(index, target)
        for (order, connector) in group.enumerated() {
            if let raw = apiConnectors.firstIndex(where: { $0.id == connector.id }) { apiConnectors[raw].sortOrder = order }
        }
    }

    private func normalizeAPIConnectorOrder() {
        for pinned in [true, false] {
            for (order, connector) in orderedAPIConnectors.filter({ $0.pinned == pinned }).enumerated() {
                if let raw = apiConnectors.firstIndex(where: { $0.id == connector.id }) { apiConnectors[raw].sortOrder = order }
            }
        }
    }

    func refreshAPIConnectors(unlockCredentials: Bool = false) { Task { [weak self] in await self?.refreshAPIConnectorsAsync(unlockCredentials: unlockCredentials) } }

    func refreshAPIConnector(_ id: UUID) {
        guard credentialVaultUnlocked else { return }
        guard let connector = apiConnectors.first(where: { $0.id == id }) else { return }
        if connector.kind == .codexLocalQuota {
            refreshQuota()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let key: String
            if connector.kind.requiresAPIKey {
                guard let saved = self.apiConnectorKeyCache[id], !saved.isEmpty else {
                    self.apiConnectorSnapshots[id] = self.credentialVaultUnlocked
                        ? APIConnectorSnapshot(id: id, state: .unavailable, updatedAt: Date(), message: "未保存 API Key；填写后点击“保存全部变更")
                        : self.waitingUnlockSnapshot(id: id, previous: self.apiConnectorSnapshots[id])
                    return
                }
                key = saved
            } else {
                key = ""
            }
            let previous = self.apiConnectorSnapshots[id]
            let generation = self.beginAPIConnectorRefresh(id: id)
            let fresh = await self.apiConnectorService.probe(connector, apiKey: key)
            // A lock may happen while this read-only probe is in flight. Its
            // result must never restore a key-backed source to fresh/failed.
            guard self.apiConnectorRefreshGeneration[id] == generation,
                  !connector.kind.requiresAPIKey || self.credentialVaultUnlocked else { return }
            self.applyAPIConnectorRefresh(fresh, previous: previous, connector: connector, generation: generation)
        }
    }

    func exportConfiguration() {
        let bundle = PulseDockConfigurationBundle(
            focusMinutes: focusMinutes, breakMinutes: breakMinutes, longBreakMinutes: longBreakMinutes,
            sessionsBeforeLongBreak: sessionsBeforeLongBreak, workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes, lunchStartMinutes: lunchStartMinutes, lunchEndMinutes: lunchEndMinutes,
            workWeekdays: Array(workWeekdays).sorted(), idleThresholdSeconds: idleThresholdSeconds,
            remoteDevices: remoteDevices, apiConnectors: apiConnectors,
            clashControllerEnabled: clashControllerEnabled, clashControllerURL: clashControllerURL,
            alertCooldownMinutes: alertCooldownMinutes
        )
        let panel = NSSavePanel(); panel.title = "导出 PulseDock 配置"; panel.nameFieldStringValue = "PulseDock-configuration.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? JSONEncoder.pretty.encode(bundle) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func importConfiguration() {
        let panel = NSOpenPanel(); panel.title = "导入 PulseDock 配置"; panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url),
              let bundle = try? JSONDecoder().decode(PulseDockConfigurationBundle.self, from: data), bundle.schemaVersion == 1 else { return }
        focusMinutes = bundle.focusMinutes; breakMinutes = bundle.breakMinutes; longBreakMinutes = bundle.longBreakMinutes
        sessionsBeforeLongBreak = bundle.sessionsBeforeLongBreak; workStartMinutes = bundle.workStartMinutes; workEndMinutes = bundle.workEndMinutes
        lunchStartMinutes = bundle.lunchStartMinutes; lunchEndMinutes = bundle.lunchEndMinutes; workWeekdays = Set(bundle.workWeekdays)
        idleThresholdSeconds = bundle.idleThresholdSeconds
        remoteDevices = Self.sanitizeRemoteConfigurations(bundle.remoteDevices)
        apiConnectors = Self.sanitizeAPIConfigurations(bundle.apiConnectors)
        clashControllerEnabled = bundle.clashControllerEnabled; clashControllerURL = bundle.clashControllerURL
        alertCooldownMinutes = bundle.alertCooldownMinutes
        eventLedger.append(category: .system, severity: .info, title: "配置已导入", evidence: bundle.note, source: "本地 JSON 配置")
        timelineEvents = eventLedger.events; refreshRemoteDevices()
        if credentialVaultUnlocked { refreshAPIConnectors() }
    }

    func chooseClashMetadataFile() {
        let panel = NSOpenPanel()
        panel.title = "选择 Clash 订阅元数据文件"
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "yaml")!]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: PreferenceKey.customClashPath)
        if credentialVaultUnlocked { refreshClashQuota() }
    }

    func togglePomodoro() {
        switch pomodoroPhase {
        case .idle:
            pomodoroPhase = .focus
            pomodoroSecondsRemaining = focusMinutes * 60
            pomodoroDeadline = Date().addingTimeInterval(TimeInterval(pomodoroSecondsRemaining))
            eventLedger.append(category: .pomodoro, severity: .info, title: "番茄钟开始", evidence: "专注 \(focusMinutes) 分钟", source: "PulseDock 番茄钟")
            timelineEvents = eventLedger.events
        case .focus, .breakTime, .longBreak:
            updatePomodoroRemaining()
            phaseBeforePause = pomodoroPhase
            pomodoroPhase = .paused
            pomodoroDeadline = nil
            eventLedger.append(category: .pomodoro, severity: .info, title: "番茄钟暂停", evidence: "剩余 \(pomodoroTimeLabel)", source: "PulseDock 番茄钟")
            timelineEvents = eventLedger.events
        case .paused:
            pomodoroPhase = phaseBeforePause
            pomodoroDeadline = Date().addingTimeInterval(TimeInterval(pomodoroSecondsRemaining))
            eventLedger.append(category: .pomodoro, severity: .info, title: "番茄钟继续", evidence: "剩余 \(pomodoroTimeLabel)", source: "PulseDock 番茄钟")
            timelineEvents = eventLedger.events
        }
    }

    func resetPomodoro() {
        let previous = pomodoroPhase
        pomodoroPhase = .idle
        pomodoroDeadline = nil
        pomodoroSecondsRemaining = focusMinutes * 60
        if previous != .idle {
            eventLedger.append(category: .pomodoro, severity: .info, title: "番茄钟已重置", evidence: "已回到待开始状态", source: "PulseDock 番茄钟")
            timelineEvents = eventLedger.events
        }
    }

    func skipPomodoroPhase() {
        guard pomodoroPhase != .idle else { return }
        skippedToday += 1
        saveDailyStats()
        eventLedger.append(category: .pomodoro, severity: .info, title: "番茄钟已跳过", evidence: "当前阶段：\(pomodoroPhase.label)", source: "PulseDock 番茄钟")
        timelineEvents = eventLedger.events
        if pomodoroPhase == .focus || (pomodoroPhase == .paused && phaseBeforePause == .focus) {
            startBreak(long: false)
        } else {
            resetPomodoro()
        }
    }

    var pomodoroTimeLabel: String { String(format: "%02d:%02d", max(0, pomodoroSecondsRemaining) / 60, max(0, pomodoroSecondsRemaining) % 60) }
    var focusTimeTodayLabel: String { "\(focusSecondsToday / 3_600)小时\((focusSecondsToday % 3_600) / 60)分" }
    var activeTimeTodayLabel: String { "\(activeWorkSecondsToday / 3_600)小时\((activeWorkSecondsToday % 3_600) / 60)分" }
    var topActivity: AppActivityRanking? { activityRankings.first }
    var topActivityCompactLabel: String {
        guard let topActivity else { return "等待统计" }
        return "#1 \(topActivity.name) · \(topActivity.durationLabel)"
    }
    var compactPriority: CompactPriority {
        if let failed = remoteSnapshots.values.first(where: { $0.health == .offline || $0.health == .degraded }),
           let device = remoteDevices.first(where: { $0.id == failed.id }) {
            return CompactPriority(kind: .remote, title: "\(device.name) \(failed.health.label)", detail: failed.message, symbol: "server.rack", color: failed.health.color)
        }
        if thermalRisk.level == .high || thermalRisk.level == .critical {
            return CompactPriority(kind: .thermal, title: thermalRisk.level.label, detail: thermalRisk.evidence, symbol: "thermometer.high", color: thermalRisk.level.color)
        }
        if diagnosticReport.health == .failed || diagnosticReport.health == .degraded {
            return CompactPriority(kind: .network, title: diagnosticReport.health.label, detail: diagnosticReport.summary, symbol: "exclamationmark.triangle.fill", color: diagnosticReport.health.color)
        }
        if health == .offline || health == .degraded {
            let detail = latency.map { "\(Int($0)) ms · \(interfaceLabel)" } ?? interfaceLabel
            return CompactPriority(kind: .network, title: "AI 网络 \(health.label)", detail: detail, symbol: health == .offline ? "wifi.slash" : "wifi.exclamationmark", color: health.color)
        }
        if let remaining = codexQuota.riskRemainingPercent, remaining <= 15 {
            let window = codexQuota.riskWindow.map { "\($0.title) · " } ?? ""
            return CompactPriority(kind: .quota, title: "Codex 额度偏低", detail: "\(window)剩余 \(codexQuota.riskRemainingLabel)", symbol: "gauge.with.dots.needle.33percent", color: .orange)
        }
        if clashQuota.state == .available, clashQuota.remainingPercent <= 10 {
            return CompactPriority(kind: .clash, title: "Clash 流量偏低", detail: "剩余 \(clashQuota.compactLabel)", symbol: "bolt.horizontal.circle.fill", color: .orange)
        }
        if pomodoroPhase != .idle {
            return CompactPriority(kind: .pomodoro, title: pomodoroPhase.label, detail: pomodoroTimeLabel, symbol: "timer", color: pomodoroPhase.color)
        }
        return CompactPriority(kind: .work, title: workStatus.label, detail: topActivityCompactLabel, symbol: workStatus.symbol, color: .secondary)
    }
    var codexFreshnessLabel: String { DataFreshness.label(codexQuota.updatedAt, now: now) }
    var clashFreshnessLabel: String { DataFreshness.label(clashQuota.updatedAt, now: now) }
    var ipFreshnessLabel: String { DataFreshness.label(lastIPUpdate, now: now) }
    var weatherFreshnessLabel: String { DataFreshness.label(weather.updatedAt, now: now) }
    var diagnosticFreshnessLabel: String { DataFreshness.label(diagnosticReport.completedAt, now: now) }

    func performCompactPrimaryAction() {
        switch compactPriority.kind {
        case .network: runAIDiagnostics()
        case .remote: refreshRemoteDevices()
        case .thermal: break
        case .quota: refreshQuota()
        case .clash: refreshClashQuota()
        case .pomodoro: togglePomodoro()
        case .work: break
        }
    }

    func copyDiagnosticReport() {
        let rows = diagnosticReport.checks.map { "[\($0.state.rawValue)] \($0.title)：\($0.detail)" }.joined(separator: "\n")
        let report = "PulseDock AI 网络诊断\n结论：\(diagnosticReport.summary)\n建议：\(diagnosticReport.recommendation)\n完成时间：\(diagnosticReport.completedAt?.formatted(date: .numeric, time: .standard) ?? "未完成")\n\n\(rows)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    func copyIPAddress() {
        guard ip.address != "--" else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip.address, forType: .string)
    }
    var activitySuggestion: String? {
        guard activeApplication.isTrackable, activeApplication.isEngaged,
              [.offWork, .weekendRest, .holidayRest].contains(workStatus) else { return nil }
        return "检测到 \(activeApplication.name) 正在活跃，是否标记为继续工作？"
    }

    func excludeApplication(_ bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty else { return }
        excludedApplicationIDs.insert(bundleIdentifier)
    }

    func restoreApplication(_ bundleIdentifier: String) {
        excludedApplicationIDs.remove(bundleIdentifier)
    }

    func restoreAllExcludedApplications() {
        excludedApplicationIDs.removeAll()
    }

    func excludedApplicationName(_ bundleIdentifier: String) -> String {
        activityTracker.knownName(for: bundleIdentifier)
    }

    private func applySystemMetrics(_ snapshot: SystemMetricsSnapshot) {
        cpuUsage = snapshot.cpuUsage
        memoryUsage = snapshot.memoryUsage
        gpuUsage = snapshot.gpuUsage
        downloadSpeed = snapshot.downloadSpeed
        uploadSpeed = snapshot.uploadSpeed
        temperature = snapshot.temperature
        temperatureSource = snapshot.temperatureSource
        thermalState = snapshot.thermalState
        batteryPercent = snapshot.batteryPercent
        proxyActive = snapshot.proxyActive
        metricsCollectionDurationMilliseconds = snapshot.collectionDurationMilliseconds
        speedHistory.append(SpeedSample(time: snapshot.sampledAt, download: snapshot.downloadSpeed, upload: snapshot.uploadSpeed))
        if speedHistory.count > 60 { speedHistory.removeFirst(speedHistory.count - 60) }
        updateThermalRisk()
    }

    private func runProbe() async {
        guard pathSatisfied else {
            latency = nil; health = .offline
            beginTimeline(key: "network.external", category: .network, severity: .critical, title: "外部网络不可用", evidence: "系统没有可用网络路径", source: "NWPathMonitor")
            return
        }
        let result = await probe.latency(); latency = result.0
        if let error = result.1 {
            health = .degraded
            beginTimeline(key: "network.external", category: .network, severity: .warning, title: error, evidence: "网络路径可用，但外部探测失败", source: "本机网络探测")
            if error != lastError { record(title: error, detail: "网络路径可用，但外部探测失败", severity: .degraded); lastError = error }
        } else {
            let wasUnhealthy = health != .healthy && health != .checking
            health = (result.0 ?? 0) > 600 ? .degraded : .healthy
            if wasUnhealthy { record(title: "网络已恢复", detail: "外部连接探测恢复正常", severity: .healthy) }
            recoverTimeline(key: "network.external", evidence: "外部连接探测恢复正常")
            lastError = nil
        }
        if lastIPUpdate == nil || Date().timeIntervalSince(lastIPUpdate!) > 600 { refreshIP() }
    }

    private func apply(path: NWPath) {
        let wasInitialized = pathInitialized
        let wasSatisfied = pathSatisfied
        pathInitialized = true
        pathSatisfied = path.status == .satisfied
        vpnActive = path.usesInterfaceType(.other) && path.availableInterfaces.contains {
            $0.type == .other && ($0.name.hasPrefix("utun") || $0.name.contains("ipsec"))
        }
        if path.usesInterfaceType(.wifi) { interfaceLabel = "Wi‑Fi" }
        else if path.usesInterfaceType(.wiredEthernet) { interfaceLabel = "以太网" }
        else if path.usesInterfaceType(.cellular) { interfaceLabel = "蜂窝网络" }
        else if pathSatisfied { interfaceLabel = vpnActive ? "VPN 隧道" : "其他网络" }
        else { interfaceLabel = "无网络" }
        // A callback can represent a new route even when both paths say
        // "Wi-Fi". Suppress SSH alerts briefly after every subsequent
        // satisfied path update rather than comparing only the display label.
        if wasInitialized, pathSatisfied {
            remoteNetworkGraceUntil = Date().addingTimeInterval(90)
            refreshRemoteDevices()
        }
        if !pathSatisfied {
            health = .offline; latency = nil
            if wasSatisfied { record(title: "网络已断开", detail: "系统没有可用的网络路径", severity: .offline) }
        } else {
            if !wasSatisfied { record(title: "网络路径可用", detail: "已连接至\(interfaceLabel)", severity: .healthy); refreshIP() }
            if health == .offline { health = .checking }
            if !wasInitialized || !wasSatisfied { refreshRemoteDevices() }
        }
    }

    private func record(title: String, detail: String, severity: ConnectionHealth) {
        events.insert(DiagnosticEvent(time: Date(), title: title, detail: detail, severity: severity), at: 0)
        if events.count > 30 { events.removeLast(events.count - 30) }
        let timelineSeverity: TimelineSeverity = switch severity {
        case .healthy, .checking: .info
        case .degraded: .warning
        case .offline: .critical
        }
        eventLedger.append(category: .system, severity: timelineSeverity, title: title, evidence: detail, source: "PulseDock 本机状态")
        timelineEvents = eventLedger.events
    }

    private func beginTimeline(key: String, category: TimelineCategory, severity: TimelineSeverity, title: String, evidence: String, source: String) {
        let isNew = !eventLedger.events.contains { $0.key == key && $0.recoveredAt == nil }
        eventLedger.beginOrUpdate(key: key, category: category, severity: severity, title: title, evidence: evidence, source: source)
        timelineEvents = eventLedger.events
        if isNew, severity == .warning || severity == .critical { deliverAlert(key: key, title: title, body: "\(evidence)\n来源：\(source)") }
    }

    private func recoverTimeline(key: String, evidence: String) {
        let active = eventLedger.events.first { $0.key == key && $0.recoveredAt == nil }
        eventLedger.recover(key: key, evidence: evidence); timelineEvents = eventLedger.events
        if let active { deliverAlert(key: "\(key).recovered", title: "已恢复：\(active.title)", body: "\(evidence)\n持续：\(active.durationLabel)") }
    }

    private func deliverAlert(key: String, title: String, body: String) {
        guard feishuAlertsEnabled, !feishuWebhook.isEmpty else { return }
        let date = Date(); let cooldown = TimeInterval(alertCooldownMinutes * 60)
        guard lastAlertAt[key].map({ date.timeIntervalSince($0) >= cooldown }) ?? true else { return }
        lastAlertAt[key] = date
        Task { [weak self] in
            guard let self else { return }
            let result = await self.feishuAlertService.send(webhook: self.feishuWebhook, signingSecret: self.feishuSigningSecret, title: title, body: body)
            if !result.success { self.feishuTestStatus = "最近发送失败：\(result.evidence)" }
        }
    }

    private func evaluateQuotaState() {
        if let remaining = codexQuota.riskRemainingPercent, remaining <= 15 {
            let window = codexQuota.riskWindow?.title ?? "当前窗口"
            beginTimeline(key: "quota.codex.low", category: .quota, severity: remaining <= 5 ? .critical : .warning, title: "Codex 额度偏低", evidence: "官方 app-server 返回 \(window) 剩余 \(codexQuota.riskRemainingLabel)", source: "Codex 官方本地接口")
        } else if codexQuota.state == .available { recoverTimeline(key: "quota.codex.low", evidence: "额度恢复到安全范围") }
    }

    private func updateThermalRisk() {
        guard let temperature else { return }
        let date = Date(); let load = max(cpuUsage, gpuUsage)
        thermalSamples.append((date, temperature, load))
        thermalSamples.removeAll { date.timeIntervalSince($0.date) > 600 }
        let old = thermalRisk.level
        let first = thermalSamples.first
        let minutes = max(0.1, first.map { date.timeIntervalSince($0.date) / 60 } ?? 0.1)
        let trend = first.map { (temperature - $0.temperature) / minutes } ?? 0
        let sustained = load >= 65 ? thermalRisk.sustainedHighLoadSeconds + 2 : 0
        let systemState = ProcessInfo.processInfo.thermalState
        let level: ThermalRiskLevel
        if systemState == .critical || systemState == .serious || temperature >= 95 { level = .critical }
        else if temperature >= 85 && sustained >= 120 { level = .high }
        else if (trend >= 0.5 && sustained >= 60) || temperature >= 78 { level = .rising }
        else { level = .normal }
        let evidence = String(format: "%.0f°C · 趋势 %+.1f°C/分钟 · 高负载 %d 分钟", temperature, trend, sustained / 60)
        thermalRisk = ThermalRiskSnapshot(level: level, trendCelsiusPerMinute: trend, sustainedHighLoadSeconds: sustained, evidence: evidence, updatedAt: date)
        if level == .high || level == .critical {
            beginTimeline(key: "thermal.local", category: .thermal, severity: level == .critical ? .critical : .warning, title: level.label, evidence: evidence, source: "macOS 热状态 + 本机传感器（风险估算）")
        } else if old == .high || old == .critical { recoverTimeline(key: "thermal.local", evidence: evidence) }
    }

    private func refreshRemoteDevicesAsync(force: Bool = false) async {
        guard !isRefreshingRemoteDevices else { return }
        let now = Date()
        let candidates = remoteDevices.filter { device in
            guard device.enabled, !refreshingRemoteDeviceIDs.contains(device.id) else { return false }
            if force { return true }
            let interval = remoteObservationUntil[device.id].map { $0 > now } == true ? 5 : max(15, device.intervalSeconds)
            return now.timeIntervalSince(lastRemoteProbeAt[device.id] ?? .distantPast) >= Double(interval)
        }
        var unavailableReasons: [UUID: String] = [:]
        for device in candidates {
            if let reason = await remoteScopeUnavailableReason(device) {
                unavailableReasons[device.id] = reason
                remoteSnapshots[device.id] = RemoteDeviceSnapshot(
                    id: device.id, health: .expectedOffline, checkedAt: now,
                    message: reason
                )
                lastRemoteProbeAt[device.id] = now
                remoteFailureStreak[device.id] = 0
                // A paused probe is not evidence that an existing SSH incident
                // recovered. Only a later healthy snapshot may close it.
            }
        }
        let enabled = candidates.filter { unavailableReasons[$0.id] == nil }
        guard !enabled.isEmpty else { return }
        isRefreshingRemoteDevices = true
        refreshingRemoteDeviceIDs.formUnion(enabled.map(\.id))
        // Bound SSH subprocesses to three at a time. A large device list must
        // not create a burst of processes, sockets and password-agent prompts.
        for start in stride(from: 0, to: enabled.count, by: 3) {
            let chunk = Array(enabled[start..<min(start + 3, enabled.count)])
            await withTaskGroup(of: RemoteDeviceSnapshot.self) { group in
                for device in chunk {
                    group.addTask { await self.sshMonitorService.probe(device) }
                }
                for await snapshot in group {
                    if let currentDevice = remoteDevices.first(where: { $0.id == snapshot.id }),
                       let reason = await remoteScopeUnavailableReason(currentDevice) {
                        remoteSnapshots[snapshot.id] = RemoteDeviceSnapshot(
                            id: snapshot.id, health: .expectedOffline, checkedAt: Date(), message: reason
                        )
                        remoteFailureStreak[snapshot.id] = 0
                    } else {
                        applyRemoteSnapshot(snapshot)
                    }
                    refreshingRemoteDeviceIDs.remove(snapshot.id)
                }
            }
        }
        isRefreshingRemoteDevices = false
    }

    private func remoteScopeUnavailableReason(_ device: RemoteDeviceConfiguration) async -> String? {
        guard pathSatisfied else { return "系统当前无可用网络，已暂停 SSH 探测与告警" }
        switch device.networkScope {
        case .automatic, .publicInternet:
            return nil
        case .localLAN:
            guard interfaceLabel == "Wi‑Fi" || interfaceLabel == "以太网" else {
                return "设备标记为局域网；当前使用 \(interfaceLabel)，已暂停 SSH 探测与告警"
            }
            let assessment = await remoteNetworkScopeService.assessLocalLAN(alias: device.sshAlias)
            return assessment.shouldProbe ? nil : assessment.message
        case .vpn:
            return vpnActive ? nil : "设备需要 VPN；当前 VPN 未连接，已暂停探测与飞书告警"
        }
    }

    private func applyRemoteSnapshot(_ snapshot: RemoteDeviceSnapshot) {
        var merged = snapshot
        if snapshot.health == .degraded, snapshot.gpus.isEmpty, let previous = remoteSnapshots[snapshot.id], !previous.gpus.isEmpty {
            merged.gpus = previous.gpus
            let cacheTime = previous.checkedAt?.formatted(date: .numeric, time: .standard) ?? "未知时间"
            merged.diagnosticEvidence += "\nGPU 显存暂用上次成功数据（\(cacheTime)），任务列表不沿用，避免把已结束任务显示为仍在运行。"
        }
        remoteSnapshots[merged.id] = merged
        lastRemoteProbeAt[merged.id] = merged.checkedAt ?? Date()
        let name = remoteDevices.first(where: { $0.id == merged.id })?.name ?? merged.hostName
        let key = "remote.\(merged.id.uuidString)"
        if merged.health == .offline || merged.health == .degraded {
            let streak = (remoteFailureStreak[merged.id] ?? 0) + 1
            remoteFailureStreak[merged.id] = streak
            let inGrace = remoteNetworkGraceUntil.map { Date() < $0 } == true
            if streak >= 3, !inGrace {
                beginTimeline(key: key, category: .remote, severity: merged.health == .offline ? .critical : .warning, title: "\(name) \(merged.health.label)", evidence: "连续 \(streak) 次失败：\(merged.message)", source: "SSH 只读探测")
            }
        } else if merged.health == .healthy {
            remoteFailureStreak[merged.id] = 0
            recoverTimeline(key: key, evidence: "SSH 与关键探测恢复正常")
        }
    }

    private func refreshAPIConnectorsAsync(unlockCredentials: Bool = false) async {
        guard credentialVaultUnlocked, !isRefreshingAPIConnectors else { return }
        let enabled = apiConnectors.filter(\.enabled)
        guard !enabled.isEmpty else { return }
        isRefreshingAPIConnectors = true
        await withTaskGroup(of: (APIConnectorSnapshot, Int, APIConnectorSnapshot?).self) { group in
            for connector in enabled {
                if connector.kind == .codexLocalQuota {
                    // Codex is adapted from the single existing official
                    // local reader. Never route it through APIConnectorService.
                    refreshQuota()
                    continue
                }
                let key: String
                if !connector.kind.requiresAPIKey {
                    // Cursor reads its own local session and must never be blocked
                    // by PulseDock's Keychain vault.
                    key = ""
                } else if let cached = apiConnectorKeyCache[connector.id] {
                    key = cached
                } else {
                    apiConnectorSnapshots[connector.id] = credentialVaultUnlocked
                        ? APIConnectorSnapshot(id: connector.id, state: .unavailable, updatedAt: Date(), message: "未保存 API Key；在统一凭据保险库解锁后重新填写并保存")
                        : waitingUnlockSnapshot(id: connector.id, previous: apiConnectorSnapshots[connector.id])
                    continue
                }
                let previous = apiConnectorSnapshots[connector.id]
                let generation = beginAPIConnectorRefresh(id: connector.id)
                group.addTask { (await self.apiConnectorService.probe(connector, apiKey: key), generation, previous) }
            }
            for await (snapshot, generation, previous) in group {
                guard let connector = apiConnectors.first(where: { $0.id == snapshot.id }),
                      apiConnectorRefreshGeneration[snapshot.id] == generation,
                      !connector.kind.requiresAPIKey || credentialVaultUnlocked else { continue }
                applyAPIConnectorRefresh(snapshot, previous: previous, connector: connector, generation: generation)
            }
        }
        isRefreshingAPIConnectors = false
    }

    private func applyAPIConnectorRefresh(_ fresh: APIConnectorSnapshot, previous: APIConnectorSnapshot?, connector: APIConnectorConfiguration, generation: Int) {
        guard apiConnectorRefreshGeneration[connector.id] == generation,
              !connector.kind.requiresAPIKey || credentialVaultUnlocked else { return }
        if fresh.state == .available {
            var current = fresh
            current.refresh = .fresh(at: fresh.updatedAt ?? Date())
            apiConnectorSnapshots[connector.id] = current
            apiConnectorRetryTasks[connector.id]?.cancel()
            apiConnectorRetryTasks[connector.id] = nil
            return
        }

        let failures = (previous?.refresh.failureCount ?? 0) + 1
        var retained = fresh
        if let previous, retained.copyDisplayPayload(from: previous) {
            retained.refresh = RefreshMetadata(
                status: .stale,
                lastSuccessAt: previous.refresh.lastSuccessAt ?? previous.updatedAt,
                lastFailureAt: Date(),
                failureMessage: fresh.message,
                failureCount: failures
            )
        } else {
            retained.refresh = RefreshMetadata(
                status: .initialFailure,
                lastFailureAt: Date(),
                failureMessage: fresh.message,
                failureCount: failures
            )
        }
        apiConnectorSnapshots[connector.id] = retained
        guard isRetryableConnectorFailure(fresh, connector: connector) else { return }
        scheduleAPIConnectorRetry(connector, afterFailureCount: failures, generation: generation)
    }

    private func isRetryableConnectorFailure(_ snapshot: APIConnectorSnapshot, connector: APIConnectorConfiguration) -> Bool {
        guard connector.enabled else { return false }
        let nonRetryable = ["未保存 API Key", "请填写", "仅允许 HTTPS", "仅允许 open.bigmodel.cn", "仅允许 api.deepseek.com"]
        return !nonRetryable.contains { snapshot.message.contains($0) }
    }

    private func scheduleAPIConnectorRetry(_ connector: APIConnectorConfiguration, afterFailureCount failures: Int, generation: Int) {
        apiConnectorRetryTasks[connector.id]?.cancel()
        let delay = RetryPolicy.delay(forFailureCount: failures)
        apiConnectorSnapshots[connector.id]?.refresh.nextRetryAt = Date().addingTimeInterval(delay)
        let accessGeneration = quotaAccessGeneration
        apiConnectorRetryTasks[connector.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self,
                  self.credentialVaultUnlocked,
                  self.quotaAccessGeneration == accessGeneration,
                  self.apiConnectorRefreshGeneration[connector.id] == generation else { return }
            self.refreshAPIConnector(connector.id)
        }
    }

    private func waitingUnlockSnapshot(id: UUID, previous: APIConnectorSnapshot?) -> APIConnectorSnapshot {
        var waiting = APIConnectorSnapshot(id: id, state: .waitingUnlock, message: "等待解锁凭据保险库；未发起网络请求")
        waiting.refresh = .waitingUnlock
        if let previous, waiting.copyDisplayPayload(from: previous) {
            waiting.message = "等待解锁凭据保险库；显示上次成功快照"
            waiting.refresh = previous.refresh
            waiting.refresh.status = .waitingUnlock
        }
        return waiting
    }

    private func beginAPIConnectorRefresh(id: UUID) -> Int {
        let generation = apiConnectorRefreshGeneration[id, default: 0] + 1
        apiConnectorRefreshGeneration[id] = generation
        var loading = APIConnectorSnapshot(id: id, state: .loading, message: "正在刷新…")
        if let previous = apiConnectorSnapshots[id], loading.copyDisplayPayload(from: previous) {
            loading.message = "正在刷新 · 显示上次成功快照"
            loading.refresh = previous.refresh
            loading.refresh.status = .refreshing
        } else {
            loading.refresh.status = .refreshing
        }
        apiConnectorSnapshots[id] = loading
        return generation
    }

    private func refreshClashQuotaAsync(expectedGeneration: Int? = nil) async {
        guard credentialVaultUnlocked else { return }
        let generation = expectedGeneration ?? quotaAccessGeneration
        let custom = UserDefaults.standard.string(forKey: PreferenceKey.customClashPath).map { URL(fileURLWithPath: $0) }
        let local = await clashService.discover(customURL: custom)
        let live = clashControllerEnabled ? await clashControllerService.providerUsage(baseURL: clashControllerURL, secret: clashControllerSecret) : []
        guard credentialVaultUnlocked, generation == quotaAccessGeneration else { return }
        var merged = live
        var knownNames = Set(live.map { $0.name })
        merged.append(contentsOf: local.filter { knownNames.insert($0.name).inserted })
        clashSubscriptions = merged
        applySelectedClash()
    }

    private func applySelectedClash() {
        guard credentialVaultUnlocked else {
            clashQuota = .locked
            return
        }
        if let selected = clashSubscriptions.first(where: { $0.identifier == selectedClashIdentifier }) { clashQuota = selected }
        else if let first = clashSubscriptions.first { clashQuota = first; selectedClashIdentifier = first.identifier }
        else { clashQuota = ClashQuotaService.parse(url: ClashQuotaService.profilesURL) }
        if clashQuota.state == .available, clashQuota.remainingPercent <= 10 {
            beginTimeline(key: "clash.quota.low", category: .clash, severity: clashQuota.remainingPercent <= 3 ? .critical : .warning, title: "Clash 流量偏低", evidence: "\(clashQuota.name) 剩余 \(clashQuota.compactLabel)，数据时间 \(clashFreshnessLabel)", source: "\(clashQuota.sourceApp) 本地订阅元数据")
        } else if clashQuota.state == .available { recoverTimeline(key: "clash.quota.low", evidence: "流量恢复到安全范围") }
    }

    private func tickClock() {
        now = Date()
        mainThreadResponsiveness = mainThreadResponsivenessMonitor.snapshot()
        resetDailyStateIfNeeded()
        activeApplication = ActiveApplicationMonitor.snapshot(idleThreshold: Double(idleThresholdSeconds), sessionActive: sessionActive)
        activityTracker.sample(activeApplication, at: now, excluded: excludedApplicationIDs)
        refreshActivityRankings()
        updateWorkStatus()
        guard [.focus, .breakTime, .longBreak].contains(pomodoroPhase) else {
            if Int(now.timeIntervalSince1970) % 30 == 0 { saveDailyStats(); activityTracker.save() }
            return
        }
        if pomodoroPhase == .focus { focusSecondsToday += 1 }
        let overdue = pomodoroDeadline.map { max(0, -$0.timeIntervalSinceNow) } ?? 0
        updatePomodoroRemaining()
        if pomodoroSecondsRemaining <= 0 { completePomodoroPhase(overdueSeconds: overdue) }
        if Int(now.timeIntervalSince1970) % 30 == 0 { saveDailyStats(); activityTracker.save() }
    }

    private func updatePomodoroRemaining() {
        guard let deadline = pomodoroDeadline else { return }
        pomodoroSecondsRemaining = PomodoroTimeLogic.remainingSeconds(deadline: deadline)
    }

    private func completePomodoroPhase(overdueSeconds: TimeInterval = 0) {
        if pomodoroPhase == .focus {
            completedFocusToday += 1
            let useLongBreak = completedFocusToday % max(1, sessionsBeforeLongBreak) == 0
            let breakSeconds = (useLongBreak ? longBreakMinutes : breakMinutes) * 60
            if overdueSeconds >= TimeInterval(breakSeconds) {
                resetPomodoro()
                PulseDockNotifications.send(title: "本轮计时已结束", body: "专注和休息已在 Mac 睡眠期间完成。")
                record(title: "番茄钟睡眠校正", detail: "专注和休息阶段均已结束", severity: .healthy)
            } else {
                startBreak(long: useLongBreak, remainingSeconds: breakSeconds - Int(overdueSeconds))
                PulseDockNotifications.send(title: "专注完成", body: useLongBreak ? "完成 \(completedFocusToday) 轮，进入长休息。" : "完成一轮专注，现在休息一下。")
                record(title: "番茄钟专注完成", detail: useLongBreak ? "已进入长休息" : "已进入短休息", severity: .healthy)
            }
        } else {
            resetPomodoro()
            PulseDockNotifications.send(title: "休息结束", body: "下一轮专注已经准备好。")
        }
        saveDailyStats()
    }

    private func startBreak(long: Bool, remainingSeconds: Int? = nil) {
        pomodoroPhase = long ? .longBreak : .breakTime
        pomodoroSecondsRemaining = remainingSeconds ?? (long ? longBreakMinutes : breakMinutes) * 60
        pomodoroDeadline = Date().addingTimeInterval(TimeInterval(pomodoroSecondsRemaining))
    }

    private func updateWorkStatus(notify: Bool = true) {
        let minute = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        let effectiveDate = workEndMinutes <= workStartMinutes && minute < workEndMinutes
            ? (Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
            : now
        let holiday = ChinaHolidayCalendar.dayInfo(for: effectiveDate)
        let next = WorkScheduleLogic.status(
            date: now, startMinutes: workStartMinutes, endMinutes: workEndMinutes,
            lunchStartMinutes: lunchStartMinutes, lunchEndMinutes: lunchEndMinutes,
            workWeekdays: workWeekdays, holidayKind: holiday.kind,
            manualDayOverride: manualDayOverride, overtimeActive: overtimeActive
        )
        guard next != workStatus || previousWorkStatus == nil else { return }
        let old = previousWorkStatus; workStatus = next; previousWorkStatus = next
        guard notify, old != nil else { return }
        switch next {
        case .offWork:
            PulseDockNotifications.send(title: "下班时间到了", body: "今天辛苦了，记得结束工作并休息。")
            record(title: "已到下班时间", detail: "工作状态已切换为下班", severity: .healthy)
        case .overtime: PulseDockNotifications.send(title: "正在加班", body: "已经超过设定下班时间，注意安排休息。")
        case .weekendOvertime, .holidayWork: PulseDockNotifications.send(title: next.label, body: "今天不是常规工作日，记得为自己保留休息时间。")
        default: break
        }
    }

    private func resetDailyStateIfNeeded() {
        let key = ChinaHolidayCalendar.dateKey(now)
        guard key != currentDayKey else { return }
        currentDayKey = key
        overtimeActive = false; manualDayOverride = 0
        completedFocusToday = 0; skippedToday = 0; focusSecondsToday = 0; activeWorkSecondsToday = 0
        saveDailyStats(); persistProductivitySettings()
    }

    private func persistProductivitySettings() {
        let defaults = UserDefaults.standard
        defaults.set(focusMinutes, forKey: PreferenceKey.focusMinutes); defaults.set(breakMinutes, forKey: PreferenceKey.breakMinutes)
        defaults.set(longBreakMinutes, forKey: PreferenceKey.longBreakMinutes); defaults.set(sessionsBeforeLongBreak, forKey: PreferenceKey.sessionsBeforeLongBreak)
        defaults.set(workStartMinutes, forKey: PreferenceKey.workStart); defaults.set(workEndMinutes, forKey: PreferenceKey.workEnd)
        defaults.set(lunchStartMinutes, forKey: PreferenceKey.lunchStart); defaults.set(lunchEndMinutes, forKey: PreferenceKey.lunchEnd)
        defaults.set(Array(workWeekdays).sorted(), forKey: PreferenceKey.workWeekdays)
        defaults.set(manualDayOverride, forKey: PreferenceKey.dayOverride); defaults.set(currentDayKey, forKey: PreferenceKey.dayOverrideDate)
        defaults.set(overtimeActive, forKey: PreferenceKey.overtime); defaults.set(currentDayKey, forKey: PreferenceKey.overtimeDate)
        defaults.set(includeBrowsers, forKey: PreferenceKey.includeBrowsers); defaults.set(includeCommunication, forKey: PreferenceKey.includeCommunication)
        defaults.set(idleThresholdSeconds, forKey: PreferenceKey.idleThreshold)
        defaults.set(Array(excludedApplicationIDs).sorted(), forKey: PreferenceKey.excludedApplications)
    }

    private func saveDailyStats() {
        let defaults = UserDefaults.standard
        defaults.set(currentDayKey, forKey: PreferenceKey.statsDate)
        defaults.set(completedFocusToday, forKey: PreferenceKey.completed); defaults.set(skippedToday, forKey: PreferenceKey.skipped)
        defaults.set(focusSecondsToday, forKey: PreferenceKey.focusSeconds); defaults.set(activeWorkSecondsToday, forKey: PreferenceKey.activeSeconds)
    }

    private func persistWeatherLocation() {
        let defaults = UserDefaults.standard
        if let weatherLocation, let data = try? JSONEncoder().encode(weatherLocation) {
            defaults.set(data, forKey: PreferenceKey.weatherLocation)
        } else {
            defaults.removeObject(forKey: PreferenceKey.weatherLocation)
        }
    }

    private func persistRemoteDevices() {
        if let data = try? JSONEncoder().encode(remoteDevices) { UserDefaults.standard.set(data, forKey: PreferenceKey.remoteDevices) }
    }

    private func persistAPIConnectors() {
        if let data = try? JSONEncoder().encode(apiConnectors) { UserDefaults.standard.set(data, forKey: PreferenceKey.apiConnectors) }
    }

    private static func sanitizeRemoteConfigurations(_ values: [RemoteDeviceConfiguration]) -> [RemoteDeviceConfiguration] {
        var seen = Set<UUID>()
        return values.enumerated().map { offset, raw in
            var value = raw
            if !seen.insert(value.id).inserted {
                value.id = UUID()
                seen.insert(value.id)
            }
            if value.sortOrder < 0 { value.sortOrder = offset }
            value.intervalSeconds = max(15, min(3_600, value.intervalSeconds))
            return value
        }
    }

    private static func sanitizeAPIConfigurations(_ values: [APIConnectorConfiguration]) -> [APIConnectorConfiguration] {
        APIConnectorConfiguration.sanitizeForStorage(values)
    }

    private func resetPomodoroIfIdle() { if pomodoroPhase == .idle { pomodoroSecondsRemaining = focusMinutes * 60 } }

    private func observeWorkspaceSession() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let inactiveNames: [Notification.Name] = [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification]
        let activeNames: [Notification.Name] = [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification]
        workspaceObservers += inactiveNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sessionActive = false }
            }
        }
        workspaceObservers += activeNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sessionActive = true }
            }
        }
    }

    private func refreshActivityRankings() {
        activityRankings = activityTracker.rankings(days: activityRangeDays, endingAt: now, excluded: excludedApplicationIDs)
        activeWorkSecondsToday = activityTracker.rankings(days: 1, endingAt: now, excluded: excludedApplicationIDs)
            .reduce(0) { $0 + $1.engagedSeconds }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; return encoder }
}
