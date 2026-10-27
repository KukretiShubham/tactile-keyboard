import AppKit
import Carbon.HIToolbox
import TactileCore

setvbuf(stdout, nil, _IOLBF, 0)

let arguments = CommandLine.arguments

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    Tactile — use an iPad as a keyboard and trackpad for this Mac.

    Usage: Tactile [--port 8420] [--dry-run] [--no-tailscale] [--forget-devices]

      --port N           Setup page port. The app uses N + 1 and N + 2 with this
                         Mac's local certificate, and N + 3 and N + 4 with its
                         Tailscale certificate. Default 8420.
      --dry-run          Log input instead of controlling the Mac, and serve a
                         plain-HTTP copy of the page on N + 5 (socket N + 6),
                         reachable only from this Mac.
      --no-tailscale     Don't ask Tailscale for a certificate.
      --forget-devices   Remove every paired iPad and exit.
    """)
    exit(0)
}

if arguments.contains("--forget-devices") {
    Pairing.forgetAll()
    print("All paired devices were removed.")
    exit(0)
}

// Inside Tactile.app there's no Terminal, so output goes to a log file
// (the menu has "Show Log").
let isApp = Bundle.main.bundleIdentifier != nil
if isApp {
    let log = Paths.logFile
    try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let size = (try? FileManager.default.attributesOfItem(atPath: log.path))?[.size] as? Int, size > 1_000_000 {
        try? FileManager.default.removeItem(at: log)
    }
    freopen(log.path, "a", stdout)
    freopen(log.path, "a", stderr)
    setvbuf(stdout, nil, _IOLBF, 0)
}

/// The app bundle keeps the web files in Contents/Resources; `swift run`
/// keeps them in SwiftPM's resource bundle.
func locateWebRoot() -> URL? {
    if let url = Bundle.main.resourceURL?.appendingPathComponent("Web"),
       FileManager.default.fileExists(atPath: url.appendingPathComponent("index.html").path) {
        return url
    }
    return Bundle.module.url(forResource: "Web", withExtension: nil)
}

guard let webRoot = locateWebRoot() else {
    Fatal.report("Web resources are missing from the build.")
    exit(1)
}

let dryRun = arguments.contains("--dry-run")
if !dryRun && !Accessibility.isTrusted(prompt: true) {
    Log.warn("""
    Accessibility access is off, so input can't reach other apps yet.
      Open System Settings → Privacy & Security → Accessibility and allow \(isApp ? "Tactile" : "the app you launched Tactile from (for example Terminal)").
    """)
}

let preferences = UserDefaults.standard
preferences.register(defaults: ["useTailscale": true, "notifyOnConnect": true, "onlyMyTailscaleDevices": true])
let service = TactileService(
    webRoot: webRoot,
    setupPort: option("--port").flatMap(UInt16.init) ?? 8420,
    dryRun: dryRun,
    useTailscale: !arguments.contains("--no-tailscale") && preferences.bool(forKey: "useTailscale"),
    onlyMyDevices: preferences.bool(forKey: "onlyMyTailscaleDevices")
)

// In Terminal, show the QR code and pairing code whenever they change.
if !isApp {
    var printedFor: String?
    service.observe { state in
        guard state.running, printedFor != state.code else { return }
        if printedFor != nil { Log.info("That pairing code is used up. Here's a new one for the next device:") }
        printedFor = state.code
        Banner.show(state)
    }
}

// Key labels on the iPad follow the Mac's keyboard layout (read on the main
// thread), including when the input language changes.
service.setKeyboardLabels(KeyboardLayout.currentLabels())
let layoutObserver = DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
) { _ in service.setKeyboardLabels(KeyboardLayout.currentLabels()) }

// The iPad shows hotkeys for the app in front, with icons read from the apps
// themselves.
service.appIcons = { ids, done in DispatchQueue.main.async { done(AppIcons.dataURLs(for: ids)) } }
service.focusApp = { id, hint in DispatchQueue.main.async { AppFocus.bring(id, window: hint) } }
func reportFrontApp(_ app: NSRunningApplication?) {
    guard let app, let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return }
    service.setFrontApp(id: id, name: app.localizedName ?? id)
}
reportFrontApp(NSWorkspace.shared.frontmostApplication)
let frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
) { note in reportFrontApp(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let menuBar = MenuBarController(service: service, isApp: isApp)

if isApp {
    Fatal.handler = { message in
        DispatchQueue.main.async {
            Log.warn(message)
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Tactile can't continue"
            alert.informativeText = message
            alert.runModal()
            exit(1)
        }
    }
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let stopSources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        service.stopAndWait()
        print("\nTactile stopped.")
        exit(0)
    }
    source.resume()
    return source
}

service.start()
app.run()
