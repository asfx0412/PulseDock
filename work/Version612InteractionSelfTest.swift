import AppKit
import SwiftUI

@main
@MainActor
enum Version612InteractionSelfTest {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() {
        _ = NSApplication.shared
        let panel = FocusableFloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        require(!panel.styleMask.contains(.nonactivatingPanel), "不得运行时切换 nonactivatingPanel")
        require(!panel.canBecomeKey, "紧凑模式不应抢键盘焦点")
        panel.allowsKeyboardFocus = true
        require(panel.canBecomeKey && panel.canBecomeMain, "展开模式必须允许 TextField/SecureField 获得焦点")

        let firstMouseRoot = FirstMouseHostingView(rootView: Text("首次点击"))
        require(firstMouseRoot.acceptsFirstMouse(for: nil), "非 key 浮窗的首次点击必须传递给 SwiftUI 控件")

        let root = NSView(frame: panel.contentView!.bounds)
        panel.contentView = root
        let scroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: 180, height: 180))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 170, height: 300))
        scroll.documentView = document
        root.addSubview(scroll)
        let backgroundPoint = root.convert(document.convert(NSPoint(x: 40, y: 40), to: nil), from: nil)
        require(!panel.isInteractiveHit(at: backgroundPoint), "普通内容背景不得伪装成控件；窗口收起只由显式拖动手柄处理")

        let button = NSButton(title: "测试", target: nil, action: nil)
        button.frame = NSRect(x: 220, y: 30, width: 90, height: 28)
        root.addSubview(button)
        require(panel.isInteractiveHit(at: NSPoint(x: 240, y: 42)), "按钮必须保留自己的点击和双击")

        let swiftUIButton = NSHostingView(rootView: Button("SwiftUI 操作") {}.frame(width: 120, height: 28))
        swiftUIButton.frame = NSRect(x: 220, y: 130, width: 120, height: 28)
        root.addSubview(swiftUIButton)
        swiftUIButton.layoutSubtreeIfNeeded()
        let swiftPoint = NSPoint(x: 280, y: 144)
        require(!panel.permitsBackgroundDoubleClick(at: swiftPoint), "SwiftUI 按钮所在内容区不得触发背景双击")
        require(panel.permitsBackgroundDoubleClick(at: NSPoint(x: 2, y: 2)), "窗口边缘真实留白必须仍支持全局双击")
        for _ in 0..<100 {
            require(!panel.permitsBackgroundDoubleClick(at: swiftPoint), "连续双击压力下 SwiftUI 操作区仍不得收起窗口")
            require(panel.isInteractiveHit(at: NSPoint(x: 240, y: 42)), "连续双击压力下原生按钮命中不得丢失")
        }

        let field = NSTextField(frame: NSRect(x: 220, y: 80, width: 120, height: 24))
        root.addSubview(field)
        require(panel.isInteractiveHit(at: NSPoint(x: 240, y: 90)), "输入框必须保留编辑、全选和复制粘贴")

        final class TextBox { var value = "" }
        let box = TextBox()
        let hosted = NSHostingView(rootView: FocusableTextField(
            text: Binding(get: { box.value }, set: { box.value = $0 }),
            placeholder: "搜索广播台"
        ).frame(width: 180, height: 24))
        hosted.frame = NSRect(x: 10, y: 220, width: 180, height: 24)
        root.addSubview(hosted)
        hosted.layoutSubtreeIfNeeded()
        guard let native = descendants(of: hosted).compactMap({ $0 as? FocusableTextField.ReliableTextField }).first else {
            FileHandle.standardError.write(Data("FAIL: SwiftUI hosting hierarchy must contain the native reliable editor\n".utf8))
            exit(1)
        }
        require(panel.isInteractiveHit(at: root.convert(native.bounds.center, from: native)), "真实托管搜索框不得被背景拖动/双击截获")
        require(native.acceptsFirstMouse(for: nil), "输入框在浮窗非 key 时必须接受首次点击")
        require(panel.makeFirstResponder(native), "托管搜索框必须能成为 first responder")
        require(panel.firstResponder != nil, "托管搜索框必须创建 field editor")
        panel.focusTextFieldForEditing(native)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        require(panel.firstResponder is NSTextView || panel.firstResponder === native, "下一事件循环必须保留托管搜索框的编辑 responder")
        require(native.currentEditor() is NSTextView, "共享 field editor 必须附着到真实 NSTextField，不能独立成为游离 responder")
        if let editor = native.currentEditor() as? NSTextView {
            require(editor.insertionPointColor == .controlTextColor, "活动输入框必须显示插入光标")
            require(editor.selectedTextAttributes[.backgroundColor] as? NSColor == .selectedTextBackgroundColor, "活动选区必须使用系统选中颜色")
        }
        print("PulseDock 6.8 interaction self-test passed")
    }

    static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
