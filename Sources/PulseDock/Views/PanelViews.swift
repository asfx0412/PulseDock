import AppKit
import Charts
import SwiftUI

struct RootPanelView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var state: PanelState

    var body: some View {
        Group {
            if state.expanded {
                ExpandedPanel(store: store, state: state)
            } else {
                CompactPanel(store: store, state: state)
            }
        }
        .background {
            ZStack {
                state.panelBackground.opacity(0.92)
                Rectangle().fill(.ultraThinMaterial).opacity(0.58)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: state.expanded ? 24 : 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: state.expanded ? 24 : 20).stroke(state.panelAccent.opacity(0.26), lineWidth: 1) }
        .tint(state.panelAccent)
        .environment(\.locale, Locale(identifier: state.appLanguage.rawValue))
        .preferredColorScheme(state.isPanelDark ? .dark : nil)
        .contextMenu {
            Toggle("只在当前桌面显示（关闭则所有桌面）", isOn: $state.currentDesktopOnly)
            Menu("透明度") {
                opacityPreset("40%", 0.40); opacityPreset("60%", 0.60); opacityPreset("80%", 0.80)
                opacityPreset("92%", 0.92); opacityPreset("100%", 1.00)
            }
            Divider()
            Button("修复菜单栏入口", systemImage: "wrench.and.screwdriver") { state.requestMenuBarRepair() }
            Button("收起到菜单栏", systemImage: "menubar.rectangle") { state.requestMinimizeToMenuBar() }
            Button("收起到程序坞", systemImage: "dock.rectangle") { state.requestMinimizeToDock() }
            Button("退出 PulseDock", systemImage: "power", role: .destructive) { NSApp.terminate(nil) }
        }
    }

    private func opacityPreset(_ label: String, _ value: Double) -> some View {
        Button { state.opacity = value } label: {
            if abs(state.opacity - value) < 0.01 { Label(label, systemImage: "checkmark") } else { Text(label) }
        }
    }
}

