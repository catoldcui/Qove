import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPane().tabItem { Label("General", systemImage: "gearshape") }
            ControlsPane().tabItem { Label("Controls", systemImage: "rectangle.split.3x1") }
        }
        .padding(12)
        .frame(width: 680, height: 500)
    }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject private var store = Store.shared
    @State private var trusted = Permissions.isTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Permissions") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Accessibility access granted" : "Accessibility access is required to move windows")
                    Spacer()
                    if !trusted {
                        Button("Open Settings…") {
                            Permissions.prompt()
                            Permissions.openSettings()
                        }
                    }
                }
            }

            Section("Keyboard controls") {
                LabeledContent("Shortcut") {
                    HotkeyRecorder(hotkey: $store.settings.keyboardHotkey).frame(width: 170, height: 24)
                }
                Text("Press the shortcut, then use ←↑→↓ to move the window over the grid, ⇧/⌥ + arrows to grow/shrink, Space to select a range, ↩ to finish, ⎋ to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Green-button palette") {
                Toggle("Show palette when hovering over a window's green button", isOn: $store.settings.hoverEnabled)
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: $store.settings.hoverDelay, in: 0...1.5)
                        Text(String(format: "%.2f s", store.settings.hoverDelay)).monospacedDigit().frame(width: 52)
                    }
                }
                Stepper("Grid columns: \(store.settings.gridColumns)", value: $store.settings.gridColumns, in: 2...16)
                Stepper("Grid rows: \(store.settings.gridRows)", value: $store.settings.gridRows, in: 2...16)
            }

            Section("Windows") {
                LabeledContent("Gap around windows") {
                    HStack {
                        Slider(value: $store.settings.gap, in: 0...40, step: 1)
                        Text("\(Int(store.settings.gap)) px").monospacedDigit().frame(width: 52)
                    }
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSSound.beep()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in trusted = Permissions.isTrusted }
    }
}

// MARK: - Controls

struct ControlsPane: View {
    @ObservedObject private var store = Store.shared
    @State private var selection: UUID?
    @State private var confirmClear = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.settings.controls) { c in
                        HStack(spacing: 8) {
                            ControlIcon(control: c).frame(width: 30, height: 20)
                            Text(c.name).lineLimit(1)
                            Spacer()
                            Text(c.hotkey?.displayString ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(c.id)
                    }
                    .onMove { store.settings.controls.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 2) {
                    Button { add() } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
                    Button { remove() } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
                        .disabled(selection == nil)
                    Spacer()
                    Menu {
                        Button("Restore Default Controls") { store.settings.controls = Control.defaults; selection = nil }
                        Button("Clear All Controls…", role: .destructive) { confirmClear = true }
                            .disabled(store.settings.controls.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 250)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))

            if let id = selection, store.control(id: id) != nil {
                ControlEditor(control: binding(for: id))
            } else {
                Text("Select a control to edit it")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog("Remove all \(store.settings.controls.count) controls and their shortcuts?",
                            isPresented: $confirmClear) {
            Button("Clear All", role: .destructive) {
                store.settings.controls.removeAll()
                selection = nil
            }
        } message: {
            Text("You can get the built-in set back with Restore Default Controls.")
        }
    }

    private func binding(for id: UUID) -> Binding<Control> {
        Binding(
            get: { store.control(id: id) ?? Control(name: "", action: .frame) },
            set: { new in
                if let i = store.settings.controls.firstIndex(where: { $0.id == id }) {
                    store.settings.controls[i] = new
                }
            })
    }

    private func add() {
        let c = Control(name: "New Control", action: .frame, frame: UnitRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5))
        store.settings.controls.append(c)
        selection = c.id
    }

    private func remove() {
        guard let id = selection else { return }
        store.settings.controls.removeAll { $0.id == id }
        selection = nil
    }
}

struct ControlEditor: View {
    @Binding var control: Control

    var body: some View {
        Form {
            TextField("Name", text: $control.name)
            Picker("Action", selection: $control.action) {
                ForEach(ControlAction.allCases) { Text($0.title).tag($0) }
            }
            if control.action == .frame {
                Section("Target region (drag to select)") {
                    FramePicker(frame: $control.frame)
                        .frame(height: 150)
                    HStack {
                        percentField("X", \.x)
                        percentField("Y", \.y)
                        percentField("W", \.w)
                        percentField("H", \.h)
                    }
                }
            }
            LabeledContent("Shortcut") {
                HotkeyRecorder(hotkey: $control.hotkey).frame(width: 170, height: 24)
            }
            Toggle("Show in green-button palette", isOn: $control.showInPalette)
        }
        .formStyle(.grouped)
    }

