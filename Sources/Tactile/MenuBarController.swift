import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

/// The Tactile icon in the menu bar, next to Wi-Fi and Control Center.
/// Clicking it drops down a panel (in the style of the Wi-Fi menu) with the
/// connected devices and every control.
final class MenuBarController: NSObject {
    private let service: TactileService
    private let isApp: Bool
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let notifier: Notifier?
    private let model = PanelModel()
    private lazy var panel = StatusPanel(model: model)
    private lazy var pairingWindow = PairingWindowController()
    private var state: TactileService.Snapshot?
    private var trusted = Accessibility.isTrusted(prompt: false)
    private var trustTimer: Timer?
    private var pauseHotKey: HotKey?
    private var screenLocked = false

    private let defaults = UserDefaults.standard

    init(service: TactileService, isApp: Bool) {
        self.service = service
        self.isApp = isApp
        notifier = isApp ? Notifier() : nil
        defaults.register(defaults: ["pauseWhenLocked": true])
        super.init()

        if let button = statusItem.button {
            button.setAccessibilityLabel("Tactile")
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        configureModel()
        updateIcon()

        service.observe { [weak self] state in
            self?.state = state
            self?.model.state = state
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
                model.trusted = now
                updateIcon()
            }
        }

        // ⌃⌥⌘P pauses or resumes input from any app.
        pauseHotKey = HotKey(keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.togglePause()
        }
        if pauseHotKey == nil { Log.warn("The ⌃⌥⌘P shortcut is taken by another app; pause from the menu instead.") }

        watchScreenLock()
    }

    // MARK: Panel

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.dismiss()
        } else if let button = statusItem.button {
            model.loginAvailable = isApp
            model.openAtLogin = isApp && SMAppService.mainApp.status == .enabled
            model.showDetails = NSEvent.modifierFlags.contains(.option)
            model.confirmingRevoke = nil
            button.highlight(true)
            panel.show(below: button) { button.highlight(false) }
        }
    }

    private func configureModel() {
        model.trusted = trusted
        model.pauseWhenLocked = defaults.bool(forKey: "pauseWhenLocked")
        model.notifyOnConnect = defaults.bool(forKey: "notifyOnConnect")
        model.actions = PanelModel.Actions(
            setRunning: { [weak self] on in on ? self?.service.start() : self?.service.stop() },
            setPaused: { [weak self] on in self?.service.setPaused(on) },
            setPauseWhenLocked: { [weak self] on in
                guard let self else { return }
                defaults.set(on, forKey: "pauseWhenLocked")
                model.pauseWhenLocked = on
                service.setLockPaused(on && screenLocked)
            },
            setUseTailscale: { [weak self] on in
                self?.defaults.set(on, forKey: "useTailscale")
                self?.service.setUseTailscale(on)
            },
            setNotify: { [weak self] on in
                self?.defaults.set(on, forKey: "notifyOnConnect")
                self?.model.notifyOnConnect = on
            },
            setOpenAtLogin: { [weak self] on in self?.setLoginItem(on) },
            disconnect: { [weak self] id in self?.service.disconnect(id) },
            reconnect: { [weak self] id in self?.service.reconnect(id) },
            revoke: { [weak self] id in self?.service.revoke(id) },
            pair: { [weak self] in
                guard let self, let state else { return }
                panel.dismiss()
                pairingWindow.show(state)
            },
            copyTailscaleLink: { [weak self] in
                guard let link = self?.state?.tailscaleURL else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
                self?.panel.dismiss()
            },
            allowAccessibility: { [weak self] in
                self?.panel.dismiss()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            },
            showLog: { [weak self] in
                self?.panel.dismiss()
                let log = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Logs/Tactile.log")
                NSWorkspace.shared.open(log)
            },
            quit: { [weak self] in
                self?.service.stopAndWait()
                NSApp.terminate(nil)
            }
        )
        panel.shortcuts = [
            "p": { [weak self] in self?.model.actions.pair() },
            "q": { [weak self] in self?.model.actions.quit() },
            ".": { [weak self] in self?.togglePause() },
        ]
    }

    private func togglePause() {
        service.setPaused(!(state?.paused ?? false))
    }

    // MARK: Icon

    private func updateIcon() {
        let symbol: String
        if let state, !state.running {
            symbol = "keyboard.badge.ellipsis"
        } else if !trusted && state?.dryRun != true {
            symbol = "exclamationmark.triangle"
        } else if state?.paused == true || state?.lockPaused == true {
            symbol = "pause.rectangle"
        } else if state?.connected.isEmpty == false {
            symbol = "keyboard.fill"
        } else {
            symbol = "keyboard"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Tactile")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = state?.running == false
        statusItem.button?.toolTip = "Tactile — \(tooltip)"
    }

    private var tooltip: String {
        guard let state else { return "Starting…" }
        if !state.running { return "Off" }
        if !trusted && !state.dryRun { return "Needs Accessibility access" }
        if state.paused { return "Input paused" }
        if state.lockPaused { return "Paused while Mac is locked" }
        let names = state.devices.filter { state.connected.contains($0.id) }.map(\.name)
        return names.isEmpty ? "Waiting for a device" : "Connected: \(names.joined(separator: ", "))"
    }

    // MARK: Screen lock

    /// Pauses input while the Mac is locked or the screen saver is running,
    /// if that option is on, and resumes when it's unlocked.
    private func watchScreenLock() {
        let center = DistributedNotificationCenter.default()
        let locked = ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"]
        let unlocked = ["com.apple.screenIsUnlocked", "com.apple.screensaver.didstop"]
        for (names, isLocked) in [(locked, true), (unlocked, false)] {
            for name in names {
                center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    guard let self else { return }
                    screenLocked = isLocked
                    service.setLockPaused(isLocked && defaults.bool(forKey: "pauseWhenLocked"))
                }
            }
        }
    }

    // MARK: Login item

    private func setLoginItem(_ on: Bool) {
        let login = SMAppService.mainApp
        do {
            if on {
                try login.register()
                if login.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else {
                try login.unregister()
            }
        } catch {
            panel.dismiss()
            let alert = NSAlert(error: error)
            alert.informativeText = "Move Tactile.app to the Applications folder, then try again."
            NSApp.activate()
            alert.runModal()
        }
        model.openAtLogin = login.status == .enabled
    }

    // MARK: Events

    private func handle(_ event: TactileService.Event) {
        switch event {
        case .paired(let device):
            pairingWindow.close()
            notifier?.post(title: "New device paired",
                           body: "\(device.name) can now type and move the pointer on this Mac. If this wasn't you, revoke it from the Tactile menu.")
        case .connected(let device):
            if defaults.bool(forKey: "notifyOnConnect") {
                notifier?.post(title: "\(device.name) connected", body: "It can now type and move the pointer on this Mac.")
            }
        case .started, .newCode:
            break
        }
    }
}

