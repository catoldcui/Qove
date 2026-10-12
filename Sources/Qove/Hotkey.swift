import AppKit
import Carbon

/// A global shortcut. `modifiers` uses the Carbon mask.
struct Hotkey: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let ctrlOpt = UInt32(controlKey | optionKey)
    static let ctrlOptCmd = UInt32(controlKey | optionKey | cmdKey)
    static let optCmd = UInt32(optionKey | cmdKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        modifiers = Hotkey.carbonModifiers(event.modifierFlags)
    }

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        return f
    }

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Hotkey.keyName(keyCode)
    }

    var menuKeyEquivalent: String? {
        func fn(_ k: Int) -> String { String(Character(UnicodeScalar(UInt16(k))!)) }
        switch keyCode {
        case 123: return fn(NSLeftArrowFunctionKey)
        case 124: return fn(NSRightArrowFunctionKey)
        case 125: return fn(NSDownArrowFunctionKey)
        case 126: return fn(NSUpArrowFunctionKey)
        case 36: return "\r"
        case 51: return "\u{08}"
        case 49: return " "
        default:
            guard let c = Hotkey.translate(keyCode), c.count == 1 else { return nil }
            return c.lowercased()
        }
    }

    private static let specialKeys: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 76: "⌤",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func keyName(_ keyCode: UInt32) -> String {
        specialKeys[keyCode] ?? translate(keyCode) ?? "#\(keyCode)"
    }

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        if let n = specialKeys[keyCode] { return n.hasPrefix("F") }
        return false
    }

    private static func translate(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &dead, chars.count, &len, &chars)
            guard status == noErr, len > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: len).uppercased()
        }
    }
}

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var bindings: [(Hotkey, () -> Void)] = []
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?

    /// While recording a new shortcut, existing ones must not swallow the keystroke.
    var isSuspended = false {
        didSet { if oldValue != isSuspended { reload() } }
    }

    func register(_ bindings: [(Hotkey, () -> Void)]) {
        self.bindings = bindings
        reload()
    }

    private func reload() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
        guard !isSuspended else { return }
        installHandler()

        for (i, (hk, action)) in bindings.enumerated() {
            let id = UInt32(i + 1)
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x514F_5645), id: id) // 'QOVE'
            let status = RegisterEventHotKey(hk.keyCode, hk.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id] = action
            } else {
                NSLog("Qove: could not register hotkey \(hk.displayString) (status \(status))")
            }
        }
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard status == noErr else { return status }
            let id = hkID.id
            DispatchQueue.main.async { HotkeyManager.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
