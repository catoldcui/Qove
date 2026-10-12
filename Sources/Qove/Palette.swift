import AppKit

/// The floating palette shown next to a window's green button: preset buttons plus a drag-to-resize grid.
final class PaletteController {
    private let panel = PalettePanel()
    private let preview = PreviewWindow()
    private var target: AXWindow?
    private var targetScreen: NSScreen?
    private var anchor: CGRect = .zero
    private var pollTimer: Timer?
    private var outsideSince: Date?
    private var eventMonitor: Any?

    func show(for window: AXWindow, buttonFrame: CGRect) {
        guard let frame = window.frame else { return }
        target = window
        targetScreen = Geometry.screen(containing: frame)
        anchor = Geometry.flip(buttonFrame)

        let settings = Store.shared.settings
        let vf = targetScreen?.visibleFrame ?? .init(x: 0, y: 0, width: 16, height: 10)
        let content = PaletteView(controls: settings.controls.filter(\.showInPalette),
                                  columns: settings.gridColumns, rows: settings.gridRows,
                                  aspect: vf.height / vf.width)
        content.onHoverControl = { [weak self] in self?.previewControl($0) }
        content.onHoverUnit = { [weak self] in self?.previewUnit($0) }
        content.onPerformControl = { [weak self] in self?.perform($0) }
        content.onPerformUnit = { [weak self] in self?.perform(unit: $0) }
        panel.setContent(content)

        let size = content.frame.size
        let screenVF = (NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? targetScreen)?.visibleFrame ?? vf
        var origin = CGPoint(x: anchor.maxX + 8, y: anchor.maxY + 6 - size.height)
        origin.x = min(max(origin.x, screenVF.minX), screenVF.maxX - size.width)
        origin.y = min(max(origin.y, screenVF.minY), screenVF.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        startTracking()
    }

    func hide() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
        eventMonitor = nil
        outsideSince = nil
        preview.orderOut(nil)
        panel.orderOut(nil)
        target = nil
    }

    private func startTracking() {
        outsideSince = nil
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.poll() }
        if eventMonitor == nil {
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
                if e.type != .keyDown || e.keyCode == 53 { self?.hide() }
            }
        }
    }

    /// Hide once the mouse has left both the button and the palette for a short grace period.
    private func poll() {
        let m = NSEvent.mouseLocation
        if anchor.union(panel.frame).insetBy(dx: -12, dy: -12).contains(m) {
            outsideSince = nil
        } else if let t = outsideSince {
            if Date().timeIntervalSince(t) > 0.4 { hide() }
        } else {
            outsideSince = Date()
        }
    }

    private func previewControl(_ control: Control?) {
        guard let control, let target, let r = WindowManager.shared.targetFrame(for: control, window: target) else {
            return preview.orderOut(nil)
        }
        preview.show(axRect: r)
    }

    private func previewUnit(_ unit: UnitRect?) {
        guard let unit, let targetScreen else { return preview.orderOut(nil) }
        preview.show(axRect: WindowManager.shared.frame(for: unit, on: targetScreen))
    }

    private func perform(_ control: Control) {
        let t = target
        hide()
        WindowManager.shared.perform(control, on: t)
    }

    private func perform(unit: UnitRect) {
        let t = target
        hide()
        WindowManager.shared.perform(unit: unit, on: t)
    }
}

final class PalettePanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { false }

    func setContent(_ view: NSView) {
        let effect = NSVisualEffectView(frame: view.bounds)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = .roundedMask(radius: 10)
        effect.addSubview(view)
        contentView = effect
    }
}

final class PreviewWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        v.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        v.layer?.borderWidth = 3
        v.layer?.cornerRadius = 10
        contentView = v
    }

    func show(axRect: CGRect) {
        setFrame(Geometry.flip(axRect), display: true)
        orderFrontRegardless()
    }
}

extension NSImage {
    static func roundedMask(radius: CGFloat) -> NSImage {
        let d = radius * 2 + 1
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }
}

// MARK: - Palette content

final class PaletteView: NSView {
    var onHoverControl: ((Control?) -> Void)?
    var onHoverUnit: ((UnitRect?) -> Void)?
    var onPerformControl: ((Control) -> Void)?
    var onPerformUnit: ((UnitRect) -> Void)?

    private let label = NSTextField(labelWithString: "")
    override var isFlipped: Bool { true }