private struct CompactPanel: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var state: PanelState

    var body: some View {
        VStack(spacing: state.compactDensity == .minimal ? 0 : 6) {
            HStack(spacing: 9) {
                PanelDragHandle(onDoubleClick: { state.expanded = true })
                    .frame(width: 22, height: 30)
                    .overlay { Image(systemName: "hand.draw.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).allowsHitTesting(false) }
                    .help("按住后拖动浮窗；双击展开")
                ZStack {
                    Circle().fill(store.workStatus.color.opacity(0.16)).frame(width: 31, height: 31)
                    Image(systemName: store.workStatus.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(store.workStatus.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.workStatus.label).font(.system(size: 11, weight: .bold))
                    Text(store.topActivityCompactLabel).font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: store.performCompactPrimaryAction) {
                    HStack(spacing: 4) {
                        Image(systemName: store.compactPriority.symbol).font(.system(size: 9, weight: .bold))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.compactPriority.title).font(.system(size: 9, weight: .bold)).lineLimit(1)
                            if state.compactDensity == .minimal {
                                Text(store.compactPriority.detail).font(.system(size: 7.5)).lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(store.compactPriority.color)
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(store.compactPriority.color.opacity(store.compactPriority.kind == .work ? 0.08 : 0.14), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(primaryActionHint)
                Button { state.expanded = true } label: { Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if state.compactDensity == .balanced {
                HStack(spacing: 5) {
                    CompactChip(icon: "timer", value: store.pomodoroPhase == .idle ? "\(store.completedFocusToday) 轮" : store.pomodoroTimeLabel, tint: store.pomodoroPhase == .idle ? .secondary : store.pomodoroPhase.color)
                    if let quota = store.compactPinnedQuotaPresentation {
                        CompactChip(icon: "gauge.with.dots.needle.67percent", value: quota.value, tint: quota.color)
                            .help("\(quota.title) · \(quota.detail)")
                    }
                    if store.credentialVaultUnlocked {
                        CompactChip(icon: "bolt.horizontal.circle", value: store.clashQuota.compactLabel, tint: store.clashQuota.remainingPercent <= 10 ? .orange : .green)
                            .help("Clash 剩余额度 · \(store.clashQuota.message)")
                    }
                    CompactChip(icon: store.weather.symbol, value: store.weather.temperatureLabel, tint: .secondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(width: state.compactSize.width, height: state.compactSize.height)
    }

    private var primaryActionHint: String {
        switch store.compactPriority.kind {
        case .network: "点击执行 AI 网络诊断"
        case .remote: "点击立即刷新远程设备"
        case .thermal: "双击查看热风险证据"
        case .quota: "点击刷新 Codex 额度"
        case .clash: "点击刷新 Clash 流量"
        case .pomodoro: "点击暂停或继续番茄钟"
        case .work: "双击浮窗查看完整工作状态"
        }
    }
}

private struct CompactChip: View {
    let icon: String
    let value: String
    let tint: Color
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 7.5, weight: .semibold))
            Text(value).font(.system(size: 8.5, weight: .bold, design: .rounded)).lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }
}

private struct ExpandedPanel: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var state: PanelState
    @State private var tab = 0
    @State private var pendingExclusion: AppActivityRanking?
    @State private var expandedRemoteIDs: Set<UUID> = []
    @State private var settingsRemoteID: UUID?
    @State private var timelineVisibleLimit = 60
    @State private var selectedCodexUsageDate: Date?
    @State private var holidayCalendarPresented = false
    @State private var activityRanksExpanded = false
    @State private var activityRanksInteractionGeneration = 0

    var body: some View {
        VStack(spacing: 10) {
            header
            Picker("页面", selection: $tab) {
                Text("工作台").tag(0); Text("洞察").tag(1); Text("设备").tag(2)
                Text("时间线").tag(3); Text("诊断").tag(4); Text("设置").tag(5); Text("声音").tag(6)
            }
            .pickerStyle(.segmented).labelsHidden()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if tab == 0 { dashboard }
                    else if tab == 1 { insights }
                    else if tab == 2 { devices }
                    else if tab == 3 { timeline }
                    else if tab == 4 { diagnostics }
                    else if tab == 5 { settings }
                    else { sounds }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(15)
        .frame(maxWidth: 500)
        .frame(maxHeight: .infinity)
        .confirmationDialog(
            "要从统计中排除 \(pendingExclusion?.name ?? "这个应用")吗？",
            isPresented: Binding(
                get: { pendingExclusion != nil },
                set: { if !$0 { pendingExclusion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("排除应用", role: .destructive) {
                if let pendingExclusion { store.excludeApplication(pendingExclusion.bundleIdentifier) }
                pendingExclusion = nil
            }
            Button("取消", role: .cancel) { pendingExclusion = nil }
        } message: {
            Text("历史数据不会删除，可随时在设置中恢复。")
        }
    }

    private var header: some View {
        HStack {
            PanelDragHandle(onDoubleClick: { state.expanded = false })
                .frame(width: 22, height: 30)
                .overlay { Image(systemName: "hand.draw.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).allowsHitTesting(false) }
                .help("按住后拖动浮窗；双击收起")
            Image(systemName: "sparkles.rectangle.stack.fill").foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text("PulseDock").font(.system(size: 15, weight: .bold, design: .rounded))
                HStack(spacing: 5) {
                    Text("AI 开发者工作状态")
                    Text("v\(appVersion)")
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.055), in: Capsule())
                        .accessibilityLabel("PulseDock 版本 \(appVersion)")
                }
                .font(.system(size: 8.5)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .help("双击这里收起为浮窗")
            Spacer()
            Text(store.now, style: .time).font(.system(size: 12, weight: .semibold, design: .rounded))
            Menu {
                Button("修复菜单栏入口") { state.requestMenuBarRepair() }
                Button("收起到菜单栏") { state.requestMinimizeToMenuBar() }
                Button("收起到程序坞") { state.requestMinimizeToDock() }
            } label: { Image(systemName: "minus") }.menuStyle(.borderlessButton).fixedSize()
            Button("收起") { state.expanded = false }.controlSize(.mini)
        }
        .padding(.top, 2)
        .contentShape(Rectangle())
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    private var dashboard: some View {
        VStack(spacing: 11) {
            Card {
                VStack(spacing: 10) {
                    HStack {
                        Label(store.workStatus.label, systemImage: store.workStatus.symbol)
                            .font(.system(size: 15, weight: .bold)).foregroundStyle(store.workStatus.color)
                        if let holiday = ChinaHolidayCalendar.dayInfo(for: store.now).name { Badge(text: holiday, color: .red) }
                        Spacer()
                        Toggle("继续工作", isOn: $store.overtimeActive).toggleStyle(.switch).controlSize(.mini).font(.system(size: 9))
                    }
                    HStack {
                        Image(systemName: "app.fill").foregroundStyle(.secondary)
                        Text(store.activeApplication.label).font(.system(size: 10, weight: .medium))
                        Spacer()
                        Text("今日有效 \(store.activeTimeTodayLabel)").font(.system(size: 8.5)).foregroundStyle(.secondary)
                    }
                    if let top = store.topActivity {
                        HStack {
                            Label("今日 #1 \(top.name)", systemImage: "trophy.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(.yellow)
                            Spacer()
                            Text("\(top.durationLabel) · \(top.shareLabel)").font(.system(size: 8.5, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }
                    if let suggestion = store.activitySuggestion {
                        HStack {
                            Text(suggestion).font(.system(size: 9)).foregroundStyle(.orange)
                            Spacer(); Button("继续工作") { store.overtimeActive = true }.controlSize(.mini)
                        }
                    }
                }
            }

            Card {
                HStack(spacing: 11) {
                    Image(systemName: store.weather.symbol).font(.system(size: 25)).foregroundStyle(store.weather.isDay ? .orange : .indigo).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.weather.location?.displayName ?? "尚未选择天气城市").font(.system(size: 10.5, weight: .bold)).lineLimit(1)
                        Text(store.weather.hasDisplayPayload ? store.weather.metricsLabel : store.weather.message)
                            .font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(1)
                        if store.weather.hasDisplayPayload {
                            Text("Open-Meteo · \(store.weatherFreshnessLabel) · \(store.weather.celestialLabel)").font(.system(size: 8)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(store.weather.temperatureLabel).font(.system(size: 22, weight: .bold, design: .rounded))
                    if store.weather.refresh.status == .stale || store.weather.refresh.status == .initialFailure {
                        DataFailureHintButton(
                            title: "天气更新暂时失败",
                            metadata: store.weather.refresh,
                            retry: store.refreshWeather
                        )
                    }
                    RefreshIconButton(isRefreshing: store.isRefreshingWeather, action: store.refreshWeather, help: "刷新天气")
                }
            }

            Card {
                VStack(spacing: 10) {
                    HStack {
                        Label(store.pomodoroPhase.label, systemImage: "timer").font(.system(size: 12, weight: .bold)).foregroundStyle(store.pomodoroPhase.color)
                        Spacer()
                        Text(store.pomodoroTimeLabel).font(.system(size: 27, weight: .bold, design: .monospaced))
                        Spacer()
                        Button(store.pomodoroPhase == .focus || store.pomodoroPhase == .breakTime || store.pomodoroPhase == .longBreak ? "暂停" : "开始") { store.togglePomodoro() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button { store.skipPomodoroPhase() } label: { Image(systemName: "forward.end.fill") }.buttonStyle(.borderless).help("跳过并记录").disabled(store.pomodoroPhase == .idle)
                        Button { store.resetPomodoro() } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.borderless)
                    }
                    HStack {
                        Stat(label: "完成", value: "\(store.completedFocusToday) 轮")
                        Divider().frame(height: 26)
                        Stat(label: "跳过", value: "\(store.skippedToday) 次")
                        Divider().frame(height: 26)
                        Stat(label: "有效专注", value: store.focusTimeTodayLabel)
                    }
                }
            }

            Card {
                VStack(spacing: 9) {
                    HStack {
                        Circle().fill(store.diagnosticReport.health.color).frame(width: 8, height: 8)
                        Text(store.diagnosticReport.health == .idle ? "AI 服务健康" : store.diagnosticReport.health.label).font(.system(size: 12, weight: .bold))
                        Spacer()
                        if !store.diagnosticReport.checks.isEmpty {
                            Button { store.copyDiagnosticReport() } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("复制诊断报告")
                        }
                        Button(store.diagnosticReport.health == .checking ? "诊断中…" : "深度诊断") { store.runAIDiagnostics() }
                            .controlSize(.small).disabled(store.diagnosticReport.health == .checking)
                    }
                    Text(store.diagnosticReport.summary).font(.system(size: 10)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(store.diagnosticReport.recommendation).font(.system(size: 8.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("诊断引擎 · \(store.diagnosticReport.completedAt == nil ? "尚未执行" : store.diagnosticFreshnessLabel)")
                        .font(.system(size: 8)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !store.dashboardQuotaPresentations.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label("额度概览", systemImage: "gauge.with.dots.needle.67percent").font(.system(size: 11, weight: .bold))
                            Text("工作台可选多个；小窗口只显示一个置顶来源").font(.system(size: 8)).foregroundStyle(.secondary)
                            Spacer()
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(store.dashboardQuotaPresentations) { quota in
                                MiniQuota(quota: quota) { store.refreshAPIConnector(quota.id) }
                            }
                        }
                    }
                }
            }

            Card {
                VStack(spacing: 7) {
                    HStack {
                        SystemPill(label: "CPU", value: DisplayFormat.percent(store.cpuUsage), color: .cyan)
                        SystemPill(label: "内存", value: DisplayFormat.percent(store.memoryUsage), color: .purple)
                        SystemPill(label: "GPU", value: DisplayFormat.percent(store.gpuUsage), color: .orange)
                        SystemPill(label: "温度", value: store.temperature.map { String(format: "%.0f°C", $0) } ?? store.thermalState, color: .red)
                        SystemPill(label: "延迟", value: store.latency.map { "\(Int($0))ms" } ?? "--", color: .green)
                    }
                    HStack {
                        Label(store.thermalRisk.level.label, systemImage: "thermometer.medium").foregroundStyle(store.thermalRisk.level.color)
                        Text(store.thermalRisk.evidence).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(); Text("风险估算").foregroundStyle(.tertiary)
                    }.font(.system(size: 8.5))
                }
            }
        }
    }

    private var devices: some View {
        VStack(spacing: 11) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("多 SSH 设备", systemImage: "server.rack").font(.system(size: 12, weight: .bold))
                        Spacer()
                        RefreshIconButton(isRefreshing: store.isRefreshingRemoteDevices, action: store.refreshRemoteDevices, help: "刷新所有设备")
                    }
                    HStack {
                        FocusableTextField(text: $store.newRemoteName, placeholder: "显示名称，例如 G1-002").frame(height: 24)
                        FocusableTextField(text: $store.newRemoteAlias, placeholder: "~/.ssh/config 别名", onSubmit: store.addRemoteDevice).frame(height: 24)
                        Button("添加") { store.addRemoteDevice() }.disabled(store.newRemoteAlias.isEmpty)
                    }.controlSize(.small)
                    Text("只使用本机 SSH 配置与 ssh-agent；探测命令固定、只读，不保存密码/私钥，不读取远端项目或训练日志。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
            }
            if store.remoteDevices.isEmpty {
                Card { Text("尚未添加远程设备。可填写你在 ~/.ssh/config 中已有的 Host 别名。").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            ForEach(store.orderedRemoteDevices) { device in
                let snapshot = store.remoteSnapshots[device.id] ?? RemoteDeviceSnapshot(id: device.id)
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Circle().fill(snapshot.health.color).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(device.name).font(.system(size: 12, weight: .bold))
                                HStack(spacing: 5) {
                                    Text("\(device.sshAlias) · \(snapshot.hostName)")
                                    Label(device.networkScope.shortLabel, systemImage: device.networkScope.symbol)
                                        .font(.system(size: 7.5, weight: .semibold))
                                        .foregroundStyle(device.networkScope.color)
                                }
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if device.pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.blue).help("已置顶") }
                            Badge(text: snapshot.health.label, color: snapshot.health.color)
                            Button { settingsRemoteID = device.id } label: { Image(systemName: "slider.horizontal.3") }
                                .buttonStyle(.plain).foregroundStyle(.blue).help("设备快捷设置")
                                .popover(isPresented: Binding(
                                    get: { settingsRemoteID == device.id },
                                    set: { if !$0, settingsRemoteID == device.id { settingsRemoteID = nil } }
                                ), arrowEdge: .trailing) {
                                    RemoteDeviceQuickSettings(store: store, deviceID: device.id) { settingsRemoteID = nil }
                                }
                            Button {
                                expandedRemoteIDs.remove(device.id)
                                store.removeRemoteDevice(device.id)
                            } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        HStack {
                            Stat(label: "探测耗时", value: snapshot.latencyMS.map { "\(Int($0)) ms" } ?? "--")
                            Stat(label: "Load", value: snapshot.load1.map { String(format: "%.2f", $0) } ?? "--")
                            Stat(label: "显存", value: snapshot.gpuMemorySummary)
                            Stat(label: "GPU", value: snapshot.gpus.isEmpty ? "--" : "\(snapshot.gpus.count) 张")
                        }
                        HStack(spacing: 5) {
                            Text(snapshot.message).lineLimit(1); Spacer(); Text(DataFreshness.label(snapshot.checkedAt, now: store.now))
                        }.font(.system(size: 8.5)).foregroundStyle(.secondary)
                        if !snapshot.gpus.isEmpty { remoteMemoryOverview(snapshot.gpus) }
                        HStack(spacing: 6) {
                            Button { store.refreshRemoteDevice(device.id) } label: {
                                Label(store.refreshingRemoteDeviceIDs.contains(device.id) ? "连接中" : "立即刷新", systemImage: "arrow.clockwise")
                            }.controlSize(.mini).disabled(store.refreshingRemoteDeviceIDs.contains(device.id))
                            Button { store.copyRemoteDiagnostic(device.id) } label: { Label("复制诊断", systemImage: "doc.on.doc") }.controlSize(.mini)
                            Button { store.observeRemoteDevice(device.id) } label: { Label("观察 2 分钟", systemImage: "eye") }.controlSize(.mini)
                            Spacer()
                            Button(expandedRemoteIDs.contains(device.id) ? "收起详情" : "展开详情") {
                                if expandedRemoteIDs.contains(device.id) {
                                    expandedRemoteIDs.remove(device.id)
                                } else if expandedRemoteIDs.count < 4 {
                                    expandedRemoteIDs.insert(device.id)
                                }
                            }
                            .disabled(!expandedRemoteIDs.contains(device.id) && expandedRemoteIDs.count >= 4)
                            .controlSize(.mini)
                        }
                        if let feedback = store.remoteActionFeedback[device.id] {
                            Text(feedback).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if expandedRemoteIDs.contains(device.id) { remoteDetail(device: device, snapshot: snapshot) }
                    }
                }
            }
        }
    }

    private func remoteMemoryOverview(_ gpus: [RemoteGPU]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("GPU 显存矩阵 · 展开详情查看任务与诊断").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(4, max(1, gpus.count))), spacing: 6) {
                ForEach(gpus) { gpu in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 3) {
                            Text("GPU \(gpu.index)").font(.system(size: 8.5, weight: .bold))
                            Spacer()
                            Text("\(Int(gpu.memoryPercent))%").font(.system(size: 8, weight: .semibold, design: .rounded)).foregroundStyle(gpuMemoryTint(gpu.memoryPercent))
                        }
                        Text(String(format: "%.1f / %.1f GB", Double(gpu.memoryUsedMiB) / 1_024, Double(gpu.memoryTotalMiB) / 1_024))
                            .font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        GeometryReader { proxy in
                            Capsule().fill(Color.secondary.opacity(0.12)).overlay(alignment: .leading) {
                                Capsule().fill(gpuMemoryTint(gpu.memoryPercent)).frame(width: max(2, proxy.size.width * gpu.memoryPercent / 100))
                            }
                        }.frame(height: 5)
                        HStack(spacing: 4) {
                            Text(gpu.utilizationPercent.map { "算力 \(Int($0))%" } ?? "算力 --")
                            Text(gpu.temperatureCelsius.map { "\(Int($0))°" } ?? "--°")
                            Text(gpu.powerWatts.map { String(format: "%.0fW", $0) } ?? "--W")
                        }.font(.system(size: 6.8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
    }

    private func gpuMemoryTint(_ percent: Double) -> Color {
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        if percent >= 50 { return .blue }
        return .cyan
    }

    @ViewBuilder
    private func remoteDetail(device: RemoteDeviceConfiguration, snapshot: RemoteDeviceSnapshot) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 6) {
            Text("Codex 发现：\(snapshot.codexFound ? snapshot.codexVersion ?? "已发现" : "默认探测环境未发现")").font(.system(size: 9, weight: .semibold))
            Text(snapshot.codexDiscoveryDetail).font(.system(size: 8.5)).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Codex 端点（独立诊断）：\(snapshot.codexEndpointDetail)").font(.system(size: 8.5)).foregroundStyle(endpointColor(snapshot)).textSelection(.enabled)
            Text(endpointGuidance(snapshot)).font(.system(size: 7.8)).foregroundStyle(.secondary)
            if !snapshot.diagnosticEvidence.isEmpty { Text(snapshot.diagnosticEvidence).font(.system(size: 8)).foregroundStyle(.tertiary).textSelection(.enabled) }
        }
        HStack {
            Text(device.taskDisclosureMode == .redactedCommand ? "任务识别：脱敏启动命令" : "任务识别：Slurm / 调度器")
                .font(.system(size: 9, weight: .semibold))
            Spacer()
            Text(device.taskDisclosureMode.label).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        Text(device.taskDisclosureMode == .redactedCommand ? snapshot.taskCollectionDetail : snapshot.schedulerCollectionDetail)
            .font(.system(size: 8)).foregroundStyle((snapshot.gpuProcesses.isEmpty && snapshot.scheduledJobs.isEmpty) ? Color.orange : Color.secondary)
        if device.taskDisclosureMode == .redactedCommand, !snapshot.gpuProcesses.isEmpty {
            Text("GPU 任务（按 PID 跨卡归并）").font(.system(size: 9, weight: .semibold))
            ForEach(snapshot.gpuProcesses.prefix(10)) { process in
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text("\(process.user.map { "\($0) · " } ?? "")\(process.name) · GPU \(process.gpuIndices.map(String.init).joined(separator: ","))").lineLimit(1); Spacer(); Text("\(process.memoryMiB.formatted()) MiB") }.font(.system(size: 8.5))
                    HStack { Text("PID \(process.pid)"); if let elapsed = process.elapsed { Text(elapsed) } }.font(.system(size: 7.5)).foregroundStyle(.tertiary)
                    if let command = process.redactedCommand, device.taskDisclosureMode == .redactedCommand { Text(command).font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
        }
        if device.taskDisclosureMode == .schedulerOnly, !snapshot.scheduledJobs.isEmpty {
            Text("Slurm 当前 SSH 用户任务").font(.system(size: 9, weight: .semibold))
            ForEach(snapshot.scheduledJobs.prefix(8)) { job in
                HStack { Text("#\(job.jobID) · \(job.name)").lineLimit(1); Spacer(); Text(job.state); Text("\(job.elapsed)/\(job.timeLimit)"); if !job.expectedEnd.isEmpty && job.expectedEnd != "N/A" { Text("预计 \(job.expectedEnd)") } }.font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
    }

    private func endpointColor(_ snapshot: RemoteDeviceSnapshot) -> Color {
        guard let status = snapshot.codexEndpointStatus else { return .secondary }
        return status >= 500 ? .red : status == 401 || status == 403 ? .green : .secondary
    }

    private func endpointGuidance(_ snapshot: RemoteDeviceSnapshot) -> String {
        if snapshot.codexEndpointStatus == 401 || snapshot.codexEndpointStatus == 403 { return "路径可达；受控探测不会读取或伪造远端 Codex 登录凭据，因此无需修复。" }
        if snapshot.codexEndpointStatus == nil { return "这不会影响 SSH、GPU 或任务监控。可在“诊断”中检查 DNS、代理和 TLS；无需修改远端全局代理。" }
        if (snapshot.codexEndpointStatus ?? 0) >= 500 { return "上游服务返回 5xx。稍后重试；若持续发生，复制诊断并检查网络路径。" }
        return "端点状态仅用于可用性观察，不会改变远端配置。"
    }

    private var timeline: some View {
        LazyVStack(spacing: 9) {
            Card {
                HStack {
                    Label("本地事件时间线", systemImage: "clock.arrow.circlepath").font(.system(size: 12, weight: .bold))
                    Spacer(); Text("保留 30 天 · 最多 500 条").font(.system(size: 8.5)).foregroundStyle(.secondary)
                    Button("清除已恢复") { store.clearResolvedTimelineEvents() }.controlSize(.mini)
                }
                if let error = store.timelineStorageError {
                    Text("账本保存失败：\(error)").font(.system(size: 8)).foregroundStyle(.red).textSelection(.enabled)
                } else {
                    Text("本机账本：\(store.timelineEvents.count) 条 · \(store.timelineStoragePath)").font(.system(size: 7.5)).foregroundStyle(.tertiary).lineLimit(1).textSelection(.enabled)
                }
            }
            if store.timelineEvents.isEmpty {
                Card { Text("暂无事件。网络、远程设备、额度、热风险、Clash 与番茄钟的异常和恢复会统一记录在这里。")
                    .font(.system(size: 9.5)).foregroundStyle(.secondary) }
            }
            ForEach(Array(store.timelineEvents.prefix(timelineVisibleLimit))) { event in
                Card {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: event.category.symbol).foregroundStyle(event.severity.color).frame(width: 15)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(event.title).font(.system(size: 10, weight: .semibold))
                                if event.isActive { Badge(text: "进行中", color: event.severity.color) }
                                else { Badge(text: "已恢复", color: .green) }
                                Spacer(); Text(event.startedAt, style: .relative).font(.system(size: 8)).foregroundStyle(.secondary)
                            }
                            Text(event.evidence).font(.system(size: 8.5)).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack {
                                Text("\(event.category.label) · \(event.source) · 持续 \(event.durationLabel)")
                                Spacer(); Button { store.copyTimelineEvent(event) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain)
                            }.font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            if store.timelineEvents.count > timelineVisibleLimit {
                Button("继续加载较早事件（剩余 \(store.timelineEvents.count - timelineVisibleLimit) 条）") {
                    timelineVisibleLimit = min(store.timelineEvents.count, timelineVisibleLimit + 60)
                }
                .controlSize(.small)
            }
        }
    }

    private var insights: some View {
        VStack(spacing: 11) {
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("应用活跃排行榜", systemImage: "chart.bar.fill").font(.system(size: 12, weight: .bold))
                        Spacer()
                        Picker("范围", selection: $store.activityRangeDays) {
                            Text("今日").tag(1); Text("7 天").tag(7); Text("30 天").tag(30)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 155)
                    }
                    if store.activityRankings.isEmpty {
                        Text("开始使用应用后，这里会按有效使用时长生成排行。锁屏、睡眠和超过空闲阈值的时间不会计入。")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                        if !store.excludedApplicationIDs.isEmpty {
                            HStack {
                                Text("已有 \(store.excludedApplicationIDs.count) 个应用被排除").font(.system(size: 8.5)).foregroundStyle(.orange)
                                Spacer()
                                Button("恢复全部") { store.restoreAllExcludedApplications() }.controlSize(.mini)
                            }
                        }
                    } else {
                        ForEach(Array(store.activityRankings.prefix(activityRanksExpanded ? store.activityRankings.count : 5).enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 8) {
                                Text("#\(index + 1)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(index == 0 ? .yellow : .secondary).frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack { Text(item.name).font(.system(size: 10, weight: .semibold)); Spacer(); Text("\(item.durationLabel) · \(item.shareLabel)").font(.system(size: 9, design: .rounded)) }
                                    GeometryReader { proxy in
                                        Capsule().fill(Color.secondary.opacity(0.12)).overlay(alignment: .leading) {
                                            Capsule().fill(index == 0 ? Color.yellow : Color.cyan).frame(width: max(3, proxy.size.width * item.share))
                                        }
                                    }.frame(height: 4)
                                }
                                Button { pendingExclusion = item } label: { Image(systemName: "eye.slash") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary).help("从统计中排除（需要确认）")
                            }
                        }
                        if store.activityRankings.count > 5 {
                            Button(activityRanksExpanded ? "收起为前 5 条" : "查看全部 · 共 \(store.activityRankings.count) 条") {
                                activityRanksExpanded.toggle()
                                activityRanksInteractionGeneration += 1
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 8.5, weight: .semibold))
                            .help(activityRanksExpanded ? "15 秒无交互后会自动收起" : "展开完整排行；15 秒无交互后自动收起")
                        }
                    }
                }
            }
            .simultaneousGesture(TapGesture().onEnded {
                if activityRanksExpanded { activityRanksInteractionGeneration += 1 }
            })
            .simultaneousGesture(DragGesture(minimumDistance: 1).onChanged { _ in
                if activityRanksExpanded { activityRanksInteractionGeneration += 1 }
            })
            .task(id: "\(activityRanksExpanded)-\(activityRanksInteractionGeneration)") {
                guard activityRanksExpanded else { return }
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                activityRanksExpanded = false
            }
            .onChange(of: store.activityRangeDays) { _, _ in activityRanksExpanded = false }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Codex 官方额度", systemImage: "gauge.with.dots.needle.67percent").font(.system(size: 12, weight: .bold))
                        Spacer(); Badge(text: "官方", color: .green)
                        RefreshIconButton(isRefreshing: store.isRefreshingQuota, action: store.refreshQuota, help: "刷新 Codex 官方额度")
                    }
                    if store.codexQuota.windows.isEmpty {
                        HStack {
                            Stat(label: "最低剩余", value: store.codexQuota.riskRemainingLabel)
                            Stat(label: "可用重置券", value: store.codexQuota.resetCreditCount.map { "\($0) 张" } ?? "--")
                            Stat(label: "下次窗口刷新", value: store.codexQuota.resetDateTimeLabel)
                        }
                    } else {
                        LazyVGrid(columns: store.codexQuota.windows.count > 1 ? [GridItem(.flexible()), GridItem(.flexible())] : [GridItem(.flexible())], spacing: 7) {
                            ForEach(store.codexQuota.windows) { window in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(LocalizedStringKey(window.title)).font(.system(size: 9.5, weight: .bold))
                                        Spacer()
                                        Text("剩余 \(window.remainingLabel)")
                                            .font(.system(size: 11, weight: .black, design: .monospaced)).foregroundStyle(window.remainingPercent < 20 ? .orange : .green)
                                    }
                                    GeometryReader { proxy in
                                        Capsule().fill(Color.secondary.opacity(0.12)).overlay(alignment: .leading) {
                                            Capsule().fill(window.remainingPercent < 20 ? Color.orange : Color.green)
                                                .frame(width: max(2, proxy.size.width * window.remainingPercent / 100))
                                        }
                                    }.frame(height: 5)
                                    HStack {
                                        Text("已用 \(window.usedLabel)")
                                        Spacer()
                                        Text("刷新 \(window.resetLabel)")
                                    }.font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                        HStack {
                            Text("可用重置券")
                            Text(store.codexQuota.resetCreditCount.map { "\($0) 张" } ?? "--")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                            Spacer()
                        }.font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    let usagePoints = CodexUsageChartData.points(from: Array(store.codexQuota.dailyUsageBuckets.suffix(14)))
                    if !usagePoints.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Codex Token 活动 · 最近 14 天").font(.system(size: 8.5, weight: .semibold))
                                Spacer()
                                if let selected = CodexUsageChartData.nearestPoint(to: selectedCodexUsageDate, in: usagePoints) {
                                    Text("\(selected.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))) · \(selected.tokens.formatted(.number.notation(.compactName))) Token")
                                        .font(.system(size: 7.5, weight: .semibold, design: .monospaced)).foregroundStyle(.cyan)
                                } else if let lifetime = store.codexQuota.tokenUsageSummary?.lifetimeTokens {
                                    Text("累计 \(lifetime.formatted(.number.notation(.compactName)))")
                                        .font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary)
                                }
                            }
                            let selectedPoint = CodexUsageChartData.nearestPoint(to: selectedCodexUsageDate, in: usagePoints)
                            Chart(usagePoints) { point in
                                BarMark(x: .value("日期", point.date, unit: .day), y: .value("Token", point.tokens))
                                    .foregroundStyle((point.date == selectedPoint?.date ? Color.blue : Color.cyan).gradient)
                                    .cornerRadius(2)
                                if point.date == selectedPoint?.date {
                                    RuleMark(x: .value("选中日期", point.date))
                                        .foregroundStyle(Color.blue.opacity(0.45))
                                }
                            }
                            .chartYAxis(.hidden)
                            .chartXAxis {
                                AxisMarks(values: CodexUsageChartData.sparseTickDates(for: usagePoints, maximumCount: 2)) { _ in
                                    AxisValueLabel(format: .dateTime.month(.twoDigits).day(.twoDigits))
                                        .font(.system(size: 6.5, design: .monospaced))
                                }
                            }
                            .chartXSelection(value: $selectedCodexUsageDate)
                            .frame(height: 55)
                            .help("点击或拖动查看完整日期与 Token 用量")
                        }
                    }
                    if let credit = store.codexQuota.resetCredits.first {
                        Text("最近重置券：\(credit.grantedAt?.formatted(date: .abbreviated, time: .shortened) ?? "授予时间未知")；到期 \(credit.expiresAt?.formatted(date: .abbreviated, time: .shortened) ?? "未提供")")
                            .font(.system(size: 8.5)).foregroundStyle(.secondary)
                    } else {
                        Text(store.codexQuota.message).font(.system(size: 8.5)).foregroundStyle(.secondary)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("社区全局重置信号", systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 12, weight: .bold))
                        Spacer(); Badge(text: store.codexCommunityReset.isStale ? "第三方 · 缓存" : "第三方", color: .orange)
                        RefreshIconButton(isRefreshing: store.isRefreshingCommunityReset, action: store.refreshCommunityReset, help: "刷新社区重置信号")
                    }
                    Text(store.codexCommunityReset.verdictLabel).font(.system(size: 15, weight: .bold, design: .rounded))
                    HStack {
                        if let confidence = store.codexCommunityReset.confidenceLabel { Badge(text: confidence, color: .orange) }
                        else if let historical = store.codexCommunityReset.historicalConfidenceLabel { Text(historical).foregroundStyle(.tertiary) }
                        if let next = store.codexCommunityReset.nextScheduledAt { Text("计划：\(next.formatted(date: .abbreviated, time: .shortened))") }
                        else if let last = store.codexCommunityReset.lastResetAt { Text("最近：\(last.formatted(date: .abbreviated, time: .shortened))") }
                        Spacer()
                        if store.codexCommunityReset.sourceURL != nil { Button("查看来源") { store.openCommunityResetSource() }.controlSize(.mini) }
                    }.font(.system(size: 8.5)).foregroundStyle(.secondary)
                    Text("上游：\(store.codexCommunityReset.sourceGeneratedAt?.formatted(date: .omitted, time: .shortened) ?? "--") · 本机获取：\(store.codexCommunityReset.checkedAt?.formatted(date: .omitted, time: .shortened) ?? "--")\(store.codexCommunityReset.isStale ? " · 缓存" : "")")
                        .font(.system(size: 7.5)).foregroundStyle(.tertiary)
                    Text("来自 Codex Runway 公共状态源，不代表 OpenAI 官方承诺；没有明确计划时不会推算倒计时。")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }

            Card {
                let day = ChinaHolidayCalendar.dayInfo(for: store.now)
                let nextEvent = ChinaHolidayCalendar.upcomingEvents(after: store.now, limit: 1).first
                Button { holidayCalendarPresented = true } label: {
                    HStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(HolidayPresentation.color(for: day).opacity(0.14))
                            Image(systemName: HolidayPresentation.symbol(for: day))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(HolidayPresentation.color(for: day))
                        }
                        .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.conciseLabel).font(.system(size: 11, weight: .bold))
                            Text(store.now.formatted(.dateTime.month().day().weekday(.wide)))
                                .font(.system(size: 8)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(HolidayPresentation.nextEventSummary(nextEvent, from: store.now))
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("中国法定节假日 · 点击查看详情")
                                .font(.system(size: 7.5)).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("日历详情。今天\(day.conciseLabel)")
                .popover(isPresented: $holidayCalendarPresented, arrowEdge: .trailing) {
                    ChinaHolidayCalendarPopover(initialDate: store.now)
                }
            }
        }
    }

    private var diagnostics: some View {
        VStack(spacing: 11) {
            Card {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("界面响应监测", systemImage: "gauge.with.dots.needle.67percent")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        Badge(text: store.mainThreadResponsiveness.isDegraded ? "检测到卡顿" : "响应正常", color: store.mainThreadResponsiveness.isDegraded ? .orange : .green)
                    }
                    Text(store.mainThreadResponsiveness.evidenceLabel)
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("系统指标最近一次后台采样 \(String(format: "%.0f", store.metricsCollectionDurationMilliseconds)) ms。这里只记录延迟数值，不记录点击、键盘内容或窗口标题。")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(store.diagnosticReport.summary, systemImage: store.diagnosticReport.health == .healthy ? "checkmark.shield.fill" : "stethoscope")
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(store.diagnosticReport.health.color)
                        Spacer()
                        if !store.diagnosticReport.checks.isEmpty { Button("复制报告") { store.copyDiagnosticReport() }.controlSize(.small) }
                        Button("重新诊断") { store.runAIDiagnostics() }.controlSize(.small)
                    }
                    Text(store.diagnosticReport.recommendation).font(.system(size: 9)).foregroundStyle(.secondary)
                    if let date = store.diagnosticReport.completedAt { Text("诊断引擎 · \(store.diagnosticFreshnessLabel)（\(date.formatted(date: .omitted, time: .standard))）").font(.system(size: 8)).foregroundStyle(.tertiary) }
                }
            }
            if store.diagnosticReport.checks.isEmpty {
                Card { Text("诊断会验证普通 DNS、OpenAI DNS、本地代理端口，并对普通 TLS、ChatGPT 和 OpenAI API 做三轮低频采样，以中位数和范围判断路径；失败时再做直连对照，最后检查 Codex app-server。")
                    .font(.system(size: 10)).foregroundStyle(.secondary) }
            } else {
                Card {
                    VStack(spacing: 9) {
                        ForEach(store.diagnosticReport.checks) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: item.state.symbol).foregroundStyle(item.state.color).frame(width: 14)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack { Text(item.title).fontWeight(.semibold); Spacer(); if let ms = item.latencyMS { Text("\(Int(ms)) ms").foregroundStyle(.secondary) } }
                                    Text(item.detail).foregroundStyle(.secondary)
                                }.font(.system(size: 9.5))
                            }
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("配置备份", systemImage: "externaldrive.badge.timemachine").font(.system(size: 12, weight: .bold))
                        Spacer(); Button("导入") { store.importConfiguration() }; Button("导出") { store.exportConfiguration() }
                    }.controlSize(.mini)
                    Text("仅导入/导出工作时间、阈值、远程设备定义和连接器地址。SSH 密钥/密码、Clash Secret、飞书 Webhook、API Key 等安全信息不会导出，换机后需要重新填写。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Label("当前出口", systemImage: "globe.asia.australia.fill").font(.system(size: 11, weight: .bold)); Spacer(); RefreshIconButton(isRefreshing: store.isRefreshingIP, action: store.refreshIP, help: "刷新公网 IP") }
                    Text(store.ip.locationHeadline).font(.system(size: 18, weight: .bold))
                    HStack {
                        Badge(text: store.ip.scopeLabel, color: store.ip.isMainlandChina ? .blue : .purple)
                        Badge(text: store.proxyActive ? "经系统代理观测" : "直连观测", color: store.proxyActive ? .indigo : .green)
                        if store.vpnActive { Badge(text: "VPN/TUN", color: .orange) }
                    }
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text("公网地址：\(store.ip.address)（\(store.ip.addressFamilyLabel)）")
                                Button { store.copyIPAddress() } label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.plain).help("复制公网地址")
                            }
                            Text("位置信息：\(store.ip.locationLine)")
                            if !store.ip.isp.isEmpty { Text("网络提供方：\(store.ip.isp)") }
                            Text("查询时间：\(store.ipFreshnessLabel)")
                            Text("仅用于网络出口观察，不参与天气、设备范围或其他位置判断。")
                                .foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    } label: {
                        Text("查看出口详情").font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 7) {
                    Text("实时网络").font(.system(size: 11, weight: .bold))
                    HStack { Stat(label: "延迟", value: store.latency.map { "\(Int($0)) ms" } ?? "--"); Stat(label: "下载", value: DisplayFormat.speed(store.downloadSpeed)); Stat(label: "上传", value: DisplayFormat.speed(store.uploadSpeed)) }
                    Chart(store.speedHistory) { sample in
                        LineMark(x: .value("时间", sample.time), y: .value("下载", sample.download / 1_000_000)).foregroundStyle(.cyan)
                    }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 45)
                }
            }
        }
    }

    private var sounds: some View {
        AmbientSoundPanel(service: store.ambientSound)
    }

    private var settings: some View {
        VStack(spacing: 11) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Label("凭据保险库", systemImage: "lock.shield.fill").font(.system(size: 12, weight: .bold))
                        Badge(text: store.credentialVaultUnlocked ? "本次运行已解锁" : "已锁定", color: store.credentialVaultUnlocked ? .green : .orange)
                        Spacer()
                        if store.credentialVaultUnlocked {
                            Button("保存全部变更") { store.saveCredentialVault() }.controlSize(.mini)
                            Button("锁定") { store.lockCredentialVault() }.controlSize(.mini)
                        } else {
                            Button("解锁凭据") { store.unlockCredentialVault() }.buttonStyle(.borderedProminent).controlSize(.mini)
                        }
                        Menu {
                            Button("尝试导入可静默读取的旧凭据") { store.importReadableLegacyCredentials() }
                            Button("打开钥匙串访问") { store.openKeychainAccess() }
                            Button("清除 PulseDock 保险库", role: .destructive) { store.clearCredentialVault() }
                        } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                    }
                    Text(store.credentialVaultStatus).font(.system(size: 8.5)).foregroundStyle(.secondary)
                    Text("只在你主动解锁时访问一次 macOS Keychain。Clash、飞书和 API 连接器在本次运行共用内存凭据；退出 PulseDock 后自动清空。")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("工作时间").font(.system(size: 12, weight: .bold))
                    HStack {
                        Stepper("上班 \(WorkScheduleLogic.timeLabel(store.workStartMinutes))", value: $store.workStartMinutes, in: 0...1_439, step: 30)
                        Stepper("下班 \(WorkScheduleLogic.timeLabel(store.workEndMinutes))", value: $store.workEndMinutes, in: 0...1_439, step: 30)
                    }.controlSize(.mini).font(.system(size: 9.5))
                    HStack {
                        Stepper("午休 \(WorkScheduleLogic.timeLabel(store.lunchStartMinutes))", value: $store.lunchStartMinutes, in: 0...1_439, step: 30)
                        Stepper("结束 \(WorkScheduleLogic.timeLabel(store.lunchEndMinutes))", value: $store.lunchEndMinutes, in: 0...1_439, step: 30)
                    }.controlSize(.mini).font(.system(size: 9.5))
                    HStack(spacing: 5) {
                        ForEach(Array(zip([1,2,3,4,5,6,7], ["日","一","二","三","四","五","六"])), id: \.0) { day, label in
                            WorkdayToggle(label: label, isSelected: store.workWeekdays.contains(day), accent: state.panelAccent) {
                                if store.workWeekdays.contains(day) { store.workWeekdays.remove(day) }
                                else { store.workWeekdays.insert(day) }
                            }
                        }
                    }
                    Picker("今天", selection: $store.manualDayOverride) { Text("跟随日历").tag(0); Text("按工作日").tag(1); Text("按休息日").tag(2) }
                        .pickerStyle(.segmented).controlSize(.small)
                    Text("下班早于或等于上班时间时按跨午夜班次处理；每日 00:00 自动清除加班和当天人工覆盖。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("应用活跃统计").font(.system(size: 12, weight: .bold))
                        Spacer()
                        Stepper("空闲 \(store.idleThresholdSeconds / 60) 分", value: $store.idleThresholdSeconds, in: 60...600, step: 60)
                            .controlSize(.mini)
                    }
                    Text("默认统计全部普通前台应用。有效时长要求应用位于前台且键鼠未超过空闲阈值；睡眠、锁屏与长时间停顿不会补记。不读取窗口标题、网页、聊天或文件内容。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                    if !store.excludedApplicationIDs.isEmpty {
                        Divider()
                        Text("已排除").font(.system(size: 9, weight: .semibold))
                        ForEach(Array(store.excludedApplicationIDs).sorted(), id: \.self) { bundle in
                            HStack {
                                Text(store.excludedApplicationName(bundle)).font(.system(size: 9)).lineLimit(1)
                                Spacer(); Button("恢复") { store.restoreApplication(bundle) }.controlSize(.mini)
                            }
                        }
                    }
                }.font(.system(size: 9.5))
            }
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    Text("全局快捷键").font(.system(size: 12, weight: .bold))
                    HStack {
                        Text("显示 / 隐藏").frame(width: 72, alignment: .leading)
                        ShortcutRecorderField(shortcut: $state.visibilityShortcut).frame(width: 150, height: 28)
                        Spacer()
                    }
                    HStack {
                        Text("展开 / 收起").frame(width: 72, alignment: .leading)
                        ShortcutRecorderField(shortcut: $state.expansionShortcut).frame(width: 150, height: 28)
                        Spacer()
                    }
                    HStack {
                        Text(state.shortcutRegistrationStatus)
                            .foregroundStyle(state.shortcutRegistrationStatus.contains("已启用") ? .green : .orange)
                        Spacer()
                        Button("恢复默认") {
                            state.visibilityShortcut = .optionSpace
                            state.expansionShortcut = .optionShiftSpace
                        }.controlSize(.mini)
                    }
                    Text("显示/隐藏：隐藏时召唤为小窗；展开/收起：隐藏时直接以展开态召唤。快捷键不会改变音频、计时或当前页面。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                    Text("点击快捷键框后直接按新组合；Esc 取消。若与 macOS、其他软件或另一项 PulseDock 快捷键冲突，会立即提示并保留上一组有效设置。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                }.font(.system(size: 9.5))
            }
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("天气城市").font(.system(size: 12, weight: .bold))
                        Spacer()
                        if let location = store.weatherLocation { Badge(text: location.name, color: .orange) }
                        Button(store.weatherLocationInProgress ? "取消定位" : "使用当前位置") { store.useCurrentWeatherLocation() }
                            .controlSize(.mini)
                    }
                    HStack {
                        Picker("位置来源", selection: $store.weatherLocationMode) {
                            ForEach(WeatherLocationMode.allCases, id: \.self) { mode in Text(mode.label).tag(mode) }
                        }.pickerStyle(.segmented).controlSize(.small)
                        if store.weatherLocationMode == .automatic {
                            Button("立即检查") { store.requestAutomaticWeatherLocation(force: true) }
                                .disabled(store.weatherLocationInProgress).controlSize(.mini)
                        }
                    }
                    HStack {
                        FocusableTextField(text: $store.citySearchQuery, placeholder: "输入城市，例如：上海", onSubmit: store.searchWeatherCities).frame(height: 24)
                        Button(store.citySearchInProgress ? "搜索中…" : "搜索") { store.searchWeatherCities() }
                            .disabled(store.citySearchInProgress).controlSize(.small)
                    }
                    ForEach(store.citySearchResults) { location in
                        Button { store.selectWeatherLocation(location) } label: {
                            HStack { Text(location.displayName); Spacer(); Image(systemName: "chevron.right") }
                                .font(.system(size: 9))
                        }.buttonStyle(.plain)
                    }
                    Text(store.weatherLocationStatus.isEmpty ? "固定地点不会自动改变；自动跟随会短时获取当前位置，移动约 2 公里且行政区变化后更新。天气约每 30 分钟刷新，不根据公网 IP 或 Clash 节点跳城。" : store.weatherLocationStatus)
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                        .help(store.weatherLocationDiagnostic.isEmpty ? "天气位置仅使用 macOS 定位服务，不读取公网 IP 或 Clash 节点位置。" : store.weatherLocationDiagnostic)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("额度连接器", systemImage: "gauge.with.dots.needle.67percent").font(.system(size: 12, weight: .bold))
                        Spacer()
                        RefreshIconButton(isRefreshing: store.isRefreshingAPIConnectors, action: { store.refreshAPIConnectors() }, help: "刷新全部额度连接器")
                    }
                    DisclosureGroup("添加新的额度来源") {
                        VStack(alignment: .leading, spacing: 7) {
                            Picker("类型", selection: $store.newAPIConnectorKind) {
                                ForEach(APIConnectorKind.allCases.filter { !$0.isBuiltInSingleton }, id: \.self) { kind in Text(LocalizedStringKey(kind.label)).tag(kind) }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: store.newAPIConnectorKind) { _, kind in
                                if kind != .customRateLimit { store.newAPIConnectorEndpoint = kind.defaultEndpoint }
                                switch kind {
                                case .codexLocalQuota: break
                                case .cursorLocalUsage: store.newAPIConnectorName = "Cursor 个人额度"
                                case .glmCodingPlan: store.newAPIConnectorName = "GLM Coding Plan"
                                case .deepSeekBalance: store.newAPIConnectorName = "DeepSeek"
                                case .customRateLimit: break
                                }
                            }
                            FocusableTextField(text: $store.newAPIConnectorName, placeholder: "名称/厂商").frame(height: 24)
                            if store.newAPIConnectorKind == .cursorLocalUsage {
                                Text("Cursor 只读本机登录会话，不读取或保存 refresh token。")
                                    .font(.system(size: 8.5)).foregroundStyle(.secondary)
                            } else {
                                FocusableTextField(text: $store.newAPIConnectorEndpoint, placeholder: "官方 HTTPS 探测端点").frame(height: 24)
                                SecureField(store.credentialVaultUnlocked ? "只读 API Key（保存至统一保险库）" : "请先解锁凭据保险库后填写 API Key", text: $store.newAPIConnectorKey)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(!store.credentialVaultUnlocked)
                            }
                            HStack {
                                Text(store.newAPIConnectorKind.requiresAPIKey && !store.credentialVaultUnlocked ? "需先解锁一次凭据保险库" : "添加后可单项或统一刷新")
                                    .font(.system(size: 8)).foregroundStyle(.secondary)
                                Spacer()
                                Button("添加") { store.addAPIConnector() }
                                    .disabled(store.newAPIConnectorName.isEmpty || (store.newAPIConnectorKind != .cursorLocalUsage && !store.newAPIConnectorEndpoint.hasPrefix("https://")) || (store.newAPIConnectorKind.requiresAPIKey && !store.credentialVaultUnlocked))
                            }
                        }
                    }.font(.system(size: 9.5))
                    ForEach(store.orderedAPIConnectors) { connector in
                        let snapshot = store.apiConnectorSnapshot(for: connector)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                            Circle().fill(snapshot.color).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    if connector.showOnDashboard { Image(systemName: "rectangle.grid.2x2.fill").font(.system(size: 7)).foregroundStyle(.blue) }
                                    if connector.pinned { Image(systemName: "pin.fill").font(.system(size: 7)).foregroundStyle(.orange) }
                                    Text(connector.name).font(.system(size: 10.5, weight: .semibold))
                                }
                                Text(LocalizedStringKey(connector.kind.label)).font(.system(size: 7.5)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button { store.refreshAPIConnector(connector.id) } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.plain).foregroundStyle(.blue).help("仅刷新 \(connector.name)")
                            Menu {
                                Button(connector.showOnDashboard ? "从工作台隐藏" : "在工作台显示") { store.toggleAPIConnectorDashboard(connector.id) }
                                Button(connector.pinned ? "取消小窗口置顶" : "置顶到小窗口") { store.toggleAPIConnectorPinned(connector.id) }
                                Button("上移") { store.moveAPIConnector(connector.id, direction: -1) }
                                Button("下移") { store.moveAPIConnector(connector.id, direction: 1) }
                                if !connector.kind.isBuiltInSingleton {
                                    Divider()
                                    Button("移除连接器", role: .destructive) { store.removeAPIConnector(connector.id) }
                                }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                            }
                            if snapshot.usageWindows.isEmpty {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(snapshot.summary).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(2)
                                    Spacer()
                                    if let reset = snapshot.resetAt { Text("刷新 \(reset)").font(.system(size: 8)).foregroundStyle(.secondary) }
                                }
                            } else {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                    ForEach(snapshot.usageWindows) { window in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 4) {
                                                Text(LocalizedStringKey(window.title)).font(.system(size: 8.5, weight: .semibold)).lineLimit(1)
                                                if let number = window.windowNumber {
                                                    Text("窗口 \(number)").font(.system(size: 6.5, weight: .medium)).padding(.horizontal, 4).padding(.vertical, 2)
                                                        .background(Color.secondary.opacity(0.12), in: Capsule())
                                                }
                                                Spacer()
                                            }
                                            HStack {
                                                Text("已用").font(.system(size: 7)).foregroundStyle(.secondary)
                                                Text(window.usedLabel).font(.system(size: 11, weight: .black, design: .monospaced))
                                                Spacer()
                                                Text("剩余 \(Int(window.remainingPercent))%").font(.system(size: 7, design: .monospaced)).foregroundStyle(.secondary)
                                            }
                                            GeometryReader { proxy in
                                                Capsule().fill(Color.secondary.opacity(0.12)).overlay(alignment: .leading) {
                                                    Capsule().fill(window.usedPercent > 85 ? Color.orange : Color.blue)
                                                        .frame(width: max(2, proxy.size.width * window.usedPercent / 100))
                                                }
                                            }.frame(height: 4)
                                        }
                                        .padding(7)
                                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                            }
                            Text("\(snapshot.message) · \(DataFreshness.label(snapshot.updatedAt, now: store.now))")
                                .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(2)
                            if connector.kind.requiresAPIKey {
                                HStack {
                                    SecureField(
                                        store.credentialVaultUnlocked ? "API Key（本次会话草稿）" : "解锁保险库后可填写 API Key",
                                        text: Binding(
                                            get: { store.apiKeyDraft(for: connector.id) },
                                            set: { store.setAPIKeyDraft($0, for: connector.id) }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(!store.credentialVaultUnlocked)
                                    Button("保存并刷新") {
                                        store.saveCredentialVault()
                                        store.refreshAPIConnector(connector.id)
                                    }
                                    .controlSize(.mini)
                                    .disabled(!store.credentialVaultUnlocked || store.apiKeyDraft(for: connector.id).isEmpty)
                                }
                            }
                        }
                        .padding(8).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    Text("工作台可显示多个额度来源；小窗口最多置顶一个。每次启动需先解锁一次保险库，解锁前 Codex、Cursor、Clash 与 API 额度均不读取、不显示。")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                }.controlSize(.small)
            }
            if !store.remoteDevices.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("远程设备 · 隐私与任务识别", systemImage: "lock.shield").font(.system(size: 12, weight: .bold))
                        ForEach(store.orderedRemoteDevices) { device in
                            HStack {
                                Text(device.name).font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
                                Spacer()
                                Picker("任务识别", selection: Binding(
                                    get: { device.taskDisclosureMode },
                                    set: { store.setRemoteTaskDisclosureMode(device.id, $0) }
                                )) {
                                    ForEach(RemoteTaskDisclosureMode.allCases, id: \.self) { Text($0.label).tag($0) }
                                }.labelsHidden().controlSize(.mini)
                            }
                        }
                        Text("默认仅读取 Slurm/调度器任务。脱敏启动命令只读取 GPU 进程，隐藏 Token、密钥和用户目录；关闭后立即停止命令采集。")
                            .font(.system(size: 8.5)).foregroundStyle(.secondary)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    Text("番茄钟").font(.system(size: 12, weight: .bold))
                    HStack { Stepper("专注 \(store.focusMinutes) 分", value: $store.focusMinutes, in: 5...120, step: 5); Stepper("短休息 \(store.breakMinutes) 分", value: $store.breakMinutes, in: 1...60, step: 5) }
                    HStack { Stepper("长休息 \(store.longBreakMinutes) 分", value: $store.longBreakMinutes, in: 5...90, step: 5); Stepper("每 \(store.sessionsBeforeLongBreak) 轮", value: $store.sessionsBeforeLongBreak, in: 1...8) }
                    Text("使用绝对截止时间，Mac 合盖或睡眠后会按真实时间校正，而不是把计时器冻结。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                }.controlSize(.mini).font(.system(size: 9.5))
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Label("Clash 订阅用量", systemImage: "bolt.horizontal.circle").font(.system(size: 12, weight: .bold)); Spacer(); Button("选择兼容文件") { store.chooseClashMetadataFile() }.controlSize(.mini) }
                    if store.clashSubscriptions.isEmpty { Text("未发现订阅元数据").font(.system(size: 9)).foregroundStyle(.secondary) }
                    else {
                        Picker("显示订阅", selection: $store.selectedClashIdentifier) {
                            ForEach(store.clashSubscriptions, id: \.identifier) { Text("\($0.sourceApp) · \($0.name)").tag($0.identifier) }
                        }
                        HStack(alignment: .top, spacing: 14) {
                            quotaStat("已用", store.clashQuota.usedLabel, color: .orange)
                            quotaStat("剩余", store.clashQuota.remainingLabel, color: .blue)
                            quotaStat("总额", store.clashQuota.totalLabel, color: .secondary)
                            Spacer()
                            Button(store.isRefreshingClash ? "读取中…" : "立即重读") { store.refreshClashQuota() }
                                .controlSize(.mini).disabled(store.isRefreshingClash)
                        }
                        Text("已用 \(String(format: "%.1f", store.clashQuota.usedPercent))% · 剩余 \(String(format: "%.1f", store.clashQuota.remainingPercent))%")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                        Text("本地额度已读取 · \(store.clashQuota.message) · \(store.clashFreshnessLabel)")
                            .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text("优先显示本机 Clash Verge 元数据；用量统一按 1024 进制标注为 GiB。例如已用 80.9 GiB / 总额 1024 GiB，剩余约 943 GiB，两者是同一组数据。不会访问机场网页、订阅 URL 或 Token。")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Mihomo 本地控制器", systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 12, weight: .bold))
                        Spacer()
                        Button(store.isCheckingClashController ? "发现中…" : "自动发现") { store.autoDiscoverClashController() }
                            .controlSize(.mini).disabled(store.isCheckingClashController)
                    }
                    Toggle("使用控制器刷新代理提供者", isOn: $store.clashControllerEnabled).toggleStyle(.switch).controlSize(.mini)
                    if store.clashControllerEnabled {
                        FocusableTextField(text: $store.clashControllerURL, placeholder: "自动发现或手动填入 127.0.0.1:端口", onSubmit: store.inspectClashController).frame(height: 24)
                        SecureField(store.credentialVaultUnlocked ? "控制器 Secret（统一保险库）" : "先解锁保险库后填写 Secret", text: $store.clashControllerSecret)
                            .textFieldStyle(.roundedBorder).disabled(!store.credentialVaultUnlocked)
                        HStack {
                            Button("验证连接") { store.inspectClashController() }.controlSize(.mini).disabled(store.isCheckingClashController)
                            Button("同步并重读") { store.refreshClashQuota() }.controlSize(.mini).disabled(store.isRefreshingClash || store.isCheckingClashController)
                            Spacer()
                            Text(store.clashCredentialStatus).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Text(store.clashSyncEvidence)
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("飞书告警", systemImage: "bell.badge").font(.system(size: 12, weight: .bold))
                        Spacer(); Toggle("启用", isOn: $store.feishuAlertsEnabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }
                    SecureField(store.credentialVaultUnlocked ? "飞书群机器人 Webhook" : "解锁保险库后可填写 Webhook", text: $store.feishuWebhook)
                        .textFieldStyle(.roundedBorder).disabled(!store.credentialVaultUnlocked)
                    SecureField(store.credentialVaultUnlocked ? "签名密钥（可选）" : "解锁保险库后可填写签名密钥", text: $store.feishuSigningSecret)
                        .textFieldStyle(.roundedBorder).disabled(!store.credentialVaultUnlocked)
                    HStack {
                        Stepper("同类告警冷却 \(store.alertCooldownMinutes) 分钟", value: $store.alertCooldownMinutes, in: 5...240, step: 5)
                        Spacer(); Text(store.feishuTestStatus).foregroundStyle(.secondary).lineLimit(1)
                        Button("保存") { store.saveCredentialVault() }.disabled(!store.credentialVaultUnlocked || store.feishuWebhook.isEmpty)
                        Button("发送测试") { store.testFeishuAlert() }.disabled(store.feishuWebhook.isEmpty || !store.credentialVaultUnlocked)
                    }.controlSize(.mini).font(.system(size: 8.5))
                    Text(store.feishuCredentialStatus).font(.system(size: 8.5)).foregroundStyle(.secondary)
                    Text("填写后点击设置页顶部“保存全部变更”。仅发送异常首次触发与恢复；凭据不进入事件账本、配置导出或诊断报告。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
            }
            Card {
                VStack(spacing: 9) {
                    HStack { Text("浮窗透明度"); Slider(value: $state.opacity, in: 0.35...1); Text("\(Int(state.opacity * 100))%") }
                    HStack { Toggle("只在当前桌面显示", isOn: $state.currentDesktopOnly).help("关闭后浮窗会出现在所有 macOS 虚拟桌面"); Spacer(); Toggle("程序坞图标", isOn: $state.showInDock) }
                    HStack {
                        Text("菜单栏入口固定显示为 ● PD").foregroundStyle(.secondary)
                        Spacer()
                        Button("立即重建") { state.requestMenuBarRepair() }
                    }
                }.toggleStyle(.switch).controlSize(.mini).font(.system(size: 9.5))
            }
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("外观主题").font(.system(size: 12, weight: .bold))
                        Spacer()
                        Menu(state.floatingTheme.label) {
                            ForEach(FloatingTheme.allCases, id: \.self) { theme in
                                Button(theme.label) { state.floatingTheme = theme }
                            }
                        }.controlSize(.mini)
                    }
                    if state.floatingTheme == .custom {
                        ColorPicker("自定义背景色", selection: $state.customBackground, supportsOpacity: false)
                            .controlSize(.small)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 7), count: 6), alignment: .leading, spacing: 7) {
                        ForEach(FloatingTheme.allCases.filter { $0 != .custom }, id: \.self) { theme in
                            Button { state.floatingTheme = theme } label: {
                                Circle().fill(theme.background)
                                    .overlay(Circle().stroke(theme.accent.opacity(0.9), lineWidth: state.floatingTheme == theme ? 2.5 : 0.5))
                                    .overlay { if state.floatingTheme == theme { Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(theme.isDark ? .white : theme.accent) } }
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("切换为\(theme.label)主题")
                        }
                        Button { state.floatingTheme = .custom } label: {
                            Image(systemName: "paintpalette.fill").font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .foregroundStyle(state.floatingTheme == .custom ? state.panelAccent : .secondary)
                                .background(Color.primary.opacity(0.08), in: Circle())
                        }.buttonStyle(.plain).help("使用自定义背景色")
                    }
                    HStack(spacing: 8) {
                        Text("浅").foregroundStyle(.secondary)
                        Slider(value: $state.themeDepth, in: 0...1)
                        Text("深").foregroundStyle(.secondary)
                        Text("\(Int(state.themeDepth * 100))%").frame(width: 30, alignment: .trailing)
                    }.font(.system(size: 8.5))
                    Text(state.floatingTheme.description).font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("紧凑浮窗").font(.system(size: 12, weight: .bold))
                    Picker("信息密度", selection: $state.compactDensity) {
                        ForEach(CompactDensity.allCases, id: \.self) { density in Text(density.label).tag(density) }
                    }.pickerStyle(.segmented)
                    Text(state.compactDensity == .minimal
                         ? "极简：工作状态与当前最重要提醒，宽约 330px。"
                         : "平衡：额外显示专注、Codex、Clash 和天气胶囊，宽约 390px。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("语言").font(.system(size: 12, weight: .bold))
                        Spacer()
                        Picker("语言", selection: $state.appLanguage) {
                            ForEach(AppLanguage.allCases, id: \.self) { language in Text(language.label).tag(language) }
                        }.labelsHidden().frame(width: 150)
                    }
                    Text("切换后立即刷新已本地化的导航、按钮、设置与空状态；第三方诊断证据和动态内容可保留原始语言。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func quotaStat(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 7.5, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
    }
}

