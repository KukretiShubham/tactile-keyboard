import AppKit
import ServiceManagement

/// The Tactile icon in the menu bar, next to Wi-Fi and Control Center.
/// Its menu shows what's connected and holds every control.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let service: TactileService
    private let isApp: Bool
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let notifier: Notifier?
    private var state: TactileService.Snapshot?
    private var trusted = Accessibility.isTrusted(prompt: false)
    private lazy var pairingWindow = PairingWindowController()
    private var trustTimer: Timer?

    private let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    init(service: TactileService, isApp: Bool) {
        self.service = service
        self.isApp = isApp
        notifier = isApp ? Notifier() : nil
        super.init()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.setAccessibilityLabel("Tactile")
        updateIcon()

        service.observe { [weak self] state in
            self?.state = state
            self?.updateIcon()
            self?.pairingWindow.update(state)
        }
        service.observeEvents { [weak self] event in self?.handle(event) }

        // Accessibility can be switched on at any time in System Settings.
        trustTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Accessibility.isTrusted(prompt: false)
            if now != trusted {
                trusted = now
                updateIcon()
            }
        }
    }

    // MARK: Icon

    private var statusText: String {
        guard let state else { return "Starting…" }
        if !state.running { return "Stopped" }
        if !trusted && !state.dryRun { return "Needs Accessibility access" }
        if state.paused { return "Input paused" }
        let names = connectedDevices.map(\.name)
        return names.isEmpty ? "Waiting for an iPad" : "Connected: \(names.joined(separator: ", "))"
    }

    private var connectedDevices: [Pairing.Device] {
        guard let state else { return [] }
        return state.devices.filter { state.connected.contains($0.id) }
    }

    private func updateIcon() {
        let symbol: String
        if let state, !state.running {
            symbol = "keyboard.badge.ellipsis"
        } else if !trusted && state?.dryRun != true {
            symbol = "exclamationmark.triangle"
        } else if state?.paused == true {
            symbol = "pause.rectangle"
        } else if !connectedDevices.isEmpty {
            symbol = "keyboard.fill"
        } else {
            symbol = "keyboard"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Tactile")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = state?.running == false
        statusItem.button?.toolTip = "Tactile — \(statusText)"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = state?.running == true

        menu.addItem(header("Tactile — \(statusText)"))
        if running {
            let connected = connectedDevices
            if connected.isEmpty {
                menu.addItem(note("No iPad connected"))
            } else {
                connected.forEach { menu.addItem(note("●  \($0.name)")) }
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Show Pairing Code…", key: "p", enabled: running) { [weak self] in self?.showPairing() })
        if let link = state?.tailscaleURL {
            menu.addItem(item("Copy Tailscale Link") { Self.copy(link) })
        }

        menu.addItem(.separator())
        let pause = item("Pause Input", key: ".", enabled: running) { [weak self] in
            self?.service.setPaused(!(self?.state?.paused ?? false))
        }
        pause.state = state?.paused == true ? .on : .off
        menu.addItem(pause)
        menu.addItem(item(running ? "Stop Tactile" : "Start Tactile") { [weak self] in
            guard let self else { return }
            running ? service.stop() : service.start()
        })

        menu.addItem(.separator())
        menu.addItem(devicesItem())
        menu.addItem(settingsItem())
        if !trusted && state?.dryRun != true {
            menu.addItem(item("Allow Accessibility Access…") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            })
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit Tactile", key: "q") { [weak self] in
            self?.service.stopAndWait()
            NSApp.terminate(nil)
        })
    }

    private func devicesItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let devices = state?.devices ?? []
        if devices.isEmpty {
            submenu.addItem(note("No paired devices"))
        }
        for device in devices {
            let online = state?.connected.contains(device.id) == true
            let detail = online ? "connected now" : "last used \(relative.localizedString(for: device.lastSeen, relativeTo: Date()))"
            let entry = item("\(device.name) — \(detail)") { [weak self] in self?.confirmRevoke(device) }
            entry.toolTip = "Paired \(device.pairedAt.formatted(date: .abbreviated, time: .shortened)). Choose to revoke."
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        submenu.addItem(item("Revoke All…", enabled: !devices.isEmpty) { [weak self] in self?.confirmRevokeAll() })

        let parent = NSMenuItem(title: "Paired Devices", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func settingsItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let defaults = UserDefaults.standard

        let tailscale = item("Use Tailscale") { [weak self] in
            let value = !defaults.bool(forKey: "useTailscale")
            defaults.set(value, forKey: "useTailscale")
            self?.service.setUseTailscale(value)
        }
        tailscale.state = state?.usesTailscale == true ? .on : .off
        tailscale.toolTip = "Serve Tactile with a trusted Tailscale certificate when Tailscale is running."
        submenu.addItem(tailscale)

        let notify = item("Notify When a Device Connects", enabled: isApp) {
            defaults.set(!defaults.bool(forKey: "notifyOnConnect"), forKey: "notifyOnConnect")
        }
        notify.state = defaults.bool(forKey: "notifyOnConnect") ? .on : .off
        submenu.addItem(notify)

        let login = item("Open at Login", enabled: isApp) { [weak self] in self?.toggleLoginItem() }
        login.state = isApp && SMAppService.mainApp.status == .enabled ? .on : .off
        if !isApp { login.toolTip = "Available in Tactile.app" }
        submenu.addItem(login)

        if isApp {
            submenu.addItem(.separator())
            submenu.addItem(item("Show Log") {
                let log = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Logs/Tactile.log")
                NSWorkspace.shared.open(log)
            })
        }

        let parent = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    // MARK: Actions

    private func showPairing() {
        guard let state else { return }
        pairingWindow.show(state)
    }

    private func confirmRevoke(_ device: Pairing.Device) {
        let alert = NSAlert()
        alert.messageText = "Revoke \(device.name)?"
        alert.informativeText = "It's disconnected right away and needs a new pairing code to connect again."
        let revoke = alert.addButton(withTitle: "Revoke")
        revoke.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { service.revoke(device.id) }
    }

    private func confirmRevokeAll() {
        let alert = NSAlert()
        alert.messageText = "Revoke all paired devices?"
        alert.informativeText = "Every iPad is disconnected and needs a new pairing code to connect again."
        let revoke = alert.addButton(withTitle: "Revoke All")
        revoke.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { service.revokeAll() }
    }

    private func toggleLoginItem() {
        let login = SMAppService.mainApp
        do {
            if login.status == .enabled {
                try login.unregister()
            } else {
                try login.register()
                if login.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.informativeText = "Move Tactile.app to the Applications folder, then try again."
            NSApp.activate()
            alert.runModal()
        }
    }

    private func handle(_ event: TactileService.Event) {
        switch event {
        case .paired(let device):
            pairingWindow.close()
            notifier?.post(title: "New device paired",
                           body: "\(device.name) can now type and move the pointer on this Mac. If this wasn't you, revoke it from the Tactile menu.")
        case .connected(let device):
            if UserDefaults.standard.bool(forKey: "notifyOnConnect") {
                notifier?.post(title: "\(device.name) connected", body: "It can now type and move the pointer on this Mac.")
            }
        case .started, .newCode:
            break
        }
    }

    // MARK: Helpers

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0).bold])
        item.isEnabled = false
        return item
    }

    private func note(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.indentationLevel = 1
        return item
    }

    private func item(_ title: String, key: String = "", enabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, keyEquivalent: key, action: action)
        item.isEnabled = enabled
        return item
    }
}

/// A menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

private extension NSFont {
    var bold: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}