    init(controls: [Control], columns: Int, rows: Int, aspect: CGFloat) {
        let pad: CGFloat = 10, spacing: CGFloat = 6
        let perRow = 7
        let btn = CGSize(width: 34, height: 24)
        let innerWidth = CGFloat(perRow) * btn.width + CGFloat(perRow - 1) * spacing
        let buttonRows = (controls.count + perRow - 1) / perRow
        let buttonsHeight = buttonRows == 0 ? 0 : CGFloat(buttonRows) * btn.height + CGFloat(buttonRows - 1) * spacing
        let gridHeight = (innerWidth * min(max(aspect, 0.3), 1.5)).rounded()
        let labelHeight: CGFloat = 16
        let gridTop = pad + buttonsHeight + (buttonRows == 0 ? 0 : 10)
        let total = CGSize(width: innerWidth + pad * 2, height: gridTop + gridHeight + 6 + labelHeight + pad)
        super.init(frame: CGRect(origin: .zero, size: total))

        for (i, c) in controls.enumerated() {
            let b = ControlButton(control: c)
            b.frame = CGRect(x: pad + CGFloat(i % perRow) * (btn.width + spacing),
                             y: pad + CGFloat(i / perRow) * (btn.height + spacing),
                             width: btn.width, height: btn.height)
            b.onHover = { [weak self] c in
                self?.label.stringValue = c.map { n in n.hotkey.map { "\(n.name)   \($0.displayString)" } ?? n.name } ?? ""
                self?.onHoverControl?(c)
            }
            b.onClick = { [weak self] in self?.onPerformControl?($0) }
            addSubview(b)
        }

        let grid = GridView(columns: columns, rows: rows)
        grid.frame = CGRect(x: pad, y: gridTop, width: innerWidth, height: gridHeight)
        grid.onHover = { [weak self] u, text in
            self?.label.stringValue = text ?? ""
            self?.onHoverUnit?(u)
        }
        grid.onSelect = { [weak self] in self?.onPerformUnit?($0) }
        addSubview(grid)

        label.frame = CGRect(x: pad, y: gridTop + gridHeight + 6, width: innerWidth, height: labelHeight)
        label.alignment = .center
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class ControlButton: NSView {
    let control: Control
    var onHover: ((Control?) -> Void)?
    var onClick: ((Control) -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    init(control: Control) {
        self.control = control
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { hovering = true; onHover?(control) }
    override func mouseExited(with event: NSEvent) { hovering = false; onHover?(nil) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?(control) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        (hovering ? NSColor.controlAccentColor.withAlphaComponent(0.3) : NSColor.labelColor.withAlphaComponent(0.07)).setFill()
        bg.fill()
        ControlIconDrawing.draw(control, in: bounds.insetBy(dx: 7, dy: 5), flipped: true)
    }
}

enum ControlIconDrawing {
    static func symbolName(for action: ControlAction) -> String? {
        switch action {
        case .nextDisplay: "arrow.right.circle"
        case .previousDisplay: "arrow.left.circle"
        case .restore: "arrow.uturn.backward.circle"
        case .frame, .center: nil
        }
    }

    /// Draws a mini "screen" with the control's target region filled in.
    static func draw(_ control: Control, in rect: CGRect, flipped: Bool) {
        if let name = symbolName(for: control.action),
           let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
               .withSymbolConfiguration(.init(pointSize: 12, weight: .medium).applying(.init(paletteColors: [.labelColor]))) {
            let s = img.size
            img.draw(in: CGRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height))
            return
        }
        let screen = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        NSColor.labelColor.withAlphaComponent(0.45).setStroke()
        screen.lineWidth = 1
        screen.stroke()

        let u = control.action == .center ? UnitRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5) : control.frame
        let y = flipped ? rect.minY + u.y * rect.height : rect.maxY - (u.y + u.h) * rect.height
        let fill = CGRect(x: rect.minX + u.x * rect.width, y: y, width: u.w * rect.width, height: u.h * rect.height)
            .insetBy(dx: 1.5, dy: 1.5)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1, yRadius: 1).fill()
    }
}

final class GridView: NSView {
    struct Cell: Equatable { var c: Int; var r: Int }

    let columns: Int, rows: Int
    var onHover: ((UnitRect?, String?) -> Void)?
    var onSelect: ((UnitRect) -> Void)?

    private var hoverCell: Cell?
    private var dragStart: Cell?

    override var isFlipped: Bool { true }

    init(columns: Int, rows: Int) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func cell(_ event: NSEvent) -> Cell {
        let p = convert(event.locationInWindow, from: nil)
        let c = Int(p.x / bounds.width * CGFloat(columns))
        let r = Int(p.y / bounds.height * CGFloat(rows))
        return Cell(c: min(max(c, 0), columns - 1), r: min(max(r, 0), rows - 1))
    }

    private var selection: (Cell, Cell)? {
        guard let end = hoverCell else { return nil }
        let start = dragStart ?? end
        return (Cell(c: min(start.c, end.c), r: min(start.r, end.r)),
                Cell(c: max(start.c, end.c), r: max(start.r, end.r)))
    }

    private var selectionUnit: UnitRect? {
        guard let (a, b) = selection else { return nil }
        return UnitRect(x: Double(a.c) / Double(columns), y: Double(a.r) / Double(rows),
                        w: Double(b.c - a.c + 1) / Double(columns), h: Double(b.r - a.r + 1) / Double(rows))
    }

    private func update(_ cell: Cell?) {
        hoverCell = cell
        needsDisplay = true
        let text = selection.map { a, b in "\(b.c - a.c + 1) × \(b.r - a.r + 1) of \(columns) × \(rows)" }
        onHover?(selectionUnit, text ?? (cell == nil ? nil : "Drag to choose a region"))
    }

    override func mouseMoved(with event: NSEvent) { update(cell(event)) }
    override func mouseEntered(with event: NSEvent) { update(cell(event)) }
    override func mouseExited(with event: NSEvent) { if dragStart == nil { update(nil) } }
    override func mouseDown(with event: NSEvent) { dragStart = cell(event); update(dragStart) }
    override func mouseDragged(with event: NSEvent) { update(cell(event)) }
    override func mouseUp(with event: NSEvent) {
        hoverCell = cell(event)
        let unit = selectionUnit
        dragStart = nil
        if let unit { onSelect?(unit) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let sel = selection
        let gap: CGFloat = 2
        let cw = bounds.width / CGFloat(columns), ch = bounds.height / CGFloat(rows)
        for r in 0..<rows {
            for c in 0..<columns {
                let rect = CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw, height: ch).insetBy(dx: gap / 2, dy: gap / 2)
                let selected = sel.map { a, b in (a.c...b.c).contains(c) && (a.r...b.r).contains(r) } ?? false
                (selected ? NSColor.controlAccentColor.withAlphaComponent(0.75) : NSColor.labelColor.withAlphaComponent(0.09)).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            }
        }
    }
}
