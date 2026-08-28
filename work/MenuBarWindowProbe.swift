import CoreGraphics
import Foundation

guard let rawWindows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
    print("WINDOW_LIST_UNAVAILABLE")
    exit(1)
}

let matches = rawWindows.filter { window in
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let name = window[kCGWindowName as String] as? String ?? ""
    return owner.localizedCaseInsensitiveContains("PulseDock")
        || name.localizedCaseInsensitiveContains("PulseDock")
}

if matches.isEmpty {
    print("NO_PULSEDOCK_WINDOWS")
}

for window in matches {
    let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
    let name = window[kCGWindowName as String] as? String ?? ""
    let number = window[kCGWindowNumber as String] ?? "?"
    let layer = window[kCGWindowLayer as String] ?? "?"
    let alpha = window[kCGWindowAlpha as String] ?? "?"
    let onScreen = window[kCGWindowIsOnscreen as String] ?? "?"
    let bounds = window[kCGWindowBounds as String] ?? [:]
    print("owner=\(owner) name=\(name) id=\(number) layer=\(layer) alpha=\(alpha) onscreen=\(onScreen) bounds=\(bounds)")
}