private struct PanelDragHandle: NSViewRepresentable {
    var onDoubleClick: () -> Void = {}

    func makeNSView(context: Context) -> DragView {
        let view = DragView(onDoubleClick: onDoubleClick)
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) { nsView.onDoubleClick = onDoubleClick }

    final class DragView: NSView {
        private var isDragArmed = false
        private var dragWorkItem: DispatchWorkItem?
        var onDoubleClick: () -> Void

        init(onDoubleClick: @escaping () -> Void) {
            self.onDoubleClick = onDoubleClick
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func mouseDown(with event: NSEvent) {
            dragWorkItem?.cancel()
            if event.clickCount >= 2 { onDoubleClick(); return }
            isDragArmed = false
            let work = DispatchWorkItem { [weak self] in self?.isDragArmed = true }
            dragWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
        override func mouseDragged(with event: NSEvent) { if isDragArmed { window?.performDrag(with: event) } }
        override func mouseUp(with event: NSEvent) { dragWorkItem?.cancel(); isDragArmed = false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}

private struct RemoteDeviceQuickSettings: View {
    @ObservedObject var store: MonitorStore
    let deviceID: UUID
    let dismiss: () -> Void

    private var device: RemoteDeviceConfiguration? { store.remoteDevices.first { $0.id == deviceID } }
    private var snapshot: RemoteDeviceSnapshot? { store.remoteSnapshots[deviceID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device?.name ?? "设备设置").font(.system(size: 13, weight: .bold))
                    Text(snapshot?.health.label ?? "等待状态").font(.system(size: 8.5)).foregroundStyle(snapshot?.health.color ?? .secondary)
                }
                Spacer()
                Button("完成", action: dismiss).controlSize(.small)
            }
            Divider()
            HStack {
                Button(device?.pinned == true ? "取消置顶" : "置顶") { store.toggleRemotePinned(deviceID) }
                Button("上移") { store.moveRemoteDevice(deviceID, direction: -1) }
                Button("下移") { store.moveRemoteDevice(deviceID, direction: 1) }
            }.controlSize(.small)
            VStack(alignment: .leading, spacing: 6) {
                Text("网络范围").font(.system(size: 10, weight: .semibold))
                Picker("网络范围", selection: Binding(
                    get: { device?.networkScope ?? .automatic },
                    set: { store.setRemoteNetworkScope(deviceID, $0) }
                )) {
                    ForEach(RemoteNetworkScope.allCases, id: \.self) { Text(LocalizedStringKey($0.label)).tag($0) }
                }.pickerStyle(.radioGroup).labelsHidden()
                Text(networkScopeHelp).font(.system(size: 8)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Toggle("显示进程用户名", isOn: Binding(
                get: { device?.collectProcessOwners ?? false },
                set: { _ in store.toggleRemoteProcessOwners(deviceID) }
            ))
            Toggle("采集 Slurm 当前用户任务", isOn: Binding(
                get: { device?.collectSchedulerJobs ?? false },
                set: { _ in store.toggleRemoteSchedulerJobs(deviceID) }
            ))
            Picker("任务识别", selection: Binding(
                get: { device?.taskDisclosureMode ?? .schedulerOnly },
                set: { store.setRemoteTaskDisclosureMode(deviceID, $0) }
            )) {
                ForEach(RemoteTaskDisclosureMode.allCases, id: \.self) { Text(LocalizedStringKey($0.label)).tag($0) }
            }.pickerStyle(.menu)
            HStack {
                Button { store.refreshRemoteDevice(deviceID) } label: { Label("立即刷新", systemImage: "arrow.clockwise") }
                Button { store.copyRemoteDiagnostic(deviceID) } label: { Label("复制诊断", systemImage: "doc.on.doc") }
            }.controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
        .onDisappear { if device == nil { dismiss() } }
    }

    private var networkScopeHelp: String {
        switch device?.networkScope ?? .automatic {
        case .automatic: "由当前网络类型与连续探测结果自动判断。"
        case .localLAN: "离开局域网时标记为预期离线，暂停重复告警。"
        case .vpn: "VPN 未连接时暂停探测，不生成 SSH 故障风暴。"
        case .publicInternet: "任何可用网络下均尝试连接，适合公网主机。"
        }
    }
}

private struct AmbientSoundPanel: View {
    @ObservedObject var service: AmbientSoundService
    @State private var stopMinutes = 0
    @State private var showFavorites = false
    @State private var ambientQuery = ""
    @State private var ambientPage = 0
    @State private var ambientCategoryID: String?
    @State private var customTimerMinutes = 25
    @State private var showCustomTimer = false
    @State private var showAllAmbientLicenses = false

    var body: some View {
        VStack(spacing: 11) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("专注声音", systemImage: "speaker.wave.2.fill").font(.system(size: 13, weight: .bold, design: .rounded))
                        Spacer()
                        Badge(text: playbackBadge, color: service.isPlaying ? .green : service.playbackState == .failed ? .red : .secondary)
                    }
                    Text("默认静音 · 单音频流 · 不保存播放历史 · 不建立离线音频资料库")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                    Picker("声音类型", selection: $service.browserKind) {
                        ForEach(MediaKind.allCases, id: \.self) { Text(LocalizedStringKey($0.label)).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()

                    HStack {
                        Text("网络").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.secondary)
                        Picker("音频网络模式", selection: $service.networkMode) {
                            ForEach(MediaNetworkMode.allCases, id: \.self) { Text(LocalizedStringKey($0.label)).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    Text(networkModeHelp).font(.system(size: 7.5)).foregroundStyle(.tertiary)

                    switch service.browserKind {
                    case .ambient: ambientCatalog
                    case .music: directoryCatalog(kind: .music)
                    case .radio: directoryCatalog(kind: .radio)
                    }

                    if let item = service.selectedItem {
                        if item.kind == .ambient { AmbientSceneDeck(item: item, state: service.playbackState) }
                        else if item.kind == .music { RetroCassetteDeck(item: item, isPlaying: service.isPlaying) }
                        else { RetroRadioDeck(item: item, state: service.playbackState) }
                    }
                    playerControls
                    Text(service.status).font(.system(size: 8.5, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 7) {
                    Label("来源与许可", systemImage: "checkmark.shield.fill").font(.system(size: 11, weight: .bold))
                    Text("环境音是 Freesound 的 CC0 录音；工作音乐和广播来自 Radio Browser 第三方公开目录，版权、地区与可用性由各电台负责。PulseDock 只接受 HTTPS 流，点击播放前不会连接音频。")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                    if let item = service.selectedItem {
                        Button("查看当前音源：\(item.provider) · \(item.license)") { NSWorkspace.shared.open(item.sourcePage) }
                            .buttonStyle(.link).controlSize(.mini)
                    }
                    DisclosureGroup("查看全部环境音来源（\(service.tracks.count)）", isExpanded: $showAllAmbientLicenses) {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(service.tracks) { track in
                                Button("\(track.title) · \(track.author) · \(track.license)") { NSWorkspace.shared.open(track.sourcePage) }
                                    .buttonStyle(.link).controlSize(.mini)
                            }
                        }.padding(.top, 4)
                    }.font(.system(size: 8.5, weight: .semibold))
                    Button("打开 Radio Browser 数据源说明") {
                        NSWorkspace.shared.open(URL(string: "https://www.radio-browser.info/")!)
                    }.buttonStyle(.link).controlSize(.mini)
                }
            }
        }
        .onChange(of: service.stopAt) { _, deadline in
            if deadline == nil { stopMinutes = 0 }
        }
    }

    /// The control deck is intentionally partitioned.  An SF Symbol changing
    /// from `speaker.wave.1` to `speaker.wave.2` must never reclaim width from
    /// the timer or playback-mode controls.
    private var playerControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                transportControls.frame(width: 118, alignment: .leading)
                Divider().frame(height: 22)
                volumeControls.frame(width: 150)
                // Keep any flexible space between volume and the trailing
                // controls.  Nothing may be left stranded after playback
                // mode, otherwise the bar reads as an unfinished layout.
                Spacer(minLength: 12)
                timerControls.fixedSize()
                playbackModeMenu.fixedSize()
            }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    transportControls
                    Spacer(minLength: 0)
                    timerControls
                    playbackModeMenu
                }
                HStack { volumeControls.frame(width: 170); Spacer(minLength: 0) }
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 5) {
            playerButton("backward.fill", help: "上一条") { service.previous() }
            playerButton(service.playbackState == .failed ? "arrow.clockwise" : service.isPlaying ? "pause.fill" : "play.fill", help: service.playbackState == .failed ? "重试" : service.isPlaying ? "暂停" : "继续") {
                if service.playbackState == .failed, let item = service.selectedItem { service.play(item) }
                else if service.isPlaying { service.pause() }
                else { service.resume() }
            }
            playerButton("forward.fill", help: "下一条") { service.next() }
            playerButton("stop.fill", help: "停止") { service.stop() }
        }
    }

