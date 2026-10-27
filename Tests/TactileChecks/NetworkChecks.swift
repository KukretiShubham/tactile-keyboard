import Foundation
import TactileCore

enum NetworkChecks {
    private static let queue = DispatchQueue(label: "tactile.checks.server")

    static func run(_ checks: Checks) {
        checks.run("web server: serves only its own files, with security headers") {
            let assets = [
                "/index.html": HTTPServer.Asset(body: Data("<p>hi</p>".utf8), type: "text/html"),
                "/app.js": HTTPServer.Asset(body: Data("1".utf8), type: "text/javascript"),
            ]
            let server = try HTTPServer(port: 0, tls: nil, assets: assets, policy: "default-src 'self'",
                                        loopbackOnly: true, queue: queue)
            defer { server.stop() }
            let port = try require(waitFor { server.start(ready: $0) }, "port")

            let page = try require(fetch(port, "/"), "response for /")
            try expectEqual(page.status, 200, "status for /")
            try expectEqual(page.body, "<p>hi</p>", "body for /")
            try expectEqual(page.headers["Content-Security-Policy"], "default-src 'self'", "CSP header")
            try expectEqual(page.headers["X-Content-Type-Options"], "nosniff", "nosniff header")
            try expectEqual(page.headers["X-Frame-Options"], "DENY", "frame header")

            try expectEqual(fetch(port, "/missing.js")?.status, 404, "status for a missing file")
            try expectEqual(fetch(port, "/../Package.swift")?.status, 404, "status for a path outside the assets")
            try expectEqual(fetch(port, "/app.js", method: "POST")?.status, 405, "status for POST")
        }

        checks.run("socket: a device pairs, then its input reaches the Mac") {
            try withTemporaryDirectory { folder in
                let pairing = Pairing(store: folder.appendingPathComponent("devices.json"))
                let input = RecordingInput()
                let server = try SocketServer(port: 0, appPort: 1, tls: nil, loopbackOnly: true, route: "Test",
                                              pairing: pairing, queue: queue, makeInput: { input })
                let focused = NSLock()
                var focusRequests: [String] = []
                server.onFocusApp = { id, hint in focused.withLock { focusRequests.append(hint.map { "\(id) \($0)" } ?? id) } }
                defer { queue.sync { server.stop() } }
                let port = try require(waitFor { server.start(ready: $0) }, "port")

                // Input before pairing closes the connection.
                let early = try Socket(port: port)
                early.send(["t": "kd", "k": "KeyA"])
                try expect(early.receive() == nil, "connection closed")

                let socket = try Socket(port: port)
                socket.send(["t": "hello"])
                try expectEqual(socket.receive()?["t"] as? String, "pair", "reply to an unknown device")

                socket.send(["t": "pair", "code": queue.sync { pairing.code } == "000000" ? "111111" : "000000"])
                try expectEqual(socket.receive()?["reason"] as? String, "code", "reply to a wrong code")

                socket.send(["t": "pair", "code": queue.sync { pairing.code }, "name": "iPad"])
                let ready = try require(socket.receive(), "reply to the right code")
                try expectEqual(ready["t"] as? String, "ready", "reply to the right code")
                let token = try require(ready["token"] as? String, "token")
                try expectEqual(input.typed, [], "input before pairing")

                socket.send(["t": "kd", "k": "KeyA"])
                socket.send(["t": "ku", "k": "KeyA"])
                socket.send(["t": "combo", "ks": ["MetaLeft", "KeyC"]])
                socket.send(["t": "combo", "ks": ["MetaLeft", "NotAKey"]])
                socket.send(["t": "sys", "k": "missionControl"])
                socket.send(["t": "sys", "k": "formatDisk"])
                socket.send(["t": "focus", "k": "com.example.Editor"])
                socket.send(["t": "focus", "k": "com.example.Terminal", "s": "codex"])
                socket.send(["t": "focus", "k": "com.example.Terminal", "s": "$(rm -rf ~)"])
                socket.send(["t": "focus", "k": "../../etc/passwd"])
                socket.send(["t": "ping"])
                try expectEqual(socket.receive()?["t"] as? String, "pong", "reply to ping")
                try expectEqual(focused.withLock { focusRequests },
                                ["com.example.Editor", "com.example.Terminal codex", "com.example.Terminal"],
                                "apps asked to come to the front (odd window hints dropped)")
                try expectEqual(input.typed, ["down KeyA", "up KeyA", "down MetaLeft", "down KeyC", "up KeyC", "up MetaLeft",
                                               "system missionControl"], "input")

                // The saved token connects again without pairing.
                let again = try Socket(port: port)
                again.send(["t": "hello", "token": token])
                let welcome = try require(again.receive(), "reply to a saved token")
                try expectEqual(welcome["t"] as? String, "ready", "reply to a saved token")
                try expect(welcome["token"] == nil, "no new token for a known device")

                // Revoked devices are cut off.
                let id = try require(queue.sync { pairing.devices.first?.id }, "device")
                queue.sync { pairing.revoke(id) }
                again.send(["t": "kd", "k": "KeyB"])
                try expect(again.receive() == nil, "connection closed after revoking")
                try expect(!input.typed.contains("down KeyB"), "input after revoking is ignored")
            }
        }

        checks.run("socket: oversized and unknown input is ignored") {
            try withTemporaryDirectory { folder in
                let device = try pairedDevice(folder)
                defer { queue.sync { device.server.stop() } }
                device.socket.send(["t": "txt", "s": String(repeating: "a", count: 4001)])
                device.socket.send(["t": "combo", "ks": ["MetaLeft", "ShiftLeft", "AltLeft", "ControlLeft", "KeyA", "KeyB"]])
                device.socket.send(["t": "combo", "ks": [String]()])
                device.socket.send(["t": "icons", "ks": Array(repeating: "com.example.App", count: 65)])
                device.socket.send(["t": "mv", "x": 1e9, "y": -1e9])
                device.socket.send(["t": "ping"])
                try expectEqual(device.socket.receive()?["t"] as? String, "pong", "still connected")
                try expectEqual(device.input.typed, ["move 800.0 -800.0"], "only the clamped move went through")
            }
        }

        checks.run("socket: input is ignored while paused, and held devices are refused") {
            try withTemporaryDirectory { folder in
                let paused = NSLock()
                var isPaused = true
                var heldIDs: Set<String> = []
                let device = try pairedDevice(folder) { server in
                    server.isPaused = { paused.withLock { isPaused } }
                    server.isHeld = { id in paused.withLock { heldIDs.contains(id) } }
                }
                defer { queue.sync { device.server.stop() } }
                device.socket.send(["t": "kd", "k": "KeyA"])
                device.socket.send(["t": "ping"])
                try expectEqual(device.socket.receive()?["t"] as? String, "pong", "pings still answered")
                try expectEqual(device.input.typed, [], "input while paused")
                paused.withLock { isPaused = false }
                device.socket.send(["t": "kd", "k": "KeyA"])
                device.socket.send(["t": "ping"])
                _ = device.socket.receive()
                try expectEqual(device.input.typed, ["down KeyA"], "input after resuming")

                // A device disconnected from the menu is turned away when it comes back.
                let id = try require(queue.sync { device.pairing.devices.first?.id }, "device")
                _ = paused.withLock { heldIDs.insert(id) }
                let again = try Socket(port: device.port)
                again.send(["t": "hello", "token": device.token])
                try expectEqual(again.receive()?["reason"] as? String, "held", "reply to a held device")
            }
        }

        checks.run("socket: pages from other sites can't connect") {
            try withTemporaryDirectory { folder in
                let pairing = Pairing(store: folder.appendingPathComponent("devices.json"))
                let server = try SocketServer(port: 0, appPort: 8443, tls: nil, loopbackOnly: true, route: "Test",
                                              pairing: pairing, queue: queue, makeInput: { RecordingInput() })
                defer { queue.sync { server.stop() } }
                let port = try require(waitFor { server.start(ready: $0) }, "port")
                let socket = try Socket(port: port, origin: "http://attacker.example:8443")
                socket.send(["t": "hello"])
                try expect(socket.receive() == nil, "a foreign origin got a reply")
                let anonymous = try Socket(port: port, origin: nil)
                anonymous.send(["t": "hello"])
                try expect(anonymous.receive() == nil, "a client naming no page got a reply")
            }
        }
    }

