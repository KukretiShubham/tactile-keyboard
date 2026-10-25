import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let arguments = CommandLine.arguments

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    Tactile — use an iPad as a keyboard and trackpad for this Mac.

    Usage: tactile [--port 8420] [--dry-run] [--forget-devices]

      --port N           Setup page port. The app uses N + 1 (HTTPS) and
                         N + 2 (secure WebSocket). Default 8420.
      --dry-run          Log input instead of controlling the Mac.
      --forget-devices   Remove every paired iPad and exit.
    """)
    exit(0)
}

if arguments.contains("--forget-devices") {
    Pairing.forgetAll()
    print("All paired devices were removed.")
    exit(0)
}

let setupPort = option("--port").flatMap(UInt16.init) ?? 8420
let appPort = setupPort + 1
let socketPort = setupPort + 2
let dryRun = arguments.contains("--dry-run")
let queue = DispatchQueue(label: "tactile.server")

guard let webRoot = Bundle.module.url(forResource: "Web", withExtension: nil) else {
    fputs("Web resources are missing from the build.\n", stderr)
    exit(1)
}

if !dryRun && !Accessibility.isTrusted(prompt: true) {
    Log.warn("""
    Accessibility access is off, so input can't reach other apps yet.
      Open System Settings → Privacy & Security → Accessibility and allow the app
      you launched Tactile from (for example Terminal), then restart Tactile.
    """)
}

let pairing = Pairing()

let tls: TLSIdentity = {
    do {
        return try TLSIdentity.prepare(hostName: HostInfo.bonjourName, addresses: HostInfo.ipv4Addresses)
    } catch {
        fputs("Could not create the HTTPS certificate: \(error)\n", stderr)
        exit(1)
    }
}()

// The app is only served over HTTPS. Plain HTTP serves just the one-time setup
// page that lets the iPad install and trust this Mac's certificate.
let assets = HTTPServer.loadAssets(from: webRoot)
var appAssets = assets.filter { !$0.key.hasPrefix("/setup/") }
appAssets["/config.json"] = HTTPServer.json(["socketPort": Int(socketPort)])
var setupAssets = assets.filter { $0.key.hasPrefix("/setup/") || $0.key == "/icon.svg" || $0.key == "/apple-touch-icon.png" }
setupAssets["/index.html"] = assets["/setup/index.html"]
setupAssets["/setup.json"] = HTTPServer.json(["appPort": Int(appPort), "fingerprint": tls.fingerprint, "caName": tls.caName])
setupAssets["/tactile-ca.crt"] = HTTPServer.Asset(body: tls.caDER, type: "application/x-x509-ca-cert")

let basePolicy = "default-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'"

let servers: (HTTPServer, HTTPServer, SocketServer) = {
    do {
        let setup = try HTTPServer(port: setupPort, tls: nil, assets: setupAssets,
                                   policy: "\(basePolicy); connect-src 'self' https:", queue: queue)
        let app = try HTTPServer(port: appPort, tls: tls.options(), assets: appAssets,
                                 policy: "\(basePolicy); connect-src 'self' wss:", queue: queue)
        let socket = try SocketServer(port: socketPort, appPort: appPort, tls: tls.options(), pairing: pairing, queue: queue) {
            dryRun ? LoggingInput() as InputTarget : InputSession()
        }
        return (setup, app, socket)
    } catch {
        fputs("Could not start Tactile: \(error)\n", stderr)
        exit(1)
    }
}()

servers.0.start()
servers.1.start()
servers.2.start()
Banner.show(setupPort: setupPort, appPort: appPort, code: pairing.code, fingerprint: tls.fingerprint, dryRun: dryRun)

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let stopSources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
    let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
    source.setEventHandler {
        servers.2.stop()
        print("\nTactile stopped.")
        exit(0)
    }
    source.resume()
    return source
}

dispatchMain()
