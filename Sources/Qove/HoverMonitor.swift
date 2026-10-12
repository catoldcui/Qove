import AppKit

/// Watches the mouse and reports when it rests on another app's green zoom/full-screen button.
final class HoverMonitor {
    var onHover: ((AXWindow, CGRect) -> Void)?

    private var monitor: Any?
    private var checkScheduled = false
    private var pending: DispatchWorkItem?
    private var currentButton: AXUIElement?
    private let systemWide = AXUIElementCreateSystemWide()
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.15)
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.scheduleCheck()
        }
    }

    /// Coalesces bursts of mouse events so we hit the AX API at most ~25x/second but always see the final position.
    private func scheduleCheck() {
        guard !checkScheduled else { return }
        checkScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            self?.checkScheduled = false
            self?.check()
        }
    }

    private func check() {
        guard Store.shared.settings.hoverEnabled, Permissions.isTrusted else { return cancel() }
        guard let button = zoomButton(at: Geometry.flip(NSEvent.mouseLocation)) else { return cancel() }
        if let cur = currentButton, CFEqual(cur, button) { return }

        cancel()
        currentButton = button
        let work = DispatchWorkItem { [weak self] in self?.fire(button) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Store.shared.settings.hoverDelay, execute: work)
    }

    private func fire(_ button: AXUIElement) {
        guard let now = zoomButton(at: Geometry.flip(NSEvent.mouseLocation)), CFEqual(now, button),
              let window = windowOf(button),
              let p = button.point(kAXPositionAttribute), let s = button.size(kAXSizeAttribute) else { return }
        onHover?(AXWindow(element: window), CGRect(origin: p, size: s))
    }

    private func cancel() {
        pending?.cancel()
        pending = nil
        currentButton = nil
    }

    private func zoomButton(at p: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &el) == .success,
              let el, el.pid != ownPID else { return nil }
        let sub = el.string(kAXSubroleAttribute)
        return sub == kAXZoomButtonSubrole || sub == kAXFullScreenButtonSubrole ? el : nil
    }

    private func windowOf(_ button: AXUIElement) -> AXUIElement? {
        if let w = button.element(kAXWindowAttribute) { return w }
        var cur = button.element(kAXParentAttribute)
        while let c = cur {
            if c.string(kAXRoleAttribute) == kAXWindowRole { return c }
            cur = c.element(kAXParentAttribute)
        }
        return nil
    }
}
