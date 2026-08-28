import AppKit
import CoreGraphics

enum ActiveApplicationMonitor {
    @MainActor
    static func snapshot(idleThreshold: Double, sessionActive: Bool) -> ActiveApplicationSnapshot {
        guard let app = NSWorkspace.shared.frontmostApplication else { return ActiveApplicationSnapshot() }
        let bundle = app.bundleIdentifier ?? ""
        let idle = reliableIdleSeconds()
        let trackable = sessionActive && app.activationPolicy == .regular
            && bundle != Bundle.main.bundleIdentifier
            && !bundle.isEmpty
        return ActiveApplicationSnapshot(
            name: app.localizedName ?? "未知应用", bundleIdentifier: bundle,
            idleSeconds: idle, isTrackable: trackable,
            isEngaged: trackable && idle < idleThreshold
        )
    }

    static func reliableIdleSeconds() -> Double {
        let types: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        let values = types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .filter { $0.isFinite && $0 >= 0 }
        return values.min() ?? .infinity
    }
}
