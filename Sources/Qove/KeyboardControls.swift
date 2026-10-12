import AppKit

/// Keyboard mode: a shortcut shows a grid over the screen, and the arrow keys / Space place the window.
final class KeyboardController: NSObject, NSWindowDelegate {
    struct Cell: Equatable { var c: Int; var r: Int }
    struct Selection: Equatable { var c: Int; var r: Int; var w: Int; var h: Int }

    private var overlay: OverlayWindow?
    private var view: OverlayView?
    private var target: AXWindow?
    private var targetApp: NSRunningApplication?
    private var original: CGRect?
    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    private var cols = 6, rows = 4
    private var sel = Selection(c: 0, r: 0, w: 1, h: 1)
    /// While non-nil we're in range mode: Space anchored this cell, arrows move `cursor`.
    private var anchor: Cell?
    private var cursor = Cell(c: 0, r: 0)
    private var finishing = false

    var isActive: Bool { overlay != nil }

    func toggle() {
        isActive ? finish(cancel: false) : begin()
    }

    private func begin() {
        guard Permissions.isTrusted else { return Permissions.prompt() }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let win = AXWindow.focused(), let frame = win.frame else { return NSSound.beep() }

        target = win
        targetApp = app
        original = frame
        cols = Store.shared.settings.gridColumns
        rows = Store.shared.settings.gridRows
        anchor = nil
        screen = Geometry.screen(containing: frame)
        sel = snap(frame)

        let w = OverlayWindow(contentRect: screen.visibleFrame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        w.delegate = self
        let v = OverlayView(frame: CGRect(origin: .zero, size: screen.visibleFrame.size))
        v.onKey = { [weak self] in self?.handle($0) ?? false }
        w.contentView = v
        overlay = w
        view = v
        redraw()

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(v)
    }

    private func finish(cancel: Bool) {
        guard !finishing, let overlay else { return }
        finishing = true
        if cancel, let target, let original { target.setFrame(original) }
        overlay.delegate = nil
        overlay.orderOut(nil)
        self.overlay = nil
        view = nil
        target = nil
        targetApp?.activate(options: [])
        targetApp = nil
        finishing = false
    }

    func windowDidResignKey(_ notification: Notification) {
        finish(cancel: false)
    }

    // MARK: Keys

    private func handle(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.shift, .option, .command, .control])
        let dir: (Int, Int)? = switch e.keyCode {
        case 123: (-1, 0)
        case 124: (1, 0)
        case 125: (0, 1)
        case 126: (0, -1)
        default: nil
        }

        if let (dx, dy) = dir {
            if anchor != nil {
                cursor = Cell(c: clamp(cursor.c + dx, 0, cols - 1), r: clamp(cursor.r + dy, 0, rows - 1))
                updateRange()
            } else if mods.contains(.shift) {
                grow(dx, dy)
            } else if mods.contains(.option) {
                shrink(dx, dy)
            } else if mods.contains(.command) {
                toEdge(dx, dy)
            } else {
                sel.c = clamp(sel.c + dx, 0, cols - sel.w)
                sel.r = clamp(sel.r + dy, 0, rows - sel.h)
            }
            if anchor == nil { applyLive() }
            redraw()
            return true
        }

