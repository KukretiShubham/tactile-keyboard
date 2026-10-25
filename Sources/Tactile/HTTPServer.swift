import Foundation
import Network

/// Serves the iPad web app. Every file is loaded into memory at launch,
/// so requests can only ever reach files that ship with the app.
final class HTTPServer {
    private struct Asset {
        let body: Data
        let type: String
    }

    private let listener: NWListener
    private let queue: DispatchQueue
    private var assets: [String: Asset] = [:]

    private static let types = [
        "html": "text/html; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "json": "application/json",
        "webmanifest": "application/manifest+json",
        "svg": "image/svg+xml",
        "png": "image/png",
    ]

    init(port: UInt16, socketPort: UInt16, webRoot: URL, queue: DispatchQueue) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.queue = queue

        let files = FileManager.default.enumerator(at: webRoot, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard let type = Self.types[url.pathExtension], let body = try? Data(contentsOf: url) else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(webRoot.standardizedFileURL.path.count))
            assets[path] = Asset(body: body, type: type)
        }
        let config = try JSONSerialization.data(withJSONObject: ["socketPort": Int(socketPort)])
        assets["/config.json"] = Asset(body: config, type: Self.types["json"]!)
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                fputs("Web server failed: \(error)\n", stderr)
                exit(1)
            }
        }
        listener.start(queue: queue)
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
            "Content-Security-Policy: default-src 'self'; connect-src 'self' ws:; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'",
            "Connection: close",
        ].joined(separator: "\r\n") + "\r\n\r\n"

        var response = Data(headers.utf8)
        if includeBody { response.append(body) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