    private func playerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 21, height: 21) }
            .buttonStyle(.bordered).controlSize(.small)
            .frame(width: 24, height: 24)
            .disabled(service.selectedItem == nil)
            .help(help)
    }

    private var volumeControls: some View {
        HStack(spacing: 5) {
            Button { service.toggleMute() } label: {
                Image(systemName: service.volume <= 0.01 ? "speaker.slash.fill" : service.volume < 0.35 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(service.volume <= 0.01 ? "恢复声音" : "静音")
            Slider(value: $service.volume, in: 0...0.8)
                .frame(width: 118)
                .accessibilityLabel("音量")
        }
        .frame(width: 150, alignment: .leading)
    }

    private var timerControls: some View {
        Button(action: cycleTimer) {
            HStack(spacing: 4) {
                Image(systemName: stopMinutes == 0 ? "timer" : "timer.circle.fill")
                if stopMinutes > 0 { Text("\(stopMinutes)m").font(.system(size: 9, weight: .bold, design: .rounded)) }
            }
            // Deliberate horizontal breathing room prevents the timer glyph
            // from touching the capsule edge when a minute label is visible.
            .padding(.horizontal, 7)
            .frame(minWidth: stopMinutes == 0 ? 34 : 50, minHeight: 30)
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .help(stopMinutes == 0 ? "单击设定 15 分钟后停止；右键可自定义" : "单击切换 15/30/60 分钟或关闭；右键可自定义")
        .contextMenu {
                Button("15 分钟") { setTimer(15) }
                Button("30 分钟") { setTimer(30) }
                Button("60 分钟") { setTimer(60) }
                Divider()
                Button("自定义…") { showCustomTimer = true }
                if stopMinutes > 0 { Button("关闭定时") { setTimer(0) } }
        }
        .popover(isPresented: $showCustomTimer) {
            VStack(alignment: .leading, spacing: 8) {
                Text("自定义停止时间").font(.headline)
                Stepper("\(customTimerMinutes) 分钟", value: $customTimerMinutes, in: 1...240)
                HStack {
                    Button("取消") { showCustomTimer = false }
                    Spacer()
                    Button("开始计时") { setTimer(customTimerMinutes); showCustomTimer = false }
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(12).frame(width: 220)
        }
    }

    private var playbackBadge: String {
        switch service.playbackState {
        case .idle: "待机"
        case .loading: "连接中"
        case .playing: "播放中"
        case .paused: "已暂停"
        case .stalled: "缓冲中"
        case .failed: "播放异常"
        }
    }

    private var ambientCatalog: some View {
        let categoryIDs = service.ambientCategories.first(where: { $0.id == ambientCategoryID })?.trackIDs
        let source = showFavorites ? service.favoriteItems.filter { $0.kind == .ambient } : service.tracks.map(\.mediaItem)
        let all = source.filter {
            (categoryIDs == nil || categoryIDs?.contains($0.id) == true) &&
            (ambientQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(ambientQuery) || $0.subtitle.localizedCaseInsensitiveContains(ambientQuery) || $0.provider.localizedCaseInsensitiveContains(ambientQuery))
        }
        let start = min(ambientPage * 6, max(0, all.count - 1))
        let visible = Array(all.dropFirst(start).prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(showFavorites ? "我的收藏" : "发现").font(.system(size: 9.5, weight: .semibold))
                Spacer()
                Button { showFavorites.toggle(); ambientPage = 0 } label: {
                    Label(showFavorites ? "返回目录" : "我的收藏", systemImage: showFavorites ? "rectangle.grid.2x2" : "heart.fill")
                }.controlSize(.mini)
            }
            if !showFavorites {
                HStack {
                    Text("按声景类型筛选").font(.system(size: 8)).foregroundStyle(.secondary)
                    Spacer()
                }
                DiscoveryChipFlow(horizontalSpacing: 6, verticalSpacing: 6) {
                    DiscoveryChip(title: "全部", symbol: "square.grid.2x2", isSelected: ambientCategoryID == nil) {
                        ambientCategoryID = nil
                        ambientPage = 0
                    }
                    ForEach(service.ambientCategories) { category in
                        DiscoveryChip(title: category.title, symbol: category.symbol, isSelected: ambientCategoryID == category.id) {
                            ambientCategoryID = category.id
                            ambientPage = 0
                        }
                    }
                }
            }
            FocusableTextField(text: $ambientQuery, placeholder: "搜索环境音", onSubmit: { ambientPage = 0 }).frame(height: 23)
            if visible.isEmpty {
                Text(showFavorites ? "还没有收藏环境音。点击音源旁的爱心即可加入。" : "当前筛选没有可用环境音。")
                    .font(.system(size: 9)).foregroundStyle(.secondary).padding(.vertical, 10)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    ForEach(visible) { mediaButton($0) }
                }
            }
            MediaPager(currentPage: ambientPage, canGoForward: start + 6 < all.count) { ambientPage = max(0, min($0, max(0, (all.count - 1) / 6))) }
            Text("共 \(all.count) 个经许可复核的环境音 · 每页 6 个 · 点击后才连接音频")
                .font(.system(size: 7.5)).foregroundStyle(.tertiary)
        }

    }

    private func cycleTimer() {
        let choices = [0, 15, 30, 60]
        let current = choices.firstIndex(of: stopMinutes) ?? 0
        let next = choices[(current + 1) % choices.count]
        setTimer(next)
    }

    private func setTimer(_ minutes: Int) {
        stopMinutes = minutes
        service.scheduleStop(minutes: minutes == 0 ? nil : minutes)
    }

    private func directoryCatalog(kind: MediaKind) -> some View {
        let scenes = kind == .music ? service.musicScenes : service.radioScenes
        let allResults = showFavorites ? service.favoriteItems.filter { $0.kind == kind } : service.directoryItems.filter { $0.kind == kind }
        let results = Array(allResults.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(showFavorites ? "我的收藏" : "发现").font(.system(size: 9.5, weight: .semibold))
                Spacer()
                Button { showFavorites.toggle() } label: { Label(showFavorites ? "返回目录" : "我的收藏", systemImage: showFavorites ? "rectangle.grid.2x2" : "heart.fill") }.controlSize(.mini)
            }
            if !showFavorites {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(scenes) { scene in
                    Button { service.load(scene: scene, for: kind) } label: {
                        Label {
                            Text(LocalizedStringKey(scene.title))
                        } icon: {
                            Image(systemName: scene.symbol)
                        }
                    }.controlSize(.mini).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                FocusableTextField(
                    text: Binding(get: { service.query(for: kind) }, set: { service.setQuery($0, for: kind) }),
                    placeholder: kind == .music ? "搜索工作音乐电台" : "搜索广播台",
                    onSubmit: { service.search(kind: kind) }
                ).frame(height: 23)
                Button("搜索") { service.search(kind: kind) }.disabled(service.query(for: kind).trimmingCharacters(in: .whitespaces).isEmpty)
            }.controlSize(.small)
            }
            HStack {
                if service.directoryLoading { ProgressView().controlSize(.small) }
                Text(service.directoryStatus).font(.system(size: 8)).foregroundStyle(.secondary)
                Text(service.directorySourceSummary).font(.system(size: 7.5)).foregroundStyle(.tertiary)
            }
            if results.isEmpty {
                Text(showFavorites ? "还没有收藏此类音源。点击结果旁的爱心即可加入。" : (kind == .music ? "选择一个工作场景后显示公开音乐流。" : "选择分类或搜索台名后显示网络广播。"))
                    .font(.system(size: 9)).foregroundStyle(.secondary).padding(.vertical, 10)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    ForEach(results) { mediaButton($0) }
                }
            }
            if !showFavorites {
                MediaPager(currentPage: service.page(for: kind), canGoForward: service.canGoForward(for: kind) && !service.directoryLoading) {
                    service.goToPage($0, kind: kind)
                }.disabled(service.directoryLoading)
            }
        }
    }

    private var playbackModeMenu: some View {
        let kind = service.selectedItem?.kind ?? service.browserKind
        let current = service.mode(for: kind)
        return Button {
            service.cycleMode(for: kind)
        } label: {
            Image(systemName: current.symbol).frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .contextMenu {
            ForEach(service.availableModes(for: kind), id: \.self) { mode in
                Button { service.setMode(mode, for: kind) } label: {
                    Label(mode.label, systemImage: mode.symbol)
                }
            }
        }
        .help("播放顺序：\(current.label) · 单击切换，右键查看全部")
    }

    private var networkModeHelp: String {
        switch service.networkMode {
        case .smart: "系统路由缓冲 9 秒后自动尝试会话级直连；不修改 Clash。"
        case .followSystem: "完全遵循系统与 Clash 当前路由。"
        case .directOnly: "仅 PulseDock 音频绕过系统代理；其他应用不受影响。"
        }
    }

    private func mediaButton(_ item: MediaStreamItem) -> some View {
        let selected = service.selectedItem?.id == item.id
        return HStack(spacing: 5) {
            Button { service.toggle(item) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: item.symbol).font(.system(size: 14)).foregroundStyle(selected ? .white : .cyan)
                        Spacer()
                        Image(systemName: selected && service.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    }
                    Text(item.title).font(.system(size: 10, weight: .bold)).lineLimit(1)
                    let availability = service.sourceAvailabilityNote(item)
                    Text(availability ?? item.subtitle)
                        .font(.system(size: 7.5))
                        .foregroundStyle(selected ? Color.white.opacity(0.78) : availability == nil ? Color.secondary : Color.orange)
                        .lineLimit(1)
                }
            }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
            Button { service.toggleFavorite(item) } label: {
                Image(systemName: service.favoriteIDs.contains(item.id) ? "heart.fill" : "heart")
                    .foregroundStyle(service.favoriteIDs.contains(item.id) ? Color.pink : (selected ? Color.white.opacity(0.8) : Color.secondary))
            }.buttonStyle(.plain).help(service.favoriteIDs.contains(item.id) ? "取消收藏" : "收藏")
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(selected ? .white : .primary)
        .background(selected ? Color.indigo : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Cursor-based sources do not expose a reliable total page count. This pager
/// therefore jumps directly to an offset without downloading every station:
/// neighbouring pages and an explicitly entered page are fetched on demand.
private struct MediaPager: View {
    let currentPage: Int
    let canGoForward: Bool
    let go: (Int) -> Void
    @State private var showJump = false
    @State private var pageText = ""

    private var nearbyPages: [Int] {
        let lower = max(0, currentPage - 2)
        let upper = currentPage + (canGoForward ? 2 : 0)
        return Array(lower...max(lower, upper))
    }

    var body: some View {
        HStack(spacing: 5) {
            Button { go(max(0, currentPage - 2)) } label: { Image(systemName: "backward.end.fill") }
                .disabled(currentPage == 0).help("向前两页")
            Button { go(max(0, currentPage - 1)) } label: { Image(systemName: "chevron.left") }
                .disabled(currentPage == 0).help("上一页")
            Spacer(minLength: 4)
            ForEach(nearbyPages, id: \.self) { page in
                Button("\(page + 1)") { go(page) }
                    .buttonStyle(.bordered)
                    .tint(page == currentPage ? .blue : .secondary)
                    .controlSize(.mini)
                    .disabled(page > currentPage && !canGoForward)
            }
            Button { pageText = String(currentPage + 1); showJump = true } label: {
                Image(systemName: "number.square")
            }
            .help("跳转到指定页")
            .popover(isPresented: $showJump) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("跳转到指定页").font(.headline)
                    FocusableTextField(text: $pageText, placeholder: "页码，例如 12", onSubmit: jump).frame(height: 24)
                    HStack { Spacer(); Button("跳转", action: jump).disabled(Int(pageText) == nil) }
                }.padding(12).frame(width: 210)
            }
            Spacer(minLength: 4)
            Button { go(currentPage + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(!canGoForward).help("下一页")
            Button { go(currentPage + 2) } label: { Image(systemName: "forward.end.fill") }
                .disabled(!canGoForward).help("向后两页")
        }.controlSize(.mini)
    }

    private func jump() {
        guard let page = Int(pageText.trimmingCharacters(in: .whitespacesAndNewlines)), page > 0 else { return }
        go(page - 1)
        showJump = false
    }
}

private struct RetroCassetteDeck: View {
    let item: MediaStreamItem
    let isPlaying: Bool

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WORK TAPE").font(.system(size: 7, weight: .black, design: .monospaced)).foregroundStyle(.orange)
                    Text(item.title).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
                    Text(item.subtitle).font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if isPlaying {
                    TimelineView(.periodic(from: .now, by: 0.25)) { context in
                        let angle = context.date.timeIntervalSinceReferenceDate * 55
                        HStack(spacing: 13) {
                            cassetteReel(angle: angle)
                            cassetteReel(angle: -angle)
                        }
                    }
                } else {
                    HStack(spacing: 13) {
                        cassetteReel(angle: 0)
                        cassetteReel(angle: 0)
                    }
                }
            }
            Capsule().fill(Color.orange.opacity(0.5)).frame(height: 3)
        }
        .padding(10)
        .background(Color(red: 0.15, green: 0.13, blue: 0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .foregroundStyle(.white)
    }

    private func cassetteReel(angle: Double) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.55), lineWidth: 2).frame(width: 25, height: 25)
            Image(systemName: "gearshape.fill").font(.system(size: 15)).foregroundStyle(.white.opacity(0.8)).rotationEffect(.degrees(angle))
        }
    }
}