/// The borderless, frosted panel under the menu bar icon. It closes when you
/// click elsewhere or press Esc, and grows or shrinks with its content.
final class StatusPanel: NSPanel {
    /// ⌘-key shortcuts while the panel is open, keyed by character.
    var shortcuts: [String: () -> Void] = [:]

    private let model: PanelModel
    private var monitors: [Any] = []
    private var onClose: (() -> Void)?
    private var top: CGFloat = 0
    /// The menu bar icon's window; clicks there toggle the panel themselves.
    private weak var buttonWindow: NSWindow?

    init(model: PanelModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 330, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let material = NSVisualEffectView()
        material.material = .menu
        material.state = .active
        material.blendingMode = .behindWindow
        material.wantsLayer = true
        material.layer?.cornerRadius = 12
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true

        let hosting = ResizingHostingView(rootView: MenuPanelView(model: model))
        hosting.onResize = { [weak self] in self?.fitToContent() }
        hosting.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: material.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        contentView = material
    }

    override var canBecomeKey: Bool { true }

    func show(below button: NSStatusBarButton, onClose: @escaping () -> Void) {
        guard let anchor = button.window?.frame else { return }
        self.onClose = onClose
        buttonWindow = button.window
        let size = contentView?.fittingSize ?? frame.size
        let screen = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(anchor.minX - 8, screen.minX + 6), screen.maxX - size.width - 6)
        top = anchor.minY - 4
        setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        makeKeyAndOrderFront(nil)
        watchForDismissal()
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        onClose?()
        onClose = nil
    }

    /// Keeps the top edge under the menu bar as the content changes height.
    private func fitToContent() {
        guard let size = contentView?.fittingSize, isVisible else { return }
        setFrame(NSRect(x: frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func watchForDismissal() {
        // Clicks in other apps, or in Tactile's other windows.
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self, event.window !== buttonWindow { dismiss() }
            return event
        } as Any)
        // Esc closes; ⌘-shortcuts work while the panel is open; holding ⌥
        // shows the details section, like the Wi-Fi menu.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            if event.type == .flagsChanged {
                model.showDetails = event.modifierFlags.contains(.option)
                return event
            }
            if event.keyCode == UInt16(kVK_Escape) {
                dismiss()
                return nil
            }
            if event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers, let action = shortcuts[key] {
                action()
                return nil
            }
            return event
        } as Any)
    }
}

/// Tells the panel when SwiftUI content changes size.
private final class ResizingHostingView<Content: View>: NSHostingView<Content> {
    var onResize: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onResize?() }
    }
}
