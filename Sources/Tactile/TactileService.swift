import Foundation

/// Everything Tactile runs: certificates, the setup page, the secure app and
/// socket servers, and pairing. The menu bar and the Terminal banner both drive
/// it and watch it; all of its own work happens on one serial queue.
final class TactileService {
    struct Snapshot {
        var running: Bool
        /// Paused from the menu or the shortcut.
        var paused: Bool
        /// Paused because the Mac is locked (and that option is on).
        var lockPaused: Bool
        var dryRun: Bool
        var usesTailscale: Bool
        var code: String
        var setupURLs: [String]
        var pairingLink: String
        var localURL: String
        var tailscaleURL: String?
        var fingerprint: String
        var devices: [Pairing.Device]
        var connected: Set<String>
        /// Devices disconnected from the menu, kept off until reconnected.
        var held: Set<String>
        /// Round-trip time to each connected device, in milliseconds.
        var latency: [String: Int]
        /// When each device last sent input.
        var lastInput: [String: Date]
        var tailscaleExpiry: Date?
        var portsSummary: String
        var setupHost: String
    }

    enum Event {
        case started
        case newCode
        case paired(Pairing.Device)
        case connected(Pairing.Device)
    }

    let queue = DispatchQueue(label: "tactile.server")
    private let pairing = Pairing()
    private let assets: [String: HTTPServer.Asset]
    private let dryRun: Bool
    private let setupPort: UInt16
    private var useTailscale: Bool

    private var local: LocalAuthority?
    private var tailscaleURL: String?
    private var pages: [HTTPServer] = []
    private var sockets: [SocketServer] = []
    private var running = false
    private var paused = false
    private var lockPaused = false
    private var held: Set<String> = []
    private var latency: [String: Int] = [:]
    private var lastInput: [String: Date] = [:]
    private var lastActivityPublish = Date.distantPast
    private var tailscaleExpiry: Date?
    private var lastActive: [String: Date] = [:]

    private var stateObservers: [(Snapshot) -> Void] = []
    private var eventObservers: [(Event) -> Void] = []

    private var localPorts: (app: UInt16, socket: UInt16) { (setupPort + 1, setupPort + 2) }
    private var tailscalePorts: (app: UInt16, socket: UInt16) { (setupPort + 3, setupPort + 4) }
    private var devPorts: (app: UInt16, socket: UInt16) { (setupPort + 5, setupPort + 6) }
    private let basePolicy = "default-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'"

    init(webRoot: URL, setupPort: UInt16, dryRun: Bool, useTailscale: Bool) {
        assets = HTTPServer.loadAssets(from: webRoot)
        self.setupPort = setupPort
        self.dryRun = dryRun
        self.useTailscale = useTailscale
        pairing.onNewCode = { [weak self] in
            self?.publish()
            self?.emit(.newCode)
        }
        pairing.onDevicesChanged = { [weak self] in self?.publish() }
    }

    // MARK: Observing (callbacks arrive on the main queue)

    func observe(_ handler: @escaping (Snapshot) -> Void) {
        queue.async { self.stateObservers.append(handler) }
    }

    func observeEvents(_ handler: @escaping (Event) -> Void) {
        queue.async { self.eventObservers.append(handler) }
    }

    private func publish() {
        let state = snapshot()
        let observers = stateObservers
        DispatchQueue.main.async { observers.forEach { $0(state) } }
    }

    private func emit(_ event: Event) {
        let observers = eventObservers
        DispatchQueue.main.async { observers.forEach { $0(event) } }
    }