/// A deliberately lightweight procedural scene: it is not a downloaded video
/// or a hidden animated wallpaper.  The scene redraws only while audio is
/// active and uses the selected environment sound to establish its mood.
private struct AmbientSceneDeck: View {
    let item: MediaStreamItem
    let state: MediaPlaybackState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: isAnimated ? 1.0 / 10.0 : 1.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Canvas { graphics, size in
                    drawScene(graphics: &graphics, size: size, phase: isAnimated ? phase : 0)
                }
                .mask(RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AMBIENT SCENE").font(.system(size: 7, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                        Text(item.title).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text(item.subtitle).font(.system(size: 7.5)).foregroundStyle(.white.opacity(0.82)).lineLimit(1)
                    }
                    Spacer()
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                        Text(style.label).font(.system(size: 6.5, weight: .semibold)).foregroundStyle(.white.opacity(0.68))
                    }
                }.padding(11)
            }
        }
        .frame(height: 82)
        .accessibilityLabel("\(item.title) 的动态环境场景")
    }

    private var style: AmbientSceneStyle { AmbientTrack.sceneStyle(for: item.id) ?? .brownNoise }
    private var isAnimated: Bool { state == .playing && !reduceMotion }

    private var colors: [Color] {
        return switch style {
        case .rainWindow, .thunderstorm: [Color(red: 0.08, green: 0.14, blue: 0.22), Color(red: 0.22, green: 0.31, blue: 0.39)]
        case .cityRain: [Color(red: 0.10, green: 0.14, blue: 0.23), Color(red: 0.28, green: 0.20, blue: 0.29)]
        case .openWind, .forestCanopy, .forestCreek: [Color(red: 0.07, green: 0.20, blue: 0.16), Color(red: 0.25, green: 0.38, blue: 0.25)]
        case .oceanShore, .underwater: [Color(red: 0.03, green: 0.20, blue: 0.31), Color(red: 0.08, green: 0.42, blue: 0.48)]
        case .fireplaceClose, .hearthRoom: [Color(red: 0.16, green: 0.08, blue: 0.04), Color(red: 0.39, green: 0.20, blue: 0.09)]
        case .cafeInterior, .libraryDesk, .typingDesk: [Color(red: 0.20, green: 0.13, blue: 0.08), Color(red: 0.42, green: 0.29, blue: 0.17)]
        case .tramWindow, .trainWindow: [Color(red: 0.08, green: 0.17, blue: 0.26), Color(red: 0.19, green: 0.32, blue: 0.40)]
        case .cityNight, .nightNature: [Color(red: 0.06, green: 0.10, blue: 0.20), Color(red: 0.16, green: 0.17, blue: 0.32)]
        case .brownNoise: [Color(red: 0.13, green: 0.10, blue: 0.08), Color(red: 0.31, green: 0.22, blue: 0.16)]
        }
    }

    private func drawScene(graphics: inout GraphicsContext, size: CGSize, phase: Double) {
        switch style {
        case .rainWindow: drawRain(&graphics, size: size, phase: phase, city: false, thunder: false)
        case .cityRain: drawRain(&graphics, size: size, phase: phase, city: true, thunder: false)
        case .thunderstorm: drawRain(&graphics, size: size, phase: phase, city: false, thunder: true)
        case .openWind: drawWind(&graphics, size: size, phase: phase)
        case .forestCanopy: drawForest(&graphics, size: size, phase: phase)
        case .oceanShore: drawOcean(&graphics, size: size, phase: phase)
        case .forestCreek: drawCreek(&graphics, size: size, phase: phase)
        case .underwater: drawUnderwater(&graphics, size: size, phase: phase)
        case .fireplaceClose: drawFireplace(&graphics, size: size, phase: phase, room: false)
        case .hearthRoom: drawFireplace(&graphics, size: size, phase: phase, room: true)
        case .cafeInterior: drawCafe(&graphics, size: size, phase: phase)
        case .libraryDesk: drawLibrary(&graphics, size: size, phase: phase, typing: false)
        case .typingDesk: drawLibrary(&graphics, size: size, phase: phase, typing: true)
        case .tramWindow, .trainWindow: drawTrain(&graphics, size: size, phase: phase, tram: style == .tramWindow)
        case .cityNight: drawNightCity(&graphics, size: size, phase: phase)
        case .nightNature: drawNightNature(&graphics, size: size, phase: phase)
        case .brownNoise: drawBrownNoise(&graphics, size: size, phase: phase)
        }
    }

    private func drawRain(_ graphics: inout GraphicsContext, size: CGSize, phase: Double, city: Bool, thunder: Bool) {
        if city { drawSkyline(&graphics, size: size, light: .orange.opacity(0.18)) }
        graphics.stroke(Path(CGRect(x: size.width * 0.60, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.20)), lineWidth: 1)
        graphics.stroke(Path(CGRect(x: 0, y: size.height * 0.36, width: size.width, height: 1)), with: .color(.white.opacity(0.15)), lineWidth: 1)
        for index in 0..<30 {
            let x = CGFloat(index * 47 % 101) / 100 * size.width
            let y = (CGFloat(index * 31 % 100) / 100 * (size.height + 18) + CGFloat(phase * 31)).truncatingRemainder(dividingBy: size.height + 18) - 9
            var drop = Path(); drop.move(to: CGPoint(x: x, y: y)); drop.addLine(to: CGPoint(x: x - 3, y: y + 12))
            graphics.stroke(drop, with: .color(.white.opacity(city ? 0.25 : 0.19)), lineWidth: 0.8)
        }
        if thunder, phase > 0, Int(phase * 1.4).isMultiple(of: 19) {
            graphics.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.16)))
        }
    }

    private func drawOcean(_ graphics: inout GraphicsContext, size: CGSize, phase: Double) {
        for layer in 0..<3 {
            let base = size.height * (0.48 + CGFloat(layer) * 0.15)
            var path = Path(); path.move(to: CGPoint(x: 0, y: base))
            for step in 0...18 {
                let x = CGFloat(step) / 18 * size.width
                let frequency = Double(step) * 0.68 + phase * (0.7 + Double(layer) * 0.2)
                let amplitude = Double(5 + layer * 2)
                let y = base + CGFloat(sin(frequency) * amplitude)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height)); path.addLine(to: CGPoint(x: 0, y: size.height)); path.closeSubpath()
            graphics.fill(path, with: .color(.white.opacity(0.07 + Double(layer) * 0.05)))
        }
    }

    private func drawCreek(_ graphics: inout GraphicsContext, size: CGSize, phase: Double) {
        for index in 0..<7 {
            let y = CGFloat(14 + index * 10)
            var stream = Path(); stream.move(to: CGPoint(x: -10, y: y))
            for step in 0...14 {
                let x = CGFloat(step) / 14 * (size.width + 20) - 10
                stream.addLine(to: CGPoint(x: x, y: y + CGFloat(sin(Double(step) * 0.9 + phase * 0.8 + Double(index)) * 2.4)))
            }
            graphics.stroke(stream, with: .color(.white.opacity(index.isMultiple(of: 2) ? 0.20 : 0.11)), lineWidth: 1)
        }
        for index in 0..<5 {
            let x = size.width * CGFloat(index + 1) / 6
            graphics.fill(Path(ellipseIn: CGRect(x: x, y: size.height * 0.68, width: 24, height: 11)), with: .color(.black.opacity(0.14)))
        }
    }

    private func drawUnderwater(_ graphics: inout GraphicsContext, size: CGSize, phase: Double) {
        for index in 0..<11 {
            let x = size.width * CGFloat(index * 37 % 97) / 100
            let y = size.height - (CGFloat(index * 29 % 100) / 100 * size.height + CGFloat(phase * Double(5 + index % 4))).truncatingRemainder(dividingBy: size.height)
            let d = CGFloat(2 + index % 4)
            graphics.stroke(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.white.opacity(0.25)), lineWidth: 0.7)
        }
        for index in 0..<5 {
            let x = size.width * CGFloat(index) / 4
            graphics.stroke(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.06)), lineWidth: 4)
        }
    }

    private func drawWind(_ graphics: inout GraphicsContext, size: CGSize, phase: Double) {
        for index in 0..<6 {
            let y = CGFloat(12 + index * 12)
            var gust = Path(); gust.move(to: CGPoint(x: -14, y: y))
            for step in 0...13 {
                let x = CGFloat(step) / 13 * (size.width + 28) - 14
                gust.addLine(to: CGPoint(x: x, y: y + CGFloat(sin(Double(step) * 0.72 + phase + Double(index)) * 3.5)))
            }
            graphics.stroke(gust, with: .color(.white.opacity(index.isMultiple(of: 2) ? 0.18 : 0.09)), lineWidth: 1)
        }
    }

    private func drawForest(_ graphics: inout GraphicsContext, size: CGSize, phase: Double) {
        for index in 0..<7 {
            let x = size.width * CGFloat(index) / 6
            let width = CGFloat(16 + index % 3 * 8)
            graphics.fill(Path(CGRect(x: x - width / 2, y: size.height * 0.42, width: width * 0.18, height: size.height * 0.58)), with: .color(.black.opacity(0.16)))
            let drift = CGFloat(sin(phase * 0.4 + Double(index)) * 2)
            graphics.fill(Path(ellipseIn: CGRect(x: x - width / 2 + drift, y: size.height * 0.12, width: width, height: size.height * 0.50)), with: .color(.white.opacity(0.08)))
        }
        for index in 0..<8 {
            let x = size.width * CGFloat(index * 23 % 97) / 100
            let y = size.height * CGFloat(18 + index * 17 % 52) / 100
            graphics.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 6)), with: .color(.white.opacity(0.18)))
        }
    }

    private func drawFireplace(_ graphics: inout GraphicsContext, size: CGSize, phase: Double, room: Bool) {
        if room {
            graphics.fill(Path(CGRect(x: size.width * 0.60, y: size.height * 0.15, width: size.width * 0.23, height: size.height * 0.46)), with: .color(.black.opacity(0.18)))
            graphics.fill(Path(CGRect(x: size.width * 0.63, y: size.height * 0.20, width: size.width * 0.17, height: size.height * 0.34)), with: .color(.orange.opacity(0.10)))
        }
        let centerX = room ? size.width * 0.70 : size.width * 0.62
        graphics.fill(Path(roundedRect: CGRect(x: centerX - 28, y: size.height * 0.62, width: 56, height: 7), cornerRadius: 4), with: .color(.black.opacity(0.25)))
        graphics.fill(Path(roundedRect: CGRect(x: centerX - 19, y: size.height * 0.55, width: 38, height: 7), cornerRadius: 4), with: .color(.brown.opacity(0.55)))
        let pulse = 1 + CGFloat(sin(phase * 1.4) * 0.14)
        graphics.fill(Path(ellipseIn: CGRect(x: centerX - 13 * pulse, y: size.height * 0.31, width: 26 * pulse, height: size.height * 0.29)), with: .color(.orange.opacity(0.34)))
        graphics.fill(Path(ellipseIn: CGRect(x: centerX - 6 * pulse, y: size.height * 0.38, width: 12 * pulse, height: size.height * 0.20)), with: .color(.yellow.opacity(0.30)))
        for index in 0..<7 {
            let x = centerX - 24 + CGFloat(index * 8)
            let y = size.height * 0.28 - CGFloat((Int(phase * 3) + index * 7) % 22)
            graphics.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.orange.opacity(0.38)))
        }
    }

    private func drawCafe(_ graphics: inout GraphicsContext, size: CGSize, phase: Double) {
        graphics.fill(Path(CGRect(x: size.width * 0.54, y: 0, width: size.width * 0.27, height: size.height * 0.54)), with: .color(.white.opacity(0.08)))
        graphics.stroke(Path(CGRect(x: size.width * 0.54, y: 0, width: size.width * 0.27, height: size.height * 0.54)), with: .color(.white.opacity(0.18)), lineWidth: 1)
        graphics.fill(Path(CGRect(x: 0, y: size.height * 0.68, width: size.width, height: size.height * 0.32)), with: .color(.black.opacity(0.13)))
        let cup = CGRect(x: size.width * 0.67, y: size.height * 0.52, width: 35, height: 16)
        graphics.fill(Path(roundedRect: cup, cornerRadius: 5), with: .color(.white.opacity(0.27)))
        graphics.stroke(Path(ellipseIn: CGRect(x: cup.minX + 5, y: cup.minY - 3, width: 25, height: 7)), with: .color(.white.opacity(0.45)), lineWidth: 1)
        for index in 0..<2 {
            var steam = Path(); let x = cup.midX + CGFloat(index * 6 - 3)
            steam.move(to: CGPoint(x: x, y: cup.minY - 3))
            steam.addCurve(to: CGPoint(x: x + 2, y: cup.minY - 23), control1: CGPoint(x: x - 5, y: cup.minY - 10), control2: CGPoint(x: x + 7, y: cup.minY - 16 + CGFloat(sin(phase + Double(index)) * 2)))
            graphics.stroke(steam, with: .color(.white.opacity(0.24)), lineWidth: 1)
        }
    }

    private func drawLibrary(_ graphics: inout GraphicsContext, size: CGSize, phase: Double, typing: Bool) {
        graphics.fill(Path(CGRect(x: 0, y: size.height * 0.16, width: size.width, height: size.height * 0.54)), with: .color(.black.opacity(0.10)))
        for index in 0..<10 {
            let height = size.height * CGFloat(0.20 + Double(index % 4) * 0.05)
            let x = size.width * 0.46 + CGFloat(index) * 9
            graphics.fill(Path(CGRect(x: x, y: size.height * 0.65 - height, width: 6, height: height)), with: .color(.white.opacity(0.10 + Double(index % 2) * 0.04)))
        }
        graphics.fill(Path(roundedRect: CGRect(x: size.width * 0.18, y: size.height * 0.65, width: size.width * 0.35, height: 10), cornerRadius: 2), with: .color(.black.opacity(0.22)))
        if typing {
            for row in 0..<2 { for column in 0..<7 {
                let lit = (Int(phase * 5) + row * 7 + column) % 13 == 0
                graphics.fill(Path(roundedRect: CGRect(x: size.width * 0.23 + CGFloat(column) * 10, y: size.height * 0.50 + CGFloat(row) * 7, width: 7, height: 4), cornerRadius: 1), with: .color(.white.opacity(lit ? 0.45 : 0.13)))
            }}
        } else {
            graphics.fill(Path(roundedRect: CGRect(x: size.width * 0.24, y: size.height * 0.47, width: 50, height: 18), cornerRadius: 2), with: .color(.white.opacity(0.16)))
        }
    }

    private func drawTrain(_ graphics: inout GraphicsContext, size: CGSize, phase: Double, tram: Bool) {
        let window = CGRect(x: size.width * 0.48, y: size.height * 0.12, width: size.width * 0.34, height: size.height * 0.58)
        graphics.fill(Path(roundedRect: window, cornerRadius: 3), with: .color(.black.opacity(0.18)))
        graphics.stroke(Path(roundedRect: window, cornerRadius: 3), with: .color(.white.opacity(0.20)), lineWidth: 1)
        for index in 0..<7 {
            let x = window.minX + (CGFloat(index * 31 % 100) / 100 * window.width + CGFloat(phase * (tram ? 11 : 18))).truncatingRemainder(dividingBy: window.width)
            graphics.stroke(Path(CGRect(x: x, y: window.minY + 8, width: 1, height: window.height - 16)), with: .color(.white.opacity(0.15)), lineWidth: tram ? 2 : 1)
        }
        graphics.fill(Path(CGRect(x: 0, y: size.height * 0.74, width: size.width, height: size.height * 0.26)), with: .color(.black.opacity(0.15)))
    }

    private func drawNightCity(_ graphics: inout GraphicsContext, size: CGSize, phase: Double) {
        drawSkyline(&graphics, size: size, light: .cyan.opacity(0.25))
        for index in 0..<5 {
            let x = (CGFloat(index) * size.width / 5 + CGFloat(phase * 16)).truncatingRemainder(dividingBy: size.width)
            graphics.fill(Path(ellipseIn: CGRect(x: x, y: size.height * 0.80, width: 18, height: 2)), with: .color(.orange.opacity(0.35)))
        }
    }

    private func drawNightNature(_ graphics: inout GraphicsContext, size: CGSize, phase: Double) {
        graphics.fill(Path(ellipseIn: CGRect(x: size.width * 0.68, y: 12, width: 22, height: 22)), with: .color(.white.opacity(0.45)))
        for index in 0..<13 {
            let x = size.width * CGFloat(index * 43 % 101) / 100
            let y = size.height * CGFloat(25 + index * 23 % 62) / 100
            let glow = 0.08 + 0.22 * abs(sin(phase * 0.8 + Double(index)))
            graphics.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.5, height: 2.5)), with: .color(.yellow.opacity(glow)))
        }
        graphics.fill(Path(CGRect(x: 0, y: size.height * 0.76, width: size.width, height: size.height * 0.24)), with: .color(.black.opacity(0.17)))
    }

    private func drawBrownNoise(_ graphics: inout GraphicsContext, size: CGSize, phase: Double) {
        let bars = 26
        for index in 0..<bars {
            let x = CGFloat(index) / CGFloat(bars) * size.width
            let amplitude = 0.28 + 0.48 * abs(sin(Double(index) * 0.43 + phase * 0.7))
            let height = CGFloat(amplitude) * size.height * 0.50
            graphics.fill(Path(roundedRect: CGRect(x: x, y: (size.height - height) / 2, width: max(2, size.width / CGFloat(bars) - 3), height: height), cornerRadius: 1), with: .color(.white.opacity(0.12)))
        }
    }

    private func drawSkyline(_ graphics: inout GraphicsContext, size: CGSize, light: Color) {
        for index in 0..<13 {
            let width = size.width / 13 + 2
            let height = size.height * CGFloat(0.20 + Double(index * 7 % 34) / 100)
            let x = CGFloat(index) * (size.width / 13)
            graphics.fill(Path(CGRect(x: x, y: size.height * 0.72 - height, width: width, height: height)), with: .color(.black.opacity(0.18)))
            if index.isMultiple(of: 2) { graphics.fill(Path(CGRect(x: x + width * 0.45, y: size.height * 0.67 - height / 2, width: 2, height: 2)), with: .color(light)) }
        }
    }
}

