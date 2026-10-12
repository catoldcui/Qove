import Foundation
import Combine

/// Fraction of a screen's visible area, origin at the top-left.
struct UnitRect: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    static let full = UnitRect(x: 0, y: 0, w: 1, h: 1)
}

enum ControlAction: String, Codable, CaseIterable, Identifiable {
    case frame, center, nextDisplay, previousDisplay, restore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frame: "Move & Resize"
        case .center: "Center"
        case .nextDisplay: "Move to Next Display"
        case .previousDisplay: "Move to Previous Display"
        case .restore: "Revert to Original Frame"
        }
    }
}

struct Control: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var action: ControlAction
    var frame: UnitRect = .full
    var hotkey: Hotkey?
    var showInPalette = true
}

extension Control {
    private static func make(_ name: String, _ action: ControlAction = .frame, _ frame: UnitRect = .full,
                             key: UInt32, mods: UInt32 = Hotkey.ctrlOpt) -> Control {
        Control(name: name, action: action, frame: frame, hotkey: Hotkey(keyCode: key, modifiers: mods))
    }

    static var defaults: [Control] {
        let t = 1.0 / 3.0
        return [
            make("Fill Screen", .frame, .full, key: 36),
            make("Left Half", .frame, UnitRect(x: 0, y: 0, w: 0.5, h: 1), key: 123),
            make("Right Half", .frame, UnitRect(x: 0.5, y: 0, w: 0.5, h: 1), key: 124),
            make("Top Half", .frame, UnitRect(x: 0, y: 0, w: 1, h: 0.5), key: 126),
            make("Bottom Half", .frame, UnitRect(x: 0, y: 0.5, w: 1, h: 0.5), key: 125),
            make("Left Third", .frame, UnitRect(x: 0, y: 0, w: t, h: 1), key: 2),
            make("Center Third", .frame, UnitRect(x: t, y: 0, w: t, h: 1), key: 3),
            make("Right Third", .frame, UnitRect(x: 2 * t, y: 0, w: t, h: 1), key: 5),
            make("Left Two Thirds", .frame, UnitRect(x: 0, y: 0, w: 2 * t, h: 1), key: 14),
            make("Right Two Thirds", .frame, UnitRect(x: t, y: 0, w: 2 * t, h: 1), key: 17),
            make("Center", .center, key: 8),
            make("Next Display", .nextDisplay, key: 124, mods: Hotkey.ctrlOptCmd),
            make("Previous Display", .previousDisplay, key: 123, mods: Hotkey.ctrlOptCmd),
            make("Revert", .restore, key: 51),
        ]
    }
}

struct Settings: Codable, Equatable {
    var hoverEnabled = true
    var hoverDelay = 0.3
    var gridColumns = 6
    var gridRows = 4
    var gap: Double = 0
    var controls = Control.defaults
    /// Shortcut that enters keyboard mode (⌥⌘, by default).
    var keyboardHotkey: Hotkey? = Hotkey(keyCode: 43, modifiers: Hotkey.optCmd)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        hoverEnabled = try c.decodeIfPresent(Bool.self, forKey: .hoverEnabled) ?? d.hoverEnabled
        hoverDelay = try c.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? d.hoverDelay
        gridColumns = try c.decodeIfPresent(Int.self, forKey: .gridColumns) ?? d.gridColumns
        gridRows = try c.decodeIfPresent(Int.self, forKey: .gridRows) ?? d.gridRows
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? d.gap
        controls = try c.decodeIfPresent([Control].self, forKey: .controls) ?? d.controls
        keyboardHotkey = c.contains(.keyboardHotkey)
            ? try c.decodeIfPresent(Hotkey.self, forKey: .keyboardHotkey)
            : d.keyboardHotkey
    }
}

final class Store: ObservableObject {
    static let shared = Store()
    private let key = "settings.v1"

    @Published var settings: Settings {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let s = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = s
        } else {
            settings = Settings()
        }
    }

    func control(id: UUID) -> Control? {
        settings.controls.first { $0.id == id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