    private func snapshot() -> Snapshot {
        let hosts = [HostInfo.bonjourName].compactMap { $0 } + HostInfo.ipv4Addresses
        let setupURLs = hosts.map { "http://\($0):\(setupPort)" }
        let host = hosts.first ?? "localhost"
        let connected = Set(sockets.flatMap(\.connectedDeviceIDs))
        var ports = "\(localPorts.app)–\(localPorts.socket)"
        if tailscaleURL != nil { ports += " · Tailscale \(tailscalePorts.app)–\(tailscalePorts.socket)" }
        return Snapshot(
            running: running,
            paused: paused,
            lockPaused: lockPaused,
            dryRun: dryRun,
            usesTailscale: useTailscale,
            code: pairing.code,
            setupURLs: setupURLs,
            pairingLink: "\(setupURLs.first ?? "http://localhost:\(setupPort)")/#pair=\(pairing.code)",
            localURL: "https://\(host):\(localPorts.app)",
            tailscaleURL: running ? tailscaleURL : nil,
            fingerprint: local?.fingerprint ?? "",
            devices: pairing.devices.sorted { $0.lastSeen > $1.lastSeen },
            connected: connected,
            held: held,
            latency: latency.filter { connected.contains($0.key) },
            lastInput: lastInput,
            tailscaleExpiry: running ? tailscaleExpiry : nil,
            portsSummary: ports,
            setupHost: "\(host):\(setupPort)"
        )
    }

    // MARK: Controls

    func start() { queue.async { self.startNow() } }
    func stop() { queue.async { self.stopNow() } }

    /// Stops right away, for quitting.
    func stopAndWait() { queue.sync { self.stopNow() } }

    func setPaused(_ value: Bool) {
        queue.async {
            self.paused = value
            if value { self.sockets.forEach { $0.releaseAllInput() } }
            Log.info(value ? "Input paused." : "Input resumed.")
            self.publish()
        }
    }

    /// Pauses input while the Mac is locked, separately from the manual pause.
    func setLockPaused(_ value: Bool) {
        queue.async {
            guard self.lockPaused != value else { return }
            self.lockPaused = value
            if value { self.sockets.forEach { $0.releaseAllInput() } }
            Log.info(value ? "Input paused while the Mac is locked." : "Mac unlocked; input resumed.")
            self.publish()
        }
    }

    /// Disconnects a device and keeps it off (it would otherwise reconnect
    /// straight away) until `reconnect` or the next start.
    func disconnect(_ id: String) {
        queue.async {
            self.held.insert(id)
            self.sockets.forEach { $0.disconnect(deviceID: id) }
            Log.info("Disconnected a device until it's reconnected from the menu.")
            self.publish()
        }
    }

    func reconnect(_ id: String) {
        queue.async {
            self.held.remove(id)
            self.publish()
        }
    }

    func setUseTailscale(_ value: Bool) {
        queue.async {
            self.useTailscale = value
            guard self.running else { return self.publish() }
            self.stopNow()
            self.startNow()
        }
    }

    func revoke(_ id: String) {
        queue.async {
            self.pairing.revoke(id)
            self.sockets.forEach { $0.disconnect(deviceID: id) }
            Log.info("Revoked a paired device.")
        }
    }

    func revokeAll() {
        queue.async {
            self.pairing.revokeAll()
            self.sockets.forEach { $0.disconnect(deviceID: nil) }
            Log.info("Revoked all paired devices.")
        }
    }

    // MARK: Lifecycle (on the queue)

    private func startNow() {
        guard !running else { return }
        do {
            // The local certificate authority is made once; a fresh server
            // certificate is issued on every start for the current addresses.
            let local = try LocalAuthority.prepare(hostName: HostInfo.bonjourName, addresses: HostInfo.ipv4Addresses)
            self.local = local
            let tailscale = useTailscale ? Tailscale.certificate() : nil
            HostInfo.tailscaleName = tailscale?.host
            tailscaleExpiry = tailscale?.expires
            tailscaleURL = tailscale.map { "https://\($0.host):\(tailscalePorts.app)/" }

            pages = [try setupServer(local: local)]
            sockets = []
            try addApp(local.identity, ports: localPorts, route: "Wi-Fi")
            if let tailscale { try addApp(tailscale.identity, ports: tailscalePorts, route: "Tailscale") }
            // Lets a browser on this Mac try the UI without trusting the
            // certificate. Input is only logged in a dry run.
            if dryRun { try addApp(nil, ports: devPorts, route: "Dry run") }
        } catch {
            return Fatal.report("Tactile couldn't start: \(error)")
        }

        pages.forEach { $0.start() }
        sockets.forEach { $0.start() }
        running = true
        Log.info("Tactile started.")
        publish()
        emit(.started)
    }

