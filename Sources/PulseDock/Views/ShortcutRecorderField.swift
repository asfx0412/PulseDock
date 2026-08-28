import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: GlobalShortcut

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> RecorderControl {
        let control = RecorderControl()
        control.shortcut = shortcut
        control.onCommit = { context.coordinator.parent.shortcut = $0 }
        return control
    }

    func updateNSView(_ control: RecorderControl, context: Context) {
        context.coordinator.parent = self
        control.onCommit = { context.coordinator.parent.shortcut = $0 }
        if !control.isRecording { control.shortcut = shortcut }
        control.needsDisplay = true
    }

    final class Coordinator {
        var parent: ShortcutRecorderField
        init(_ parent: ShortcutRecorderField) { self.parent = parent }
    }

    final class RecorderControl: NSControl {
        var shortcut: GlobalShortcut = .optionSpace
        var onCommit: ((GlobalShortcut) -> Void)?
        var isRecording = false

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 28) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            NotificationCenter.default.post(name: .pulseDockGlobalHotKeyRecordingBegan, object: nil)
            isRecording = true
            needsDisplay = true
        }

        override func resignFirstResponder() -> Bool {
            if isRecording {
                NotificationCenter.default.post(name: .pulseDockGlobalHotKeysChanged, object: nil)
            }
            isRecording = false
            needsDisplay = true
            return super.resignFirstResponder()
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == UInt16(kVK_Escape) {
                isRecording = false
                NotificationCenter.default.post(name: .pulseDockGlobalHotKeysChanged, object: nil)
                window?.makeFirstResponder(nil); needsDisplay = true; return
            }
            let candidate = GlobalShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: Self.carbonModifiers(event.modifierFlags),
                keyLabel: Self.keyLabel(event)
            )
            guard candidate.validationMessage == nil else { NSSound.beep(); return }
            shortcut = candidate
            isRecording = false
            onCommit?(candidate)
            window?.makeFirstResponder(nil)
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.controlBackgroundColor).setFill()
            path.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = isRecording ? 2 : 1
            path.stroke()
            let text = isRecording ? "请按新快捷键…" : shortcut.label
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: isRecording ? .medium : .regular),
                .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: 10, y: floor((bounds.height - size.height) / 2)), withAttributes: attributes)
        }

        private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
            var result: UInt32 = 0
            if flags.contains(.command) { result |= UInt32(cmdKey) }
            if flags.contains(.control) { result |= UInt32(controlKey) }
            if flags.contains(.option) { result |= UInt32(optionKey) }
            if flags.contains(.shift) { result |= UInt32(shiftKey) }
            return result
        }

        private static func keyLabel(_ event: NSEvent) -> String {
            let known: [UInt16: String] = [
                UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return", UInt16(kVK_Tab): "Tab",
                UInt16(kVK_Delete): "Delete", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_LeftArrow): "←",
                UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
                UInt16(kVK_Home): "Home", UInt16(kVK_End): "End", UInt16(kVK_PageUp): "Page Up", UInt16(kVK_PageDown): "Page Down",
                UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
                UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
                UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
            ]
            if let value = known[event.keyCode] { return value }
            let characters = event.charactersIgnoringModifiers?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return characters.isEmpty ? "Key \(event.keyCode)" : String(characters.prefix(4))
        }
    }
}
