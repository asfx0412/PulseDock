import AppKit
import SwiftUI

/// Native AppKit editing keeps caret, field editor and marked-text IME state
/// reliable inside the accessory floating panel.
struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var onSubmit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ReliableTextField {
        let field = ReliableTextField()
        field.placeholderString = placeholder
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.focusRingType = .default
        field.font = .systemFont(ofSize: 11)
        field.isEditable = true
        field.isSelectable = true
        field.refusesFirstResponder = false
        field.usesSingleLineMode = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: ReliableTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        // Updating an NSTextField while its field editor is active can remove
        // the insertion point and cancel Chinese/Japanese/Korean marked text.
        // User edits already update the binding in the delegate, so external
        // state only writes back after editing ended.
        let editor = field.currentEditor() as? NSTextView
        let hasLiveEditor = editor != nil || field.window?.firstResponder === field
        // `controlTextDidBeginEditing` may arrive one run-loop turn after the
        // first input event.  Preserve that small window too: replacing the
        // value here is what made a CJK composition lose its caret or accept
        // only the raw ASCII keystrokes intermittently.
        let composing = editor?.hasMarkedText() == true
        if !context.coordinator.isEditing, !hasLiveEditor, !composing, field.stringValue != text {
            field.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        var isEditing = false
        init(_ parent: FocusableTextField) { self.parent = parent }
        func controlTextDidBeginEditing(_ notification: Notification) { isEditing = true }
        func controlTextDidEndEditing(_ notification: Notification) { isEditing = false }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText() {
                parent.text = (control as? NSTextField)?.stringValue ?? parent.text
                parent.onSubmit()
                return true
            }
            return false
        }
    }

    final class ReliableTextField: NSTextField {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var acceptsFirstResponder: Bool { isEditable && isEnabled }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            // This is intentionally a second, idempotent focus request.  In
            // an accessory floating panel the shared field editor sometimes
            // attaches after the panel has already processed mouseDown.
            if let panel = window as? FocusableFloatingPanel, panel.allowsKeyboardFocus {
                panel.focusTextFieldForEditing(self)
            }
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted, let editor = currentEditor() as? NSTextView {
                editor.insertionPointColor = .controlTextColor
            }
            return accepted
        }
    }
}