    private func stopNow() {
        guard running else { return }
        sockets.forEach { $0.stop() }
        pages.forEach { $0.stop() }
        sockets = []
        pages = []
        running = false
        paused = false
        held = []
        latency = [:]
        Log.info("Tactile stopped.")
        publish()
    }

    private func setupServer(local: LocalAuthority) throws -> HTTPServer {
        // Plain HTTP serves only the setup page, which sends the iPad to
        // whichever secure address it can use.
        var setup = assets.filter { $0.key.hasPrefix("/setup/") || $0.key == "/icon.svg" || $0.key == "/apple-touch-icon.png" }
        setup["/index.html"] = assets["/setup/index.html"]
        var info: [String: Any] = ["appPort": Int(localPorts.app), "fingerprint": local.fingerprint, "caName": local.caName]
        if let tailscaleURL { info["tailscaleURL"] = tailscaleURL }
        setup["/setup.json"] = HTTPServer.json(info)
        setup["/tactile-ca.crt"] = HTTPServer.Asset(body: local.caDER, type: "application/x-x509-ca-cert")
        return try HTTPServer(port: setupPort, tls: nil, assets: setup,
                              policy: "\(basePolicy); connect-src 'self' https:", queue: queue)
    }

    /// The keyboard page and its socket, served with one certificate. Without a
    /// certificate (dry-run development copy only) both listen on 127.0.0.1 alone.
    private func addApp(_ identity: TLSIdentity?, ports: (app: UInt16, socket: UInt16), route: String) throws {
        var pageAssets = assets.filter { !$0.key.hasPrefix("/setup/") }
        pageAssets["/config.json"] = HTTPServer.json(["socketPort": Int(ports.socket)])
        let loopbackOnly = identity == nil
        pages.append(try HTTPServer(port: ports.app, tls: identity?.options(), assets: pageAssets,
                                    policy: "\(basePolicy); connect-src 'self' \(loopbackOnly ? "ws:" : "wss:")",
                                    loopbackOnly: loopbackOnly, queue: queue))

        let dryRun = dryRun
        let socket = try SocketServer(port: ports.socket, appPort: ports.app, tls: identity?.options(),
                                      loopbackOnly: loopbackOnly, route: route, pairing: pairing, queue: queue) {
            dryRun ? LoggingInput() as InputTarget : InputSession()
        }
        socket.isPaused = { [weak self] in (self?.paused ?? false) || (self?.lockPaused ?? false) }
        socket.isHeld = { [weak self] id in self?.held.contains(id) ?? false }
        socket.onInput = { [weak self] id in self?.inputArrived(from: id) }
        socket.onLatency = { [weak self] id, ms in
            self?.latency[id] = ms
            self?.publish()
        }
        socket.onChange = { [weak self] in self?.connectionsChanged() }
        socket.onConnect = { [weak self] device, isNew in self?.connected(device, isNew: isNew) }
        sockets.append(socket)
    }

    /// Marks a device as typing; the menu shows "input flowing" for a moment.
    /// Published at most twice a second, however fast the input arrives.
    private func inputArrived(from id: String) {
        let now = Date()
        lastInput[id] = now
        if now.timeIntervalSince(lastActivityPublish) > 0.5 {
            lastActivityPublish = now
            publish()
        }
    }

    private var connectedBefore: Set<String> = []

    /// Remembers when each device was last connected, so a quick reconnect
    /// (the iPad waking up) isn't announced as a new connection.
    private func connectionsChanged() {
        let now = Date()
        let current = Set(sockets.flatMap(\.connectedDeviceIDs))
        for id in connectedBefore.union(current) { lastActive[id] = now }
        connectedBefore = current
        publish()
    }

    /// Announce new pairings, and connections from a device that hasn't been
    /// around for a while (not every reconnect after the iPad wakes).
    private func connected(_ device: Pairing.Device, isNew: Bool) {
        let now = Date()
        let recent = lastActive[device.id].map { now.timeIntervalSince($0) < 10 * 60 } ?? false
        lastActive[device.id] = now
        if isNew { emit(.paired(device)) } else if !recent { emit(.connected(device)) }
    }
}
