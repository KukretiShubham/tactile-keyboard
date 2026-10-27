import Foundation
import Network

/// A tiny static file server. It only ever serves the in-memory assets it was
/// given, so requests can't reach anything else on disk.
public final class HTTPServer {
    public struct Asset: Sendable {
        let body: Data
        let type: String

        public init(body: Data, type: String) {
            self.body = body
            self.type = type
        }
    }

    private let listener: NWListener
    private let queue: DispatchQueue
    private var assets: [String: Asset]
    private let policy: String

    private static let types = [
        "html": "text/html; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "json": "application/json",
        "webmanifest": "application/manifest+json",
        "svg": "image/svg+xml",
        "png": "image/png",
    ]

    /// Loads every servable file under `root`, keyed by its URL path
    /// (prefixed with `mount`, e.g. "/app").
    public static func loadAssets(from root: URL, mount: String = "") -> [String: Asset] {
        var assets: [String: Asset] = [:]
        let rootPath = root.standardizedFileURL.path
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard let type = types[url.pathExtension], let body = try? Data(contentsOf: url) else { continue }
            assets[mount + String(url.standardizedFileURL.path.dropFirst(rootPath.count))] = Asset(body: body, type: type)
        }
        return assets
    }

    public static func json(_ object: [String: Any]) -> Asset {
        Asset(body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8), type: types["json"]!)
    }

    /// - Parameters:
    ///   - tls: Serve HTTPS with these options, or plain HTTP when nil.
    ///   - policy: The page's Content-Security-Policy.
    ///   - loopbackOnly: Accept connections from this Mac only.
    ///   - port: 0 picks any free port (see `start(ready:)`).
    public init(port: UInt16, tls: NWProtocolTLS.Options?, assets: [String: Asset], policy: String,
                loopbackOnly: Bool = false, queue: DispatchQueue) throws {
        let parameters = tls.map { NWParameters(tls: $0) } ?? .tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener.make(parameters, port: port, loopbackOnly: loopbackOnly)
        self.assets = assets
        self.policy = policy
        self.queue = queue
    }

    /// Starts listening; `ready` receives the port once it's open.
    public func start(ready: ((UInt16) -> Void)? = nil) {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.watch("web server", ready: ready)
        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
    }

    /// Replaces one file, e.g. when the Mac's Tailscale address becomes known.
    /// Call on the server's queue.
    func setAsset(_ asset: Asset, at path: String) {
        assets[path] = asset
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, buffer: Data())
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if error != nil || buffer.count > 16_384 {
                connection.cancel()
            } else if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(connection, head: String(decoding: buffer[..<end.lowerBound], as: UTF8.self))
            } else if done {
                connection.cancel()
            } else {
                self.read(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        let parts = head.split(separator: "\r\n", maxSplits: 1).first?.split(separator: " ") ?? []
        guard parts.count == 3 else { return send(connection, status: "400 Bad Request") }
        let method = parts[0]
        guard method == "GET" || method == "HEAD" else { return send(connection, status: "405 Method Not Allowed") }

        var path = String(parts[1].split(separator: "?", maxSplits: 1).first ?? "/")
        if path == "/" { path = "/index.html" }
        guard let asset = assets[path] else { return send(connection, status: "404 Not Found") }
        send(connection, status: "200 OK", asset: asset, includeBody: method == "GET")
    }

    private func send(_ connection: NWConnection, status: String, asset: Asset? = nil, includeBody: Bool = true) {
        let body = asset?.body ?? Data(status.utf8)
        let headers = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(asset?.type ?? "text/plain; charset=utf-8")",
            "Content-Length: \(body.count)",
            "Cache-Control: no-cache",
            "X-Content-Type-Options: nosniff",
            "X-Frame-Options: DENY",
            "Referrer-Policy: no-referrer",
            "Content-Security-Policy: \(policy)",
            "Connection: close",
        ].joined(separator: "\r\n") + "\r\n\r\n"

        var response = Data(headers.utf8)
        if includeBody { response.append(body) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

extension NWListener {
    /// A listener on every interface, or only on 127.0.0.1. Port 0 means any free port.
    static func make(_ parameters: NWParameters, port: UInt16, loopbackOnly: Bool) throws -> NWListener {
        let port = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: port)!
        guard loopbackOnly else { return try NWListener(using: parameters, on: port) }
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        return try NWListener(using: parameters)
    }

    /// Reports the port once listening, and turns failures into a clear
    /// message (most often: another copy of Tactile already has the port).
    func watch(_ what: String, ready: ((UInt16) -> Void)? = nil) {
        stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.port?.rawValue { ready?(port) }
            case .failed(let error):
                let busy = if case .posix(.EADDRINUSE) = error { true } else { false }
                Fatal.report(busy
                    ? "Port \(self?.port.map { "\($0)" } ?? "?") is already in use. Is Tactile already running?"
                    : "The \(what) couldn't start: \(error)")
            default:
                break
            }
        }
    }
}
