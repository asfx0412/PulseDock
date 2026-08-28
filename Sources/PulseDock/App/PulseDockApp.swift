import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
    private let store = MonitorStore()
    private var panelController: FloatingPanelController?
    private var hotKeyManager: GlobalHotKeyManager?
    private var statusItem: NSStatusItem?
    private var desktopMenuItem: NSMenuItem?
    private var dockMenuItem: NSMenuItem?
    private var menuBarRepairScheduled = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if activateExistingInstanceIfNeeded() { return }
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        panelController = FloatingPanelController(store: store)
        configureGlobalHotKeys()
        configureStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(ensureMenuBarItem), name: .pulseDockEnsureMenuBarItem, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reconfigureGlobalHotKeys), name: .pulseDockGlobalHotKeysChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(suspendGlobalHotKeysForRecording), name: .pulseDockGlobalHotKeyRecordingBegan, object: nil)
        // macOS may finish rebuilding its status bar after the activation
        // policy transition. Recreate the item after those launch-time passes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.ensureMenuBarItem() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.ensureMenuBarItem() }
        store.start()
        panelController?.show()
    }

    /// LaunchServices normally enforces the plist flag, while this runtime guard
    /// also covers development launches and copies started directly from Finder.
    private func activateExistingInstanceIfNeeded() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        guard let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != currentPID }) else { return false }
        existing.activate(options: [.activateAllWindows])
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregisterAll()
        store.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return true
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 48)
        item.autosaveName = "PulseDock.MainStatusItem"
        if let button = item.button {
            // A plain, fixed-width label avoids SF Symbol rendering and
            // variable-width regressions observed on macOS 26 menu bars.
            button.image = nil
            button.imagePosition = .noImage
            button.title = "● PD"
            button.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            button.isHidden = false
            button.alphaValue = 1
            button.isEnabled = true
            button.toolTip = "PulseDock — 点击打开菜单"
        }
        item.isVisible = true
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("显示 / 隐藏浮窗", action: #selector(togglePanel), key: "p"))
        menu.addItem(menuItem("收起到菜单栏", action: #selector(hideToMenuBar), key: "m"))
        menu.addItem(menuItem("收起到程序坞", action: #selector(hideToDock), key: "d"))
        menu.addItem(menuItem("刷新公网 IP", action: #selector(refreshIP), key: "r"))
        menu.addItem(.separator())
        let desktop = menuItem("只在当前桌面显示（关闭则所有桌面）", action: #selector(toggleCurrentDesktop), key: "")
        let dock = menuItem("在程序坞显示图标", action: #selector(toggleDockIcon), key: "")
        menu.addItem(desktop)
        menu.addItem(dock)
        desktopMenuItem = desktop
        dockMenuItem = dock
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 PulseDock", action: #selector(quit), key: "q"))
        item.menu = menu
        statusItem = item
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu(title: "PulseDock")
        let editRoot = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editRoot.submenu = editMenu
        mainMenu.addItem(editRoot)
        NSApp.mainMenu = mainMenu
    }

    private func menuItem(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        desktopMenuItem?.state = panelController?.state.currentDesktopOnly == true ? .on : .off
        dockMenuItem?.state = panelController?.state.showInDock == true ? .on : .off
    }

    @objc private func togglePanel() { panelController?.toggle() }
    @objc private func hideToMenuBar() { panelController?.minimizeToMenuBar() }
    @objc private func hideToDock() { panelController?.minimizeToDock() }
    @objc private func refreshIP() { store.refreshIP() }
    @objc func ensureMenuBarItem() {
        // Switching between .regular (Dock) and .accessory (menu bar only)
        // can invalidate the status window while leaving the NSStatusItem
        // object alive. Rebuild it on the next run-loop instead of merely
        // toggling isVisible on a stale item.
        guard !menuBarRepairScheduled else { return }
        menuBarRepairScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.menuBarRepairScheduled = false
            if let oldItem = self.statusItem {
                NSStatusBar.system.removeStatusItem(oldItem)
            }
            self.statusItem = nil
            self.desktopMenuItem = nil
            self.dockMenuItem = nil
            self.configureStatusItem()
        }
    }
    @objc private func toggleCurrentDesktop() { panelController?.state.currentDesktopOnly.toggle() }
    @objc private func toggleDockIcon() { panelController?.state.showInDock.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func configureGlobalHotKeys() {
        let manager = hotKeyManager ?? GlobalHotKeyManager()
        manager.onToggleVisibility = { [weak self] in self?.panelController?.toggleVisibilityShortcut() }
        manager.onToggleExpansion = { [weak self] in self?.panelController?.toggleExpansionShortcut() }
        hotKeyManager = manager
        let state = panelController?.state
        let registrationStatus = manager.register(
            visibility: state?.visibilityShortcut ?? .optionSpace,
            expansion: state?.expansionShortcut ?? .optionShiftSpace
        )
        state?.shortcutRegistrationStatus = registrationStatus
        if !registrationStatus.contains("已启用"),
           let visibility = manager.registeredVisibility,
           let expansion = manager.registeredExpansion {
            state?.restoreShortcutChoices(visibility: visibility, expansion: expansion)
        }
    }

    @objc private func reconfigureGlobalHotKeys() { configureGlobalHotKeys() }
    @objc private func suspendGlobalHotKeysForRecording() { hotKeyManager?.suspendForRecording() }
}

@MainActor
final class FloatingPanelController {
    private let panel: FocusableFloatingPanel
    let state = PanelState()
    private var observers: [NSObjectProtocol] = []

    init(store: MonitorStore) {
        let initialSize = state.compactSize
        panel = FocusableFloatingPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            // Runtime switching of .nonactivatingPanel is unreliable: AppKit can
            // keep the old activation tag, leaving SwiftUI fields unable to become
            // first responder. Key-window eligibility is controlled by the panel
            // subclass instead.
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Background window dragging consumes click sequences before SwiftUI can
        // recognize double-clicks and text-field focus. Use the title/drag handle.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.onBackgroundDoubleClick = { [weak state] in state?.expanded.toggle() }
        panel.contentView = FirstMouseHostingView(rootView: RootPanelView(store: store, state: state))

        let frame = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: max(frame.minX + 16, frame.maxX - initialSize.width - 22), y: frame.maxY - initialSize.height - 22))

        observers.append(NotificationCenter.default.addObserver(forName: .pulseDockPanelSizeChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resize() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .pulseDockPanelConfigurationChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyConfiguration() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .pulseDockPanelMinimizeToMenuBar, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.minimizeToMenuBar() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .pulseDockPanelMinimizeToDock, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.minimizeToDock() }
        })
        applyConfiguration()
    }

    func show() {
        if state.expanded {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
            if state.showInDock { NSApp.activate(ignoringOtherApps: true) }
        }
        NotificationCenter.default.post(name: .pulseDockPanelShown, object: nil)
    }
    func hide() { panel.orderOut(nil) }
    func toggle() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }

    func toggleVisibilityShortcut() {
        if panel.isVisible {
            hide()
        } else {
            if state.expanded { state.expanded = false }
            show()
        }
    }

    func toggleExpansionShortcut() {
        if !panel.isVisible {
            if !state.expanded { state.expanded = true }
            show()
        } else {
            state.expanded.toggle()
            show()
        }
    }

    func minimizeToMenuBar() {
        state.showInDock = false
        NotificationCenter.default.post(name: .pulseDockEnsureMenuBarItem, object: nil)
        panel.orderOut(nil)
    }

    func minimizeToDock() {
        state.showInDock = true
        panel.orderOut(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    private func resize() {
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let target: NSSize
        if state.expanded {
            target = NSSize(width: min(500, max(380, visible.width - 32)), height: min(700, max(500, visible.height - 32)))
        } else {
            target = state.compactSize
        }
        var frame = panel.frame
        if state.expanded {
            panel.allowsKeyboardFocus = true
            panel.becomesKeyOnlyIfNeeded = false
        } else {
            panel.allowsKeyboardFocus = false
            panel.becomesKeyOnlyIfNeeded = false
        }
        frame.origin.y += frame.height - target.height
        frame.size = target
        // A compact panel commonly lives near the screen edge. Once it grows,
        // keep the whole expanded panel inside the usable screen so its header
        // controls cannot land outside the visible area.
        frame.origin.x = min(max(frame.origin.x, visible.minX + 16), max(visible.minX + 16, visible.maxX - target.width - 16))
        frame.origin.y = min(max(frame.origin.y, visible.minY + 16), max(visible.minY + 16, visible.maxY - target.height - 16))
        // The hosted SwiftUI hierarchy changes with this size. Applying the
        // frame atomically avoids a click landing on a transient, old layout.
        panel.setFrame(frame, display: true, animate: false)
        if state.expanded {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else if panel.isKeyWindow {
            panel.resignKey()
        }
    }

    private func applyConfiguration() {
        panel.alphaValue = state.opacity
        panel.level = .floating
        panel.collectionBehavior = state.currentDesktopOnly
            ? [.fullScreenAuxiliary, .stationary]
            : [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        NSApp.setActivationPolicy(state.showInDock ? .regular : .accessory)
    }
}

@MainActor
final class PanelState: ObservableObject {
    private var isRestoringShortcutChoices = false
    private enum Key {
        static let opacity = "PulseDock.opacity"
        static let currentDesktop = "PulseDock.currentDesktopOnly"
        static let showInDock = "PulseDock.showInDock"
        static let compactDensity = "PulseDock.compactDensity"
        static let floatingTheme = "PulseDock.floatingTheme"
        static let customBackground = "PulseDock.customBackground"
        static let themeDepth = "PulseDock.themeDepth"
        static let appLanguage = "PulseDock.appLanguage"
        static let visibilityShortcut = "PulseDock.visibilityShortcut"
        static let expansionShortcut = "PulseDock.expansionShortcut"
    }

    @Published var expanded = false {
        didSet { NotificationCenter.default.post(name: .pulseDockPanelSizeChanged, object: nil) }
    }
    @Published var opacity: Double {
        didSet {
            UserDefaults.standard.set(opacity, forKey: Key.opacity)
            notifyConfigurationChanged()
        }
    }
    @Published var currentDesktopOnly: Bool {
        didSet {
            UserDefaults.standard.set(currentDesktopOnly, forKey: Key.currentDesktop)
            notifyConfigurationChanged()
        }
    }
    @Published var showInDock: Bool {
        didSet {
            UserDefaults.standard.set(showInDock, forKey: Key.showInDock)
            notifyConfigurationChanged()
            NotificationCenter.default.post(name: .pulseDockEnsureMenuBarItem, object: nil)
        }
    }
    @Published var compactDensity: CompactDensity {
        didSet {
            UserDefaults.standard.set(compactDensity.rawValue, forKey: Key.compactDensity)
            NotificationCenter.default.post(name: .pulseDockPanelSizeChanged, object: nil)
        }
    }
    @Published var floatingTheme: FloatingTheme {
        didSet { UserDefaults.standard.set(floatingTheme.rawValue, forKey: Key.floatingTheme) }
    }
    @Published var customBackground: Color {
        didSet { UserDefaults.standard.set(Self.encode(customBackground), forKey: Key.customBackground) }
    }
    @Published var themeDepth: Double {
        didSet { UserDefaults.standard.set(themeDepth, forKey: Key.themeDepth) }
    }
    @Published var appLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: Key.appLanguage)
            UserDefaults.standard.set([appLanguage.rawValue], forKey: "AppleLanguages")
        }
    }
    @Published var visibilityShortcut: GlobalShortcut {
        didSet {
            UserDefaults.standard.set(visibilityShortcut.rawValue, forKey: Key.visibilityShortcut)
            if !isRestoringShortcutChoices { NotificationCenter.default.post(name: .pulseDockGlobalHotKeysChanged, object: nil) }
        }
    }
    @Published var expansionShortcut: GlobalShortcut {
        didSet {
            UserDefaults.standard.set(expansionShortcut.rawValue, forKey: Key.expansionShortcut)
            if !isRestoringShortcutChoices { NotificationCenter.default.post(name: .pulseDockGlobalHotKeysChanged, object: nil) }
        }
    }
    @Published var shortcutRegistrationStatus = "正在注册全局快捷键…"

    var panelBackground: Color { Self.adjust(floatingTheme == .custom ? customBackground : floatingTheme.background, depth: themeDepth) }
    var panelAccent: Color { floatingTheme.accent }
    var isPanelDark: Bool { Self.isDark(panelBackground) }

    var compactSize: NSSize {
        switch compactDensity {
        case .minimal: NSSize(width: 330, height: 58)
        case .balanced: NSSize(width: 390, height: 68)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        opacity = min(1, max(0.35, defaults.object(forKey: Key.opacity) as? Double ?? 0.92))
        currentDesktopOnly = defaults.object(forKey: Key.currentDesktop) as? Bool ?? false
        showInDock = defaults.object(forKey: Key.showInDock) as? Bool ?? true
        compactDensity = CompactDensity(rawValue: defaults.string(forKey: Key.compactDensity) ?? "") ?? .balanced
        floatingTheme = FloatingTheme(rawValue: defaults.string(forKey: Key.floatingTheme) ?? "") ?? .mist
        customBackground = Self.decode(defaults.string(forKey: Key.customBackground))
        themeDepth = min(1, max(0, defaults.object(forKey: Key.themeDepth) as? Double ?? 0.5))
        appLanguage = AppLanguage(rawValue: defaults.string(forKey: Key.appLanguage) ?? "") ?? .simplifiedChinese
        visibilityShortcut = GlobalShortcut(rawValue: defaults.string(forKey: Key.visibilityShortcut) ?? "") ?? .optionSpace
        expansionShortcut = GlobalShortcut(rawValue: defaults.string(forKey: Key.expansionShortcut) ?? "") ?? .optionShiftSpace
    }

    func requestMinimizeToMenuBar() {
        NotificationCenter.default.post(name: .pulseDockPanelMinimizeToMenuBar, object: nil)
    }

    func requestMinimizeToDock() {
        NotificationCenter.default.post(name: .pulseDockPanelMinimizeToDock, object: nil)
    }

    func requestMenuBarRepair() {
        NotificationCenter.default.post(name: .pulseDockEnsureMenuBarItem, object: nil)
    }

    func restoreShortcutChoices(visibility: GlobalShortcut, expansion: GlobalShortcut) {
        isRestoringShortcutChoices = true
        visibilityShortcut = visibility
        expansionShortcut = expansion
        isRestoringShortcutChoices = false
    }

    private func notifyConfigurationChanged() {
        NotificationCenter.default.post(name: .pulseDockPanelConfigurationChanged, object: nil)
    }

    private static func encode(_ color: Color) -> String {
        let value = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        return [value.redComponent, value.greenComponent, value.blueComponent, value.alphaComponent]
            .map { String(format: "%.4f", $0) }.joined(separator: ",")
    }

    private static func decode(_ value: String?) -> Color {
        let parts = value?.split(separator: ",").compactMap { Double($0) } ?? []
        guard parts.count == 4 else { return Color(red: 0.88, green: 0.93, blue: 0.95) }
        return Color(red: parts[0], green: parts[1], blue: parts[2], opacity: parts[3])
    }

    private static func adjust(_ color: Color, depth: Double) -> Color {
        let value = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        let amount = abs(depth - 0.5) * 2
        let target: CGFloat = depth < 0.5 ? 1 : 0
        func blend(_ component: CGFloat) -> Double { Double(component + (target - component) * amount) }
        return Color(red: blend(value.redComponent), green: blend(value.greenComponent), blue: blend(value.blueComponent), opacity: Double(value.alphaComponent))
    }

    private static func isDark(_ color: Color) -> Bool {
        let value = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
        return (0.2126 * value.redComponent + 0.7152 * value.greenComponent + 0.0722 * value.blueComponent) < 0.48
    }
}

extension Notification.Name {
    static let pulseDockPanelSizeChanged = Notification.Name("PulseDock.PanelSizeChanged")
    static let pulseDockPanelConfigurationChanged = Notification.Name("PulseDock.PanelConfigurationChanged")
    static let pulseDockPanelMinimizeToMenuBar = Notification.Name("PulseDock.PanelMinimizeToMenuBar")
    static let pulseDockPanelMinimizeToDock = Notification.Name("PulseDock.PanelMinimizeToDock")
    static let pulseDockEnsureMenuBarItem = Notification.Name("PulseDock.EnsureMenuBarItem")
    static let pulseDockGlobalHotKeysChanged = Notification.Name("PulseDock.GlobalHotKeysChanged")
    static let pulseDockGlobalHotKeyRecordingBegan = Notification.Name("PulseDock.GlobalHotKeyRecordingBegan")
    static let pulseDockPanelShown = Notification.Name("PulseDock.PanelShown")
}