    // Pairs a device and returns its socket, the server and what it typed.
    private static func pairedDevice(_ folder: URL, configure: (SocketServer) -> Void = { _ in }) throws
        -> (socket: Socket, server: SocketServer, input: RecordingInput, pairing: Pairing, port: UInt16, token: String) {
        let pairing = Pairing(store: folder.appendingPathComponent("devices.json"))
        let input = RecordingInput()
        let server = try SocketServer(port: 0, appPort: 1, tls: nil, loopbackOnly: true, route: "Test",
                                      pairing: pairing, queue: queue, makeInput: { input })
        configure(server)
        let port = try require(waitFor { server.start(ready: $0) }, "port")
        let socket = try Socket(port: port)
        socket.send(["t": "pair", "code": queue.sync { pairing.code }, "name": "iPad"])
        let ready = try require(socket.receive(), "reply to pairing")
        try expectEqual(ready["t"] as? String, "ready", "paired")
        return (socket, server, input, pairing, port, try require(ready["token"] as? String, "token"))
    }

    private struct Response {
        let status: Int
        let headers: [String: String]
        let body: String
    }

    private static func fetch(_ port: UInt16, _ path: String, method: String = "GET") -> Response? {
        // URL(string:) would tidy "/../"; build the request line as given.
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.percentEncodedPath = path
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return waitFor { done in
            URLSession.shared.dataTask(with: request) { data, response, _ in
                guard let http = response as? HTTPURLResponse else { return done(Response(status: 0, headers: [:], body: "")) }
                let headers = (http.allHeaderFields as? [String: String]) ?? [:]
                done(Response(status: http.statusCode, headers: headers, body: String(decoding: data ?? Data(), as: UTF8.self)))
            }.resume()
        }
    }
}

/// A WebSocket client speaking JSON, like the iPad page.
private final class Socket {
    private let task: URLSessionWebSocketTask

    /// `origin` is the page asking, as a browser would say; nil sends none.
    init(port: UInt16, origin: String? = "http://127.0.0.1:1") throws {
        var request = URLRequest(url: try require(URL(string: "ws://127.0.0.1:\(port)"), "socket URL"))
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        task = URLSession.shared.webSocketTask(with: request)
        task.resume()
    }

    deinit { task.cancel(with: .goingAway, reason: nil) }

    func send(_ message: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
        task.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
    }

    /// The next message, or nil if the connection closed or nothing came.
    func receive(timeout: TimeInterval = 3) -> [String: Any]? {
        let result: [String: Any]?? = waitFor(timeout: timeout) { done in
            self.task.receive { result in
                guard case .success(.string(let text)) = result else { return done(nil) }
                done(try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            }
        }
        return result ?? nil
    }
}
