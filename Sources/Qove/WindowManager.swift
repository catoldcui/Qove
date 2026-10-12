import AppKit

final class WindowManager {
    static let shared = WindowManager()

    /// Frame each window had before we first moved it, for "Revert".
    private var originals: [(AXUIElement, CGRect)] = []

    func perform(_ control: Control, on window: AXWindow? = nil) {
        guard Permissions.isTrusted else { Permissions.prompt(); return }
        guard let win = window ?? AXWindow.focused(), let current = win.frame else { NSSound.beep(); return }

        if control.action == .restore {
            guard let i = originals.lastIndex(where: { CFEqual($0.0, win.element) }) else { NSSound.beep(); return }
            win.setFrame(originals.remove(at: i).1)
            return
        }
        guard let target = targetFrame(for: control, window: win, current: current) else { NSSound.beep(); return }
        move(win, to: target, from: current)
    }

    func move(_ win: AXWindow, to target: CGRect, from current: CGRect? = nil) {
        if let current = current ?? win.frame, !originals.contains(where: { CFEqual($0.0, win.element) }) {
            originals.append((win.element, current))
            if originals.count > 200 { originals.removeFirst() }
        }
        win.setFrame(target)
    }

    func perform(unit: UnitRect, on window: AXWindow? = nil) {
        perform(Control(name: "", action: .frame, frame: unit), on: window)
    }

    /// Where `control` would put `window`, in Accessibility coordinates.
    func targetFrame(for control: Control, window: AXWindow, current: CGRect? = nil) -> CGRect? {
        guard let current = current ?? window.frame else { return nil }
        let screen = Geometry.screen(containing: current)

        switch control.action {
        case .frame:
            return frame(for: control.frame, on: screen)

        case .center:
            let vf = Geometry.visibleFrame(screen)
            let w = min(current.width, vf.width), h = min(current.height, vf.height)
            return CGRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h).integral

        case .nextDisplay, .previousDisplay:
            let screens = Geometry.orderedScreens
            guard screens.count > 1, let i = screens.firstIndex(of: screen) else { return nil }
            let step = control.action == .nextDisplay ? 1 : -1
            let dest = screens[(i + step + screens.count) % screens.count]
            let src = Geometry.visibleFrame(screen), dst = Geometry.visibleFrame(dest)
            let w = min(current.width / src.width * dst.width, dst.width)
            let h = min(current.height / src.height * dst.height, dst.height)
            let x = dst.minX + (current.minX - src.minX) / src.width * dst.width
            let y = dst.minY + (current.minY - src.minY) / src.height * dst.height
            return CGRect(x: min(max(x, dst.minX), dst.maxX - w),
                          y: min(max(y, dst.minY), dst.maxY - h),
                          width: w, height: h).integral

        case .restore:
            return originals.last(where: { CFEqual($0.0, window.element) })?.1
        }
    }

    func frame(for u: UnitRect, on screen: NSScreen) -> CGRect {
        let gap = CGFloat(Store.shared.settings.gap)
        let vf = Geometry.visibleFrame(screen).insetBy(dx: gap / 2, dy: gap / 2)
        return CGRect(x: vf.minX + u.x * vf.width, y: vf.minY + u.y * vf.height,
                      width: u.w * vf.width, height: u.h * vf.height)
            .insetBy(dx: gap / 2, dy: gap / 2)
            .integral
    }
}
