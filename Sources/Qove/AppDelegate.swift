import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hover = HoverMonitor()
    private let palette = PaletteController()
    private let keyboardMode = KeyboardController()
    private var prefsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Qove")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        Store.shared.$settings
            .map { ($0.controls, $0.keyboardHotkey) }
            .removeDuplicates(by: ==)
            .sink { [weak self] in self?.registerHotkeys($0.0, keyboard: $0.1) }
            .store(in: &cancellables)

        hover.onHover = { [weak self] window, button in self?.palette.show(for: window, buttonFrame: button) }
        hover.start()

        if !Permissions.isTrusted {
            Permissions.prompt()
            openPreferences()
        }
    }

    private func registerHotkeys(_ controls: [Control], keyboard: Hotkey?) {
        var bindings: [(Hotkey, () -> Void)] = controls.compactMap { c in
            c.hotkey.map { hk in
                (hk, { [id = c.id] in
                    if let c = Store.shared.control(id: id) { WindowManager.shared.perform(c) }
                })
            }
        }
        if let keyboard {
            bindings.append((keyboard, { [weak self] in self?.keyboardMode.toggle() }))
        }
        HotkeyManager.shared.register(bindings)
    }

    // MARK: Status menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !Permissions.isTrusted {
            menu.addItem(item("Grant Accessibility Access…", #selector(grantAccess)))
            menu.addItem(.separator())
        }

        let kb = item("Keyboard Controls", #selector(startKeyboardMode))
        if let hk = Store.shared.settings.keyboardHotkey, let key = hk.menuKeyEquivalent {
            kb.keyEquivalent = key
            kb.keyEquivalentModifierMask = hk.cocoaModifiers
        }
        kb.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        menu.addItem(kb)
        menu.addItem(.separator())

        for c in Store.shared.settings.controls {
            let mi = item(c.name, #selector(runControl(_:)))
            mi.representedObject = c.id
            if let hk = c.hotkey, let key = hk.menuKeyEquivalent {
                mi.keyEquivalent = key
                mi.keyEquivalentModifierMask = hk.cocoaModifiers
            }
            mi.image = iconImage(for: c)
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let hoverItem = item("Show Palette on Green-Button Hover", #selector(toggleHover))
        hoverItem.state = Store.shared.settings.hoverEnabled ? .on : .off
        menu.addItem(hoverItem)
        menu.addItem(item("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Qove", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = target ?? self
        return mi
    }

    private func iconImage(for c: Control) -> NSImage {
        let img = NSImage(size: NSSize(width: 20, height: 14), flipped: true) { rect in
            ControlIconDrawing.draw(c, in: rect.insetBy(dx: 1, dy: 1), flipped: true)
            return true
        }
        return img
    }

    @objc private func runControl(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let c = Store.shared.control(id: id) else { return }
        WindowManager.shared.perform(c)
    }

    @objc private func startKeyboardMode() {
        // Let the status menu close and focus return to the previous app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.keyboardMode.toggle() }
    }

    @objc private func toggleHover() {
        Store.shared.settings.hoverEnabled.toggle()
    }

    @objc private func grantAccess() {
        Permissions.prompt()
        Permissions.openSettings()
    }

    @objc func openPreferences() {
        if prefsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView()))
            w.title = "Qove Preferences"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            prefsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        prefsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Accessory apps have no visible menu bar, but text fields still need Edit-menu key equivalents.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Qove", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
