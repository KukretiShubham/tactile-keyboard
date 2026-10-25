import AppKit
import TactileCore
import WebKit

/// Runs the web app's tests (Tests/Web) in a WebKit view, served the same way
/// Tactile serves the page to the iPad, and reports each one here.
enum WebChecks {
    private static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func run(_ checks: Checks) {
        do {
            for result in try results() {
                checks.record("web: \(result.name)", passed: result.passed, message: result.message ?? "")
            }
        } catch {
            checks.record("web: tests ran", passed: false, message: "\(error)")
        }
    }

    private struct Result: Decodable {
        let name: String
        let passed: Bool
        let message: String?
    }

    private static func results() throws -> [Result] {
        var assets = HTTPServer.loadAssets(from: projectRoot.appendingPathComponent("Sources/Tactile/Web"), mount: "/Sources/Tactile/Web")
        assets.merge(HTTPServer.loadAssets(from: projectRoot.appendingPathComponent("Tests/Web"), mount: "/Tests/Web")) { $1 }
        // The test page runs its tests from an inline script.
        let policy = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
        let server = try HTTPServer(port: 0, tls: nil, assets: assets, policy: policy, loopbackOnly: true,
                                    queue: DispatchQueue(label: "tactile.checks.web"))
        defer { server.stop() }
        let port = try require(waitFor { server.start(ready: $0) }, "port")

        _ = NSApplication.shared
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900))
        view.load(URLRequest(url: try require(URL(string: "http://127.0.0.1:\(port)/Tests/Web/index.html"), "URL")))

        var json: String?
        waitUntil(timeout: 90) {
            if json == nil {
                view.evaluateJavaScript("window.__results ? JSON.stringify(window.__results) : ''") { value, _ in
                    if let text = value as? String, !text.isEmpty { json = text }
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            }
            return json != nil
        }
        let data = Data(try require(json, "web test results (did the page load?)").utf8)
        return try JSONDecoder().decode([Result].self, from: data)
    }
}
