import Foundation
import Network

/// WebSocket endpoint the iPad talks to. Each connection must pair (or present a
/// saved token) before any input is accepted, and gets its own input session so
/// held keys are released when that iPad disconnects.
public final class SocketServer {
    private final class Client {
        let connection: NWConnection
        let address: String
        let input: InputTarget
        var deviceID: String?
        var authTimeout: DispatchWorkItem?
        /// Who Tailscale says owns this device (Tailscale route only).
        var peer: Tailscale.Peer?

        init(connection: NWConnection, address: String, input: InputTarget) {
            self.connection = connection
            self.address = address
            self.input = input
        }
    }

    private struct Message: Decodable {
        let t: String
        var k: String?
        var token: String?
        var code: String?
        var name: String?
        var b: String?
        var s: String?
        var x: Double?
        var y: Double?
        var r: Bool?
        var n: String?
        /// Keys of a shortcut, e.g. ["MetaLeft", "KeyC"]; or bundle IDs of apps
        /// whose icons the page wants.
        var ks: [String]?
    }

    private static let inputTypes: Set = ["kd", "ku", "mv", "md", "mu", "sc", "sys", "txt", "combo", "focus"]

    /// Shown next to device names, e.g. "iPad · Tailscale".
    let route: String
    /// While true, input is ignored (the connection stays up).
    public var isPaused: () -> Bool = { false }
    /// A device finished connecting; `isNew` when it just paired.
    public var onConnect: ((Pairing.Device, _ isNew: Bool) -> Void)?
    /// Connected devices changed.
    var onChange: (() -> Void)?
    /// A device disconnected from the menu; it's refused until reconnected.
    public var isHeld: (String) -> Bool = { _ in false }
    /// A device asked for the app with this bundle ID to come to the front
    /// (opening it if needed), from its app hotkey tabs; if given, its window
    /// whose title includes the second string (e.g. "codex") comes first.
    public var onFocusApp: ((String, String?) -> Void)?
    /// A device sent input (used to show "input flowing").
    var onInput: ((String) -> Void)?
    /// A device's measured round-trip time, in milliseconds.
    var onLatency: ((String, Int) -> Void)?

    private var probeTimer: DispatchSourceTimer?

    /// Set on the Tailscale route: only the Mac owner's devices get in.
    public var gate: TailnetGate?
    /// Messages each device gets as soon as it connects, such as the Mac's
    /// keyboard layout and the app in front (see `broadcast`).
    var welcomeMessages: () -> [[String: Any]] = { [] }
    /// Icons of the apps with these bundle IDs that are installed on the Mac,
    /// as PNG data URLs. Calls back on any queue.
    var appIcons: ([String], @escaping ([String: String]) -> Void) -> Void = { _, done in done([:]) }

    private let listener: NWListener
    private let queue: DispatchQueue
    private let pairing: Pairing
    private let makeInput: () -> InputTarget
    private var clients: [ObjectIdentifier: Client] = [:]

    /// IDs of paired devices connected right now.
    public var connectedDeviceIDs: [String] { clients.values.compactMap(\.deviceID) }

    /// - Parameters:
    ///   - appPort: Port of the page that serves the app; only that page may connect.
    ///   - tls: Always set in normal use. Nil only for the dry-run development
    ///     copy, which is also limited to this Mac (`loopbackOnly`).
    public init(port: UInt16, appPort: UInt16, tls: NWProtocolTLS.Options?, loopbackOnly: Bool = false, route: String,
                pairing: Pairing, queue: DispatchQueue, makeInput: @escaping () -> InputTarget) throws {
        let scheme = tls == nil ? "http" : "https"
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        options.maximumMessageSize = 16 * 1024
        options.setClientRequestHandler(queue) { _, headers in
            // Only the page this Mac serves may open the socket. Browsers always
            // say which page is asking; anything that doesn't is refused.
            let origin = headers.first { $0.name.caseInsensitiveCompare("Origin") == .orderedSame }?.value
            let allowed = origin.map { Self.isAllowedOrigin($0, scheme: scheme, port: appPort) } ?? false
            return NWProtocolWebSocket.Response(status: allowed ? .accept : .reject, subprotocol: nil, additionalHeaders: nil)
        }

        // Small, frequent messages: send each one right away instead of batching.
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.allowLocalEndpointReuse = true
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        listener = try NWListener.make(parameters, port: port, loopbackOnly: loopbackOnly)

        self.route = route
        self.queue = queue
        self.pairing = pairing
        self.makeInput = makeInput
    }

