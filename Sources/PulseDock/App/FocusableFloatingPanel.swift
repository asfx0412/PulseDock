import AppKit
import SwiftUI

/// The floating panel may be visible while another application owns the key
/// window.  AppKit otherwise reserves the first click for activation on some
/// controls, which feels like a dead button.  The hosting root explicitly
/// accepts that first click; `FocusableFloatingPanel.sendEvent` activates the
/// panel before forwarding the same event exactly once.
@MainActor
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Compact mode stays passive; expanded mode becomes a normal key window so
/// SwiftUI TextField/SecureField can receive keyboard and clipboard commands.
/// The panel is created without `.nonactivatingPanel` because toggling that bit
/// at runtime can leave AppKit's activation state stale.
@MainActor
final class FocusableFloatingPanel: NSPanel {
    var allowsKeyboardFocus = false
    /// Called only for a double-click that did not land on a native editing or
    /// control view. This keeps the global expand gesture from stealing a
    /// second click from Toggle/TextField/Button.
    var onBackgroundDoubleClick: (() -> Void)?
    private var backgroundMouseDown: NSEvent?
    private var backgroundMouseDownPoint: NSPoint?
    /// Menu dismissal can send the following click to the hosting background.
    /// Keep a small grace window so controls can never trigger global collapse.
    private var lastInteractiveMouseDownTimestamp: TimeInterval?
    private let dragThreshold: CGFloat = 4

    override var canBecomeKey: Bool { allowsKeyboardFocus }
    override var canBecomeMain: Bool { allowsKeyboardFocus }
    override func sendEvent(_ event: NSEvent) {
        let editableField = event.type == .leftMouseDown ? editableTextField(at: event.locationInWindow) : nil
        let shouldRestoreTextFocus = editableField.map { !isKeyWindow || $0.currentEditor() == nil } ?? false
        if allowsKeyboardFocus, event.type == .leftMouseDown, !isKeyWindow {
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
        }
        switch event.type {
        case .leftMouseDown:
            // Clicking outside an editable field must end the shared AppKit
            // field editor, removing its focus ring and insertion caret.
            if editableField == nil, currentFirstResponderIsTextEditor {
                makeFirstResponder(nil)
            }
            let interactive = isInteractiveHit(at: event.locationInWindow)
            if interactive { lastInteractiveMouseDownTimestamp = event.timestamp }
            let followsInteractiveControl = lastInteractiveMouseDownTimestamp.map { event.timestamp - $0 < 0.9 } ?? false
            if event.clickCount >= 2, permitsBackgroundDoubleClick(at: event.locationInWindow), !followsInteractiveControl {
                clearBackgroundDrag()
                onBackgroundDoubleClick?()
                return
            }
            if event.clickCount == 1, !interactive {
                backgroundMouseDown = event
                backgroundMouseDownPoint = event.locationInWindow
            } else {
                clearBackgroundDrag()
            }
        case .leftMouseDragged:
            if let down = backgroundMouseDown, let origin = backgroundMouseDownPoint {
                let point = event.locationInWindow
                let distance = hypot(point.x - origin.x, point.y - origin.y)
                if distance >= dragThreshold {
                    clearBackgroundDrag()
                    performDrag(with: down)
                    return
                }
            }
        case .leftMouseUp:
            clearBackgroundDrag()
        default:
            break
        }
        super.sendEvent(event)
        // Creating the shared field editor during the same mouseDown that
        // activates an accessory panel is timing-sensitive. Let AppKit finish
        // dispatching the click, then make the editor the responder on the
        // next main-loop turn. This keeps IME marked text and the caret alive.
        if shouldRestoreTextFocus, let editableField { focusTextFieldForEditing(editableField) }
    }