private struct RetroRadioDeck: View {
    let item: MediaStreamItem
    let state: MediaPlaybackState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "radio.fill").font(.system(size: 29)).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
                Text([item.country, item.language, item.codec].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { index in
                        Capsule()
                            .fill(index < radioStateLights ? radioStateColor : Color.black.opacity(0.12))
                            .frame(height: 5)
                    }
                }
                Text("网络播放状态灯 · 不表示 FM 信号强度").font(.system(size: 6.8)).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack { Circle().stroke(.secondary, lineWidth: 3).frame(width: 26, height: 26); Text("TUNE").font(.system(size: 6, design: .monospaced)) }
        }
        .padding(10)
        .background(Color.brown.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var radioStateLights: Int {
        switch state {
        case .playing: 8
        case .loading, .stalled: 4
        case .paused: 2
        case .failed: 1
        case .idle: 0
        }
    }

    private var radioStateColor: Color {
        switch state {
        case .playing: .green
        case .failed: .red
        case .loading, .stalled: .orange
        case .paused, .idle: .secondary
        }
    }
}

private enum HolidayPresentation {
    static func color(for info: ChinaHolidayDayInfo) -> Color {
        switch info.kind {
        case .holiday: .red
        case .makeupWorkday: .orange
        case .normal: info.isWeekend ? .indigo : .blue
        }
    }