    /// Starts listening; `ready` receives the port once it's open.
    public func start(ready: ((UInt16) -> Void)? = nil) {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.watch("secure connection", ready: ready)
        listener.start(queue: queue)

        // Every few seconds, time a round trip to each device for the menu's
        // connection quality. The page echoes the timestamp straight back.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 3)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = String(Self.uptimeMilliseconds)
            for client in clients.values where client.deviceID != nil {
                reply(client, ["t": "probe", "n": now])
            }
        }
        timer.resume()
        probeTimer = timer
    }

    private static var uptimeMilliseconds: Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }

    /// Stops listening and lets go of everything every iPad is holding.
    /// Call on the server queue.
    public func stop() {
        probeTimer?.cancel()
        probeTimer = nil
        listener.cancel()
        let all = clients.values
        clients.removeAll()
        for client in all {
            client.input.releaseAll()
            client.connection.cancel()
        }
        onChange?()
    }

    /// Releases held keys and buttons for every connected iPad.
    func releaseAllInput() {
        clients.values.forEach { $0.input.releaseAll() }
    }

    /// Sends `payload` to every connected, paired device.
    func broadcast(_ payload: [String: Any]) {
        for client in clients.values where client.deviceID != nil {
            reply(client, payload)
        }
    }

    /// Disconnects a device right away (for example after it's revoked).
    func disconnect(deviceID: String?) {
        for client in clients.values where deviceID == nil || client.deviceID == deviceID {
            client.connection.cancel()
        }
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        let client = Client(connection: connection, address: Self.address(of: connection), input: makeInput())
        let id = ObjectIdentifier(client)
        clients[id] = client

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.drop(id)
            default: break
            }
        }
        connection.start(queue: queue)

        let timeout = DispatchWorkItem { [weak client] in
            if let client, client.deviceID == nil { client.connection.cancel() }
        }
        client.authTimeout = timeout
        queue.asyncAfter(deadline: .now() + 120, execute: timeout)

        // Over Tailscale, nothing is read until Tailscale confirms the device
        // is yours, so other people's devices never reach pairing.
        guard let gate, gate.isEnabled() else { return receive(client) }
        gate.check(client.address, on: queue) { [weak self, weak client] verdict in
            guard let self, let client, clients[ObjectIdentifier(client)] != nil else { return }
            switch verdict {
            case .allowed(let peer):
                client.peer = peer
                receive(client)
            case .refused(let reason):
                Log.warn("Refused a Tailscale connection from \(client.address): \(reason).")
                refuse(client, reason: "foreign")
            }
        }
    }

    private func drop(_ id: ObjectIdentifier) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.authTimeout?.cancel()
        client.input.releaseAll()
        if client.deviceID != nil {
            Log.info("Disconnected \(client.address)")
            onChange?()
        }
    }

    private func receive(_ client: Client) {
        client.connection.receiveMessage { [weak self] data, context, _, error in
            guard let self, error == nil else {
                client.connection.cancel()
                return
            }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            switch metadata?.opcode {
            case .close:
                client.connection.cancel()
                return
            case .text:
                if let data { self.handle(data, from: client) }
            default:
                break
            }
            if self.clients[ObjectIdentifier(client)] != nil { self.receive(client) }
        }
    }

    /// Says why, then disconnects a moment later so the reason arrives first.
    private func refuse(_ client: Client, reason: String) {
        reply(client, ["t": "denied", "reason": reason])
        queue.asyncAfter(deadline: .now() + 0.5) { client.connection.cancel() }
    }

    private func reply(_ client: Client, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "reply", metadata: [metadata])
        client.connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    // MARK: Messages

    private func handle(_ data: Data, from client: Client) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
        guard let deviceID = client.deviceID else { return authenticate(message, client) }

        // A device revoked while connected loses access at once.
        guard pairing.devices.contains(where: { $0.id == deviceID }) else {
            client.connection.cancel()
            return
        }

        let input = client.input
        switch message.t {
        case "ping": reply(client, ["t": "pong"])
        case "icons":
            // A short list of plausible bundle IDs; the reply has only the
            // ones installed on this Mac.
            guard let ids = message.ks, ids.count <= 64, ids.allSatisfy(Self.isBundleID) else { return }
            appIcons(ids) { [weak self, weak client] icons in
                self?.queue.async {
                    guard let self, let client, self.clients[ObjectIdentifier(client)] != nil else { return }
                    self.reply(client, ["t": "icons", "icons": icons])
                }
            }
        case "probe":
            if let sent = message.n.flatMap(Int.init) {
                onLatency?(deviceID, max(0, Self.uptimeMilliseconds - sent))
            }
        case "rel": input.releaseAll()
        case _ where isPaused(): break
        case "kd": if let key = message.k { input.keyDown(key, isRepeat: message.r ?? false) }
        case "ku": if let key = message.k { input.keyUp(key) }
        case "mv": input.move(dx: Self.limit(message.x, 800), dy: Self.limit(message.y, 800))
        case "md", "mu":
            if let button = message.b.flatMap(MouseButton.init) { input.button(button, down: message.t == "md") }
        case "sc": input.scroll(dx: Self.limit(message.x, 2000), dy: Self.limit(message.y, 2000))
        case "sys": if let action = message.k.flatMap(SystemAction.init) { input.system(action) }
        case "combo":
            // Shortcuts are a few known keys; anything else is ignored.
            if let codes = message.ks, (1...5).contains(codes.count), codes.allSatisfy({ KeyMap.codes[$0] != nil }) {
                input.combo(codes)
            }
        case "txt": if let text = message.s, text.count <= 4000 { input.type(text) }
        case "focus":
            if let id = message.k, Self.isBundleID(id) { onFocusApp?(id, message.s.flatMap(Self.windowHint)) }
        default: break
        }
        if Self.inputTypes.contains(message.t) && !isPaused() { onInput?(deviceID) }
    }

    private func authenticate(_ message: Message, _ client: Client) {
        if pairing.isLocked(client.address) {
            return reply(client, ["t": "denied", "reason": "locked"])
        }
        switch message.t {
        case "hello":
            if let token = message.token, let device = pairing.device(forToken: token) {
                if isHeld(device.id) {
                    refuse(client, reason: "held")
                    return
                }
                pairing.improveName(device.id, to: "\(client.peer?.deviceName ?? DeviceKind.name(claimed: message.name)) · \(route)",
                                    isRealName: client.peer != nil)
                let named = pairing.devices.first { $0.id == device.id } ?? device
                grant(client, device: named, token: nil)
            } else {
                reply(client, ["t": "pair"])
            }
        case "pair":
            let name = "\(client.peer?.deviceName ?? DeviceKind.name(claimed: message.name)) · \(route)"
            if let code = message.code, let paired = pairing.redeem(code: code, from: client.address, name: name) {
                Log.info("Paired \(name) at \(client.address)")
                grant(client, device: paired.device, token: paired.token)
            } else {
                let reason = pairing.isLocked(client.address) ? "locked" : "code"
                reply(client, ["t": "denied", "reason": reason])
            }
        default:
            client.connection.cancel()
        }
    }

    private func grant(_ client: Client, device: Pairing.Device, token: String?) {
        client.deviceID = device.id
        client.authTimeout?.cancel()
        pairing.markSeen(device.id)
        var payload = ["t": "ready", "name": HostInfo.computerName]
        if let token { payload["token"] = token }
        reply(client, payload)
        welcomeMessages().forEach { reply(client, $0) }
        Log.info("Connected \(device.name) (\(client.address))")
        onConnect?(device, token != nil)
        onChange?()
    }

    // MARK: Helpers

    private static func limit(_ value: Double?, _ bound: Double) -> Double {
        guard let value, value.isFinite else { return 0 }
        return min(max(value, -bound), bound)
    }

    private static func address(of connection: NWConnection) -> String {
        guard case let .hostPort(host, _) = connection.endpoint else { return "unknown" }
        return "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
    }

    /// A short word to look for in window titles, or nil if it isn't one.
    private static func windowHint(_ hint: String) -> String? {
        (1...32).contains(hint.count) && hint.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" } ? hint : nil
    }

    private static func isBundleID(_ id: String) -> Bool {
        (1...128).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    private static func isAllowedOrigin(_ origin: String, scheme: String, port: UInt16) -> Bool {
        guard let url = URL(string: origin), url.scheme == scheme,
              let host = url.host?.lowercased(), url.port == Int(port) else { return false }
        return HostInfo.reachableHosts.contains(host)
    }
}