    func focusTextFieldForEditing(_ field: NSTextField) {
        DispatchQueue.main.async { [weak self, weak field] in
            guard let self, let field, self.allowsKeyboardFocus, field.window === self else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.orderFrontRegardless()
            self.makeKeyAndOrderFront(nil)
            // The field itself must become first responder first. Asking the
            // window for a field editor and directly making that shared editor
            // responder can leave it detached from its NSTextField: ASCII may
            // work while IME marked text, caret and active selection do not.
            guard self.isKeyWindow, self.makeFirstResponder(field) else { return }
            if let editor = field.currentEditor() as? NSTextView {
                editor.insertionPointColor = .controlTextColor
                editor.selectedTextAttributes[.backgroundColor] = NSColor.selectedTextBackgroundColor
                editor.selectedTextAttributes[.foregroundColor] = NSColor.selectedTextColor
            }
        }
    }

    /// ScrollView/ClipView are containers, not controls. Treating the whole
    /// document area as interactive was why expanded-mode double-click worked
    /// only in the header.
    func isInteractiveHit(at point: NSPoint) -> Bool {
        if accessibilityInteractiveHit(at: point) { return true }
        guard let hit = contentView?.hitTest(point) else { return false }
        var view: NSView? = hit
        while let current = view {
            if current is NSControl || current is NSTextView || current is NSScroller {
                return true
            }
            if let role = current.accessibilityRole(), [
                .button, .checkBox, .comboBox, .link, .menuButton, .menuItem,
                .popUpButton, .radioButton, .scrollBar, .slider, .textField
            ].contains(role) { return true }
            view = current.superview
        }
        return false
    }

    /// SwiftUI does not expose every semantic control through AppKit hit
    /// testing (notably several Button/Slider/Menu compositions).  Instead of
    /// guessing and occasionally collapsing on a second control click, only
    /// the real outer blank gutter participates in the global double-click.
    /// The full content canvas is protected; it contains cards, scrolling and
    /// dynamically laid-out controls whose bounds change with every page.
    func permitsBackgroundDoubleClick(at point: NSPoint) -> Bool {
        guard !isInteractiveHit(at: point), let contentView else { return false }
        return !contentView.bounds.insetBy(dx: 14, dy: 14).contains(point)
    }

    /// SwiftUI often exposes a Button/Toggle/Picker only through the
    /// accessibility tree rather than as an NSControl descendant.  Consult
    /// that tree before treating a hit as empty background; actionable and
    /// scrollable SwiftUI content must always win over the panel gesture.
    private func accessibilityInteractiveHit(at point: NSPoint) -> Bool {
        let screenPoint = convertToScreen(NSRect(origin: point, size: .zero)).origin
        guard let target = contentView?.accessibilityHitTest(screenPoint) as? NSObject else { return false }
        let selector = NSSelectorFromString("accessibilityActionNames")
        if target.responds(to: selector),
           let actions = target.perform(selector)?.takeUnretainedValue() as? [Any] {
            let interactiveActions = ["AXPress", "AXIncrement", "AXDecrement", "AXShowMenu", "AXConfirm"]
            if actions.contains(where: { interactiveActions.contains(String(describing: $0)) }) { return true }
        }
        return false
    }

    private func editableTextField(at point: NSPoint) -> NSTextField? {
        guard let hit = contentView?.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view {
            if let field = current as? NSTextField, field.isEditable, field.isEnabled { return field }
            // Once editing has started AppKit may hit-test the shared field
            // editor rather than the NSTextField itself.  Treat that editor as
            // the same interactive target, otherwise a second click can be
            // misclassified as background drag/double-click and terminate an
            // active CJK marked-text composition.
            if let editor = current as? NSTextView,
               editor.isEditable,
               let field = editor.delegate as? NSTextField,
               field.isEnabled {
                return field
            }
            view = current.superview
        }
        return nil
    }

    private func clearBackgroundDrag() {
        backgroundMouseDown = nil
        backgroundMouseDownPoint = nil
    }

    private var currentFirstResponderIsTextEditor: Bool {
        if firstResponder is NSTextView { return true }
        if let field = firstResponder as? NSTextField { return field.isEditable }
        return false
    }
}
