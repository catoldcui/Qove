import AppKit
import ApplicationServices

enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func prompt() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension AXUIElement {
    private func raw(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value
    }

    func element(_ name: String) -> AXUIElement? {
        guard let v = raw(name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    func string(_ name: String) -> String? { raw(name) as? String }

    func bool(_ name: String) -> Bool? { raw(name) as? Bool }

    func point(_ name: String) -> CGPoint? {
        guard let v = raw(name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    func size(_ name: String) -> CGSize? {
        guard let v = raw(name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    var pid: pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(self, &p)
        return p
    }
}

/// A window of another app, addressed through the Accessibility API (top-left-origin coordinates).
struct AXWindow {
    let element: AXUIElement

    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        if let w = appEl.element(kAXFocusedWindowAttribute) ?? appEl.element(kAXMainWindowAttribute) {
            return AXWindow(element: w)
        }
        return nil
    }

    var frame: CGRect? {
        guard let p = element.point(kAXPositionAttribute), let s = element.size(kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    func setFrame(_ r: CGRect) {
        // Apps with AXEnhancedUserInterface on (e.g. when VoiceOver-like tools ran) animate and drop resizes.
        let app = AXUIElementCreateApplication(element.pid)
        let enhanced = app.bool("AXEnhancedUserInterface") ?? false
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }

        // Size, move, size again: the first resize can be clamped by the old screen's bounds.
        setSize(r.size)
        setPosition(r.origin)
        setSize(r.size)

        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    private func setPosition(_ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v)
        }
    }

    private func setSize(_ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v)
        }
    }
}

/// Converts between Cocoa (bottom-left origin) and Accessibility (top-left origin) coordinates.
enum Geometry {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func flip(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    static func visibleFrame(_ screen: NSScreen) -> CGRect { flip(screen.visibleFrame) }

    static func screen(containing axRect: CGRect) -> NSScreen {
        let r = flip(axRect)
        func overlap(_ s: NSScreen) -> CGFloat {
            let i = s.frame.intersection(r)
            return i.isNull ? 0 : i.width * i.height
        }
        if let best = NSScreen.screens.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 {
            return best
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// Screens ordered left to right, used for next/previous display.
    static var orderedScreens: [NSScreen] {
        NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
    }
}