    static func symbol(for info: ChinaHolidayDayInfo) -> String {
        switch info.kind {
        case .holiday: "calendar.badge.checkmark"
        case .makeupWorkday: "calendar.badge.exclamationmark"
        case .normal: info.isWeekend ? "calendar.badge.minus" : "calendar"
        }
    }

    static func marker(for info: ChinaHolidayDayInfo) -> String? {
        switch info.kind {
        case .holiday: "休"
        case .makeupWorkday: "班"
        case .normal: info.isWeekend ? "周" : nil
        }
    }

    static func nextEventSummary(_ event: ChinaHolidayUpcomingEvent?, from date: Date, calendar: Calendar = .current) -> String {
        guard let event else { return "暂无已公布的后续安排" }
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: event.date)).day ?? 0)
        if days == 0 { return "今天 · \(event.title)" }
        return "距\(event.title) \(days) 天"
    }
}

private struct ChinaHolidayCalendarPopover: View {
    @Environment(\.dismiss) private var dismiss
    let initialDate: Date
    @State private var displayedMonth: Date
    @State private var selectedDate: Date

    init(initialDate: Date) {
        self.initialDate = initialDate
        let calendar = Self.makeCalendar()
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: initialDate)) ?? initialDate
        _displayedMonth = State(initialValue: month)
        _selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .keyboardShortcut(.leftArrow, modifiers: []).help("上个月")
                Spacer()
                VStack(spacing: 1) {
                    Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("中国法定节假日与调休")
                        .font(.system(size: 7.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .keyboardShortcut(.rightArrow, modifiers: []).help("下个月")
                Button { showToday() } label: { Image(systemName: "scope") }.help("返回今天")
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .keyboardShortcut(.cancelAction).help("关闭")
            }
            .buttonStyle(.borderless)

            calendarGrid
            legend
            selectedDayDetails
            upcomingEvents
            sourceDetails
        }
        .padding(13)
        .frame(width: 420)
    }

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let cells = monthCells
        return VStack(spacing: 5) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                    Text(weekday).font(.system(size: 7.5, weight: .semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        calendarDay(date)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
    }

    private func calendarDay(_ date: Date) -> some View {
        let calendar = Self.makeCalendar()
        let info = ChinaHolidayCalendar.dayInfo(for: date, calendar: calendar)
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let marker = HolidayPresentation.marker(for: info)
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 9, weight: selected ? .bold : .medium, design: .rounded))
                Text(marker ?? " ")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(marker == nil ? Color.clear : HolidayPresentation.color(for: info))
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                selected ? Color.accentColor : HolidayPresentation.color(for: info).opacity(info.kind == .normal && !info.isWeekend ? 0 : 0.10),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                if calendar.isDateInToday(date) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.accentColor.opacity(selected ? 0 : 0.75), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(date: .long, time: .omitted))，\(info.conciseLabel)")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem("休", "法定休假", .red)
            legendItem("班", "调休上班", .orange)
            legendItem("周", "周末", .indigo)
            Spacer()
            Text("方向键切换月份 · Esc 关闭")
                .font(.system(size: 7)).foregroundStyle(.tertiary)
        }
    }

    private func legendItem(_ marker: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(marker).font(.system(size: 7, weight: .bold)).foregroundStyle(color)
            Text(label).font(.system(size: 7.5)).foregroundStyle(.secondary)
        }
    }

    private var selectedDayDetails: some View {
        let calendar = Self.makeCalendar()
        let info = ChinaHolidayCalendar.dayInfo(for: selectedDate, calendar: calendar)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(selectedDate.formatted(date: .complete, time: .omitted))
                    .font(.system(size: 9.5, weight: .semibold))
                Spacer()
                Badge(text: info.conciseLabel, color: HolidayPresentation.color(for: info))
            }
            if let period = info.period {
                Text("\(period.name) · \(period.startDateKey) 至 \(period.endDateKey) · 连休 \(period.dayCount) 天")
                    .font(.system(size: 8.5))
                Text(period.makeupWorkdayKeys.isEmpty ? "官方通知未安排调休上班日" : "所属节日调休上班：\(period.makeupWorkdayKeys.joined(separator: "、"))")
                    .font(.system(size: 7.8)).foregroundStyle(.secondary)
            } else if !info.hasOfficialSchedule {
                Text("\(info.scheduleYear) 年官方节假日安排尚未收录；PulseDock 不根据往年日期推测。")
                    .font(.system(size: 8)).foregroundStyle(.orange)
            } else {
                Text(info.isWeekend ? "周末（非法定节假日或已公布的调休日）" : "普通工作日")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var upcomingEvents: some View {
        let calendar = Self.makeCalendar()
        let events = ChinaHolidayCalendar.upcomingEvents(after: initialDate, limit: 3, calendar: calendar)
        return VStack(alignment: .leading, spacing: 4) {
            Text("接下来的官方安排").font(.system(size: 8.5, weight: .semibold))
            if events.isEmpty {
                Text("暂无已收录的后续安排。")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 6) {
                        Text(event.kind == .holiday ? "休" : "班")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(event.kind == .holiday ? .red : .orange)
                            .frame(width: 16, height: 16)
                            .background((event.kind == .holiday ? Color.red : Color.orange).opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).font(.system(size: 8.5, weight: .semibold))
                            Text(event.detail).font(.system(size: 7)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(HolidayPresentation.nextEventSummary(event, from: initialDate, calendar: calendar))
                            .font(.system(size: 7.5, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var sourceDetails: some View {
        let year = Self.makeCalendar().component(.year, from: displayedMonth)
        return Group {
            if let schedule = ChinaHolidayCalendar.schedule(forYear: year) {
                Divider()
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(schedule.issuingAuthority) · \(schedule.noticeNumber)")
                            .font(.system(size: 7.5, weight: .semibold))
                        Text("发布 \(schedule.publishedDateKey) · 数据按年独立审计")
                            .font(.system(size: 7)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link("官方通知", destination: schedule.sourceURL).font(.system(size: 7.5))
                }
            }
        }
    }

    private var monthCells: [Date?] {
        let calendar = Self.makeCalendar()
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: first)
        let leading = (firstWeekday + 5) % 7
        var cells = Array<Date?>(repeating: nil, count: leading)
        cells.append(contentsOf: range.compactMap { day in calendar.date(byAdding: .day, value: day - 1, to: first) })
        let trailing = (7 - cells.count % 7) % 7
        cells.append(contentsOf: Array<Date?>(repeating: nil, count: trailing))
        return cells
    }

    private func moveMonth(_ amount: Int) {
        let calendar = Self.makeCalendar()
        guard let month = calendar.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        displayedMonth = month
        selectedDate = month
    }

    private func showToday() {
        let calendar = Self.makeCalendar()
        displayedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: initialDate)) ?? initialDate
        selectedDate = initialDate
    }

    private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }
}

private struct MiniQuota: View {
    let quota: QuotaPresentation
    let refresh: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(quota.title).font(.system(size: 10, weight: .bold)).lineLimit(1)
                    Text(quota.value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(quota.color).lineLimit(1)
                    Text(quota.detail).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if quota.hasRecoverableFailure {
                    DataFailureHintButton(
                        title: "\(quota.title) 更新暂时失败",
                        metadata: RefreshMetadata(
                            status: quota.freshness == .stale ? .stale : .initialFailure,
                            lastSuccessAt: quota.lastSuccessAt,
                            failureMessage: quota.failureMessage,
                            failureCount: quota.failureCount,
                            nextRetryAt: quota.nextRetryAt
                        ),
                        retry: refresh
                    )
                }
                RefreshIconButton(isRefreshing: quota.isRefreshing, action: refresh, help: "刷新\(quota.title)")
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Keeps the workbench compact while still giving a temporary data failure a
/// clear explanation and a user-controlled retry path.
private struct DataFailureHintButton: View {
    let title: String
    let metadata: RefreshMetadata
    let retry: () -> Void
    @State private var showingDetails = false

    var body: some View {
        Button { showingDetails = true } label: {
            Image(systemName: metadata.failureCount >= 3 ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                .foregroundStyle(metadata.failureCount >= 3 ? .red : .orange)
        }
        .buttonStyle(.plain)
        .help("查看更新状态")
        .popover(isPresented: $showingDetails, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 7) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(metadata.failureCount >= 3 ? .red : .orange)
                Text(metadata.failureMessage ?? "数据源暂时未返回结果")
                    .font(.system(size: 9)).fixedSize(horizontal: false, vertical: true)
                if let success = metadata.lastSuccessAt {
                    Text("上次成功：\(success.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
                if let retryAt = metadata.nextRetryAt {
                    Text("下次自动重试：\(retryAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 8.5)).foregroundStyle(.secondary)
                }
                if metadata.failureCount >= 3 {
                    Text("已连续失败 \(metadata.failureCount) 次；可检查网络、代理或登录状态。")
                        .font(.system(size: 8.5)).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("立即重试") { showingDetails = false; retry() }.controlSize(.small)
                }
            }
            .padding(11).frame(width: 245)
        }
    }
}

private struct RefreshIconButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    let help: String

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(isRefreshing ? .linear(duration: 0.75).repeatForever(autoreverses: false) : .default, value: isRefreshing)
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .help(isRefreshing ? "正在刷新…" : help)
        .accessibilityLabel(isRefreshing ? "正在刷新" : help)
    }
}

private struct WorkdayToggle: View {
    let label: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 10, weight: .bold))
                .frame(width: 28, height: 26)
                .foregroundStyle(isSelected ? .white : .secondary)
                .background(isSelected ? accent : Color.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(isSelected ? "点击设为休息日" : "点击设为工作日")
        .accessibilityLabel("星期\(label)")
        .accessibilityValue(isSelected ? "工作日" : "休息日")
    }
}

/// A content-sized, left-aligned flow for short discovery filters.
/// Using a flow rather than flexible grid columns is intentional: category chips must
/// look like controls, not like full-width list rows.
private struct DiscoveryChipFlow: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 6, verticalSpacing: CGFloat = 6) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                widest = max(widest, x - horizontalSpacing)
                x = 0
                y += lineHeight + verticalSpacing
                lineHeight = 0
            }
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        widest = max(widest, max(0, x - horizontalSpacing))
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + verticalSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct DiscoveryChip: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 8.5, weight: isSelected ? .bold : .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "已选中" : "未选中")
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { content.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
}

private struct Badge: View {
    let text: String; let color: Color
    var body: some View { Text(LocalizedStringKey(text)).font(.system(size: 8.5, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 3).background(color.opacity(0.16), in: Capsule()).foregroundStyle(color) }
}

private struct Stat: View {
    let label: String; let value: String
    var body: some View { VStack(spacing: 2) { Text(value).font(.system(size: 11, weight: .bold, design: .rounded)); Text(label).font(.system(size: 8)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
}

private struct SystemPill: View {
    let label: String; let value: String; let color: Color
    var body: some View { VStack(spacing: 2) { Text(value).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(color); Text(label).font(.system(size: 7.5)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
}