    private func percentField(_ label: String, _ key: WritableKeyPath<UnitRect, Double>) -> some View {
        TextField(label, value: Binding(
            get: { control.frame[keyPath: key] },
            set: { control.frame[keyPath: key] = min(max($0, 0), 1) }),
                  format: .percent.precision(.fractionLength(0...1)))
            .textFieldStyle(.roundedBorder)
    }
}

/// A 12×12 grid; drag across cells to set a unit rect (halves, thirds, quarters and sixths all snap).
struct FramePicker: View {
    @Binding var frame: UnitRect
    private let n = 12

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06))
                Path { p in
                    for i in 1..<n {
                        let x = size.width * CGFloat(i) / CGFloat(n), y = size.height * CGFloat(i) / CGFloat(n)
                        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                    }
                }
                .stroke(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.65))
                    .frame(width: frame.w * size.width, height: frame.h * size.height)
                    .offset(x: frame.x * size.width, y: frame.y * size.height)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let a = cell(v.startLocation, size), b = cell(v.location, size)
                let d = Double(n)
                frame = UnitRect(x: Double(min(a.0, b.0)) / d, y: Double(min(a.1, b.1)) / d,
                                 w: Double(abs(a.0 - b.0) + 1) / d, h: Double(abs(a.1 - b.1) + 1) / d)
            })
        }
    }

    private func cell(_ p: CGPoint, _ size: CGSize) -> (Int, Int) {
        let c = Int(p.x / size.width * CGFloat(n)), r = Int(p.y / size.height * CGFloat(n))
        return (min(max(c, 0), n - 1), min(max(r, 0), n - 1))
    }
}

struct ControlIcon: View {
    let control: Control

    var body: some View {
        if let name = ControlIconDrawing.symbolName(for: control.action) {
            Image(systemName: name)
        } else {
            GeometryReader { geo in
                let u = control.action == .center ? UnitRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5) : control.frame
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 2).stroke(Color.secondary, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: max(u.w * geo.size.width - 3, 1), height: max(u.h * geo.size.height - 3, 1))
                        .offset(x: u.x * geo.size.width + 1.5, y: u.y * geo.size.height + 1.5)
                }
            }
        }
    }
}

// MARK: - Shortcut recorder

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var hotkey: Hotkey?

    func makeNSView(context: Context) -> RecorderView { RecorderView() }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.hotkey = hotkey
        view.onChange = { hotkey = $0 }
    }
}

final class RecorderView: NSView {
    var hotkey: Hotkey? { didSet { needsDisplay = true } }
    var onChange: ((Hotkey?) -> Void)?
    private var recording = false {
        didSet {
            needsDisplay = true
            HotkeyManager.shared.isSuspended = recording
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if recording {
            window?.makeFirstResponder(nil)
        } else {
            window?.makeFirstResponder(self)
            recording = true
        }
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 53 where mods.isEmpty:
            window?.makeFirstResponder(nil)
        case 51 where mods.isEmpty, 117 where mods.isEmpty:
            onChange?(nil)
            window?.makeFirstResponder(nil)
        default:
            let hk = Hotkey(event: event)
            // Bare keys would hijack normal typing; require a modifier other than Shift (F-keys excepted).
            guard !mods.subtracting(.shift).isEmpty || Hotkey.isFunctionKey(hk.keyCode) else { return NSSound.beep() }
            onChange?(hk)
            window?.makeFirstResponder(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let text: String
        let color: NSColor
        if recording {
            (text, color) = ("Type shortcut…  ⎋ cancel  ⌫ clear", .secondaryLabelColor)
        } else if let hotkey {
            (text, color) = (hotkey.displayString, .labelColor)
        } else {
            (text, color) = ("Click to record", .tertiaryLabelColor)
        }
        let font: NSFont = recording ? .systemFont(ofSize: 10) : .systemFont(ofSize: 12, weight: .medium)
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let s = str.size()
        str.draw(at: CGPoint(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2))
    }
}