        switch e.keyCode {
        case 49: // Space: first press anchors a range, second press commits it
            if anchor == nil {
                anchor = Cell(c: sel.c, r: sel.r)
                cursor = anchor!
                updateRange()
            } else {
                anchor = nil
                applyLive()
            }
            redraw()
        case 36, 76: // Return / Enter
            if anchor != nil { anchor = nil; applyLive() }
            finish(cancel: false)
        case 53: // Esc
            if anchor != nil {
                anchor = nil
                if let target, let f = target.frame { sel = snap(f) }
                redraw()
            } else {
                finish(cancel: true)
            }
        case 48: // Tab: move to next/previous display
            switchDisplay(mods.contains(.shift) ? -1 : 1)
        case 3: // F: fill
            sel = Selection(c: 0, r: 0, w: cols, h: rows)
            anchor = nil
            applyLive()
            redraw()
        default:
            if let n = Int(e.charactersIgnoringModifiers ?? ""), n >= 1 {
                runControl(n)
            } else {
                return false
            }
        }
        return true
    }

    private func grow(_ dx: Int, _ dy: Int) {
        if dx < 0, sel.c > 0 { sel.c -= 1; sel.w += 1 }
        if dx > 0, sel.c + sel.w < cols { sel.w += 1 }
        if dy < 0, sel.r > 0 { sel.r -= 1; sel.h += 1 }
        if dy > 0, sel.r + sel.h < rows { sel.h += 1 }
    }

    /// The edge on the arrow's opposite side moves toward the arrow.
    private func shrink(_ dx: Int, _ dy: Int) {
        if dx < 0, sel.w > 1 { sel.w -= 1 }
        if dx > 0, sel.w > 1 { sel.c += 1; sel.w -= 1 }
        if dy < 0, sel.h > 1 { sel.h -= 1 }
        if dy > 0, sel.h > 1 { sel.r += 1; sel.h -= 1 }
    }

    private func toEdge(_ dx: Int, _ dy: Int) {
        if dx < 0 { sel.c = 0 }
        if dx > 0 { sel.c = cols - sel.w }
        if dy < 0 { sel.r = 0 }
        if dy > 0 { sel.r = rows - sel.h }
    }

    private func updateRange() {
        guard let a = anchor else { return }
        sel = Selection(c: min(a.c, cursor.c), r: min(a.r, cursor.r),
                        w: abs(a.c - cursor.c) + 1, h: abs(a.r - cursor.r) + 1)
    }

    private func switchDisplay(_ step: Int) {
        let screens = Geometry.orderedScreens
        guard screens.count > 1, let i = screens.firstIndex(of: screen), let overlay else { return NSSound.beep() }
        screen = screens[(i + step + screens.count) % screens.count]
        overlay.setFrame(screen.visibleFrame, display: false)
        view?.frame = CGRect(origin: .zero, size: screen.visibleFrame.size)
        applyLive()
        redraw()
    }

    private func runControl(_ n: Int) {
        let controls = Store.shared.settings.controls
        guard n <= controls.count, let target else { return NSSound.beep() }
        let t = target
        finish(cancel: false)
        WindowManager.shared.perform(controls[n - 1], on: t)
    }

    // MARK: Geometry

    private func unit(_ s: Selection) -> UnitRect {
        UnitRect(x: Double(s.c) / Double(cols), y: Double(s.r) / Double(rows),
                 w: Double(s.w) / Double(cols), h: Double(s.h) / Double(rows))
    }

    private func applyLive() {
        guard let target else { return }
        WindowManager.shared.move(target, to: WindowManager.shared.frame(for: unit(sel), on: screen), from: original)
    }

    /// Nearest grid selection to a window frame (AX coordinates).
    private func snap(_ f: CGRect) -> Selection {
        let vf = Geometry.visibleFrame(screen)
        let cw = vf.width / CGFloat(cols), ch = vf.height / CGFloat(rows)
        let c0 = clamp(Int(((f.minX - vf.minX) / cw).rounded()), 0, cols - 1)
        let c1 = clamp(Int(((f.maxX - vf.minX) / cw).rounded()), c0 + 1, cols)
        let r0 = clamp(Int(((f.minY - vf.minY) / ch).rounded()), 0, rows - 1)
        let r1 = clamp(Int(((f.maxY - vf.minY) / ch).rounded()), r0 + 1, rows)
        return Selection(c: c0, r: r0, w: c1 - c0, h: r1 - r0)
    }

    private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), max(lo, hi)) }

    private func redraw() {
        guard let view else { return }
        view.cols = cols
        view.rows = rows
        view.selection = sel
        view.anchor = anchor
        view.cursor = anchor == nil ? nil : cursor
        view.needsDisplay = true
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class OverlayView: NSView {
    var onKey: ((NSEvent) -> Bool)?
    var cols = 6, rows = 4
    var selection = KeyboardController.Selection(c: 0, r: 0, w: 1, h: 1)
    var anchor: KeyboardController.Cell?
    var cursor: KeyboardController.Cell?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { NSSound.beep() }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘-arrows would otherwise be eaten as menu key equivalents.
        onKey?(event) ?? false
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        let cw = bounds.width / CGFloat(cols), ch = bounds.height / CGFloat(rows)
        func rect(_ c: Int, _ r: Int, _ w: Int, _ h: Int) -> CGRect {
            CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: CGFloat(w) * cw, height: CGFloat(h) * ch)
        }

        let grid = NSBezierPath()
        for i in 1..<cols { grid.move(to: CGPoint(x: CGFloat(i) * cw, y: 0)); grid.line(to: CGPoint(x: CGFloat(i) * cw, y: bounds.height)) }
        for i in 1..<rows { grid.move(to: CGPoint(x: 0, y: CGFloat(i) * ch)); grid.line(to: CGPoint(x: bounds.width, y: CGFloat(i) * ch)) }
        NSColor.white.withAlphaComponent(0.35).setStroke()
        grid.lineWidth = 1
        grid.setLineDash([6, 4], count: 2, phase: 0)
        grid.stroke()

        let s = rect(selection.c, selection.r, selection.w, selection.h).insetBy(dx: 4, dy: 4)
        let sp = NSBezierPath(roundedRect: s, xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
        sp.fill()
        NSColor.controlAccentColor.setStroke()
        sp.lineWidth = 3
        sp.stroke()

        if let anchor {
            NSColor.white.withAlphaComponent(0.85).setStroke()
            let a = NSBezierPath(roundedRect: rect(anchor.c, anchor.r, 1, 1).insetBy(dx: 12, dy: 12), xRadius: 6, yRadius: 6)
            a.lineWidth = 2
            a.setLineDash([5, 4], count: 2, phase: 0)
            a.stroke()
        }
        if let cursor {
            NSColor.white.setStroke()
            let c = NSBezierPath(roundedRect: rect(cursor.c, cursor.r, 1, 1).insetBy(dx: 12, dy: 12), xRadius: 6, yRadius: 6)
            c.lineWidth = 3
            c.stroke()
        }

        drawHelp()
    }

    private func drawHelp() {
        let lines = anchor != nil
            ? ["Selecting range — ←↑→↓ extend", "Space  set     ↩ done     ⎋ back"]
            : ["←↑→↓ move    ⇧ grow    ⌥ shrink    ⌘ to edge",
               "Space  select range    F  fill    1–9  controls    ⇥  next display",
               "↩ done     ⎋ cancel"]
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 4
        let text = NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ])
        let size = text.boundingRect(with: CGSize(width: 600, height: 200), options: .usesLineFragmentOrigin).size
        let box = CGRect(x: bounds.midX - size.width / 2 - 18, y: bounds.maxY - size.height - 48,
                         width: size.width + 36, height: size.height + 20)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        text.draw(with: box.insetBy(dx: 18, dy: 10), options: .usesLineFragmentOrigin)
    }
}
