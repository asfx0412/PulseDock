import Carbon.HIToolbox
import Foundation

struct GlobalShortcut: RawRepresentable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let optionSpace = GlobalShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), keyLabel: "Space")
    static let optionShiftSpace = GlobalShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey), keyLabel: "Space")

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel.isEmpty ? "Key \(keyCode)" : keyLabel
    }

    init?(rawValue: String) {
        let legacy: [String: GlobalShortcut] = [
            "optionSpace": .optionSpace,
            "optionShiftSpace": .optionShiftSpace,
            "controlOptionSpace": .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), keyLabel: "Space"),
            "controlOptionShiftSpace": .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey | shiftKey), keyLabel: "Space"),
            "commandOptionSpace": .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey), keyLabel: "Space"),
            "commandOptionShiftSpace": .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey | shiftKey), keyLabel: "Space")
        ]
        if let migrated = legacy[rawValue] { self = migrated; return }
        let parts = rawValue.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let keyCode = UInt32(parts[0]), let modifiers = UInt32(parts[1]),
              let labelData = Data(base64Encoded: String(parts[2])),
              let keyLabel = String(data: labelData, encoding: .utf8) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel)
    }

    var rawValue: String {
        "\(keyCode):\(modifiers):\(Data(keyLabel.utf8).base64EncodedString())"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode); hasher.combine(modifiers)
    }

    var label: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + keyLabel
    }

    var validationMessage: String? {
        let primary = modifiers & UInt32(cmdKey | controlKey | optionKey)
        return primary == 0 ? "请至少使用 ⌘、⌃ 或 ⌥ 中的一个修饰键" : nil
    }
}

@MainActor
final class GlobalHotKeyManager {
    private enum ActionID: UInt32 { case visibility = 1, expansion = 2 }
    var onToggleVisibility: (() -> Void)?
    var onToggleExpansion: (() -> Void)?
    private var visibilityRef: EventHotKeyRef?
    private var expansionRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var isSuspendedForRecording = false
    private(set) var registeredVisibility: GlobalShortcut?
    private(set) var registeredExpansion: GlobalShortcut?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in manager.perform(identifier.id) }
            return noErr
        }, 1, &type, pointer, &eventHandler)
    }

    deinit {
        if let visibilityRef { UnregisterEventHotKey(visibilityRef) }
        if let expansionRef { UnregisterEventHotKey(expansionRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(visibility: GlobalShortcut, expansion: GlobalShortcut) -> String {
        if let reason = visibility.validationMessage { return "显示/隐藏：\(reason)；已保留上一组有效设置" }
        if let reason = expansion.validationMessage { return "展开/收起：\(reason)；已保留上一组有效设置" }
        guard visibility != expansion else { return "两项快捷键不能相同；已保留上一组有效设置" }
        if !isSuspendedForRecording, visibility == registeredVisibility, expansion == registeredExpansion { return "全局快捷键已启用：\(visibility.label) · \(expansion.label)" }
        let oldVisibility = registeredVisibility
        let oldExpansion = registeredExpansion
        unregisterAll()

        let signature = Self.fourCharacterCode("PLSD")
        let visibilityID = EventHotKeyID(signature: signature, id: ActionID.visibility.rawValue)
        let visibilityStatus = RegisterEventHotKey(visibility.keyCode, visibility.modifiers, visibilityID, GetApplicationEventTarget(), 0, &visibilityRef)
        guard visibilityStatus == noErr else {
            unregisterAll(); restore(visibility: oldVisibility, expansion: oldExpansion)
            return "显示/隐藏快捷键 \(visibility.label) 已被系统或其他应用占用；已保留上一组有效设置"
        }
        let expansionID = EventHotKeyID(signature: signature, id: ActionID.expansion.rawValue)
        let expansionStatus = RegisterEventHotKey(expansion.keyCode, expansion.modifiers, expansionID, GetApplicationEventTarget(), 0, &expansionRef)
        guard expansionStatus == noErr else {
            unregisterAll(); restore(visibility: oldVisibility, expansion: oldExpansion)
            return "展开/收起快捷键 \(expansion.label) 已被系统或其他应用占用；已保留上一组有效设置"
        }
        registeredVisibility = visibility; registeredExpansion = expansion
        isSuspendedForRecording = false
        return "全局快捷键已启用：\(visibility.label) · \(expansion.label)"
    }

    func suspendForRecording() {
        if let visibilityRef { UnregisterEventHotKey(visibilityRef); self.visibilityRef = nil }
        if let expansionRef { UnregisterEventHotKey(expansionRef); self.expansionRef = nil }
        isSuspendedForRecording = true
    }

    func unregisterAll() {
        if let visibilityRef { UnregisterEventHotKey(visibilityRef); self.visibilityRef = nil }
        if let expansionRef { UnregisterEventHotKey(expansionRef); self.expansionRef = nil }
        registeredVisibility = nil; registeredExpansion = nil
        isSuspendedForRecording = false
    }

    private func restore(visibility: GlobalShortcut?, expansion: GlobalShortcut?) {
        guard let visibility, let expansion else { return }
        _ = register(visibility: visibility, expansion: expansion)
    }

    private func perform(_ rawID: UInt32) {
        switch ActionID(rawValue: rawID) {
        case .visibility: onToggleVisibility?()
        case .expansion: onToggleExpansion?()
        case nil: break
        }
    }

    private static func fourCharacterCode(_ value: String) -> OSType {
        value.utf8.prefix(4).reduce(0) { ($0 << 8) | OSType($1) }
    }
}
