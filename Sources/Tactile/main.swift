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

    Usage: tactile [--port 8420] [--dry-run] [--no-tailscale] [--forget-devices]

      --port N           Setup page port. The app uses N + 1 and N + 2 with this
                         Mac's local certificate, and N + 3 and N + 4 with its
                         Tailscale certificate. Default 8420.
      --dry-run          Log input instead of controlling the Mac.
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

let setupPort = option("--port").flatMap(UInt16.init) ?? 8420
let localPorts = (app: setupPort + 1, socket: setupPort + 2)
let tailscalePorts = (app: setupPort + 3, socket: setupPort + 4)
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

// Two ways to get a certificate the iPad trusts:
//  - Tailscale: a real Let's Encrypt certificate for this Mac's tailnet name.
//    iPads running Tailscale need no setup at all.
//  - Local: this Mac's own certificate authority, which other iPads trust once.
let local: LocalAuthority = {
    do {
        return try LocalAuthority.prepare(hostName: HostInfo.bonjourName, addresses: HostInfo.ipv4Addresses)
    } catch {
        fputs("Could not create the HTTPS certificate: \(error)\n", stderr)
        exit(1)
    }
}()
let tailscale = arguments.contains("--no-tailscale") ? nil : Tailscale.certificate()
HostInfo.tailscaleName = tailscale?.host
let tailscaleURL = tailscale.map { "https://\($0.host):\(tailscalePorts.app)/" }

// The app is only served over HTTPS. Plain HTTP serves just the setup page,
// which sends the iPad to whichever secure address it can use.
let assets = HTTPServer.loadAssets(from: webRoot)
let appAssets = assets.filter { !$0.key.hasPrefix("/setup/") }
var setupAssets = assets.filter { $0.key.hasPrefix("/setup/") || $0.key == "/icon.svg" || $0.key == "/apple-touch-icon.png" }
setupAssets["/index.html"] = assets["/setup/index.html"]
var setupInfo: [String: Any] = ["appPort": Int(localPorts.app), "fingerprint": local.fingerprint, "caName": local.caName]
if let tailscaleURL { setupInfo["tailscaleURL"] = tailscaleURL }
setupAssets["/setup.json"] = HTTPServer.json(setupInfo)
setupAssets["/tactile-ca.crt"] = HTTPServer.Asset(body: local.caDER, type: "application/x-x509-ca-cert")

let basePolicy = "default-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'"
let makeInput = { dryRun ? LoggingInput() as InputTarget : InputSession() }

/// The keyboard page and its socket, served with one certificate.
func secureApp(_ identity: TLSIdentity, ports: (app: UInt16, socket: UInt16)) throws -> (HTTPServer, SocketServer) {
    var pageAssets = appAssets
    pageAssets["/config.json"] = HTTPServer.json(["socketPort": Int(ports.socket)])
    let page = try HTTPServer(port: ports.app, tls: identity.options(), assets: pageAssets,
                              policy: "\(basePolicy); connect-src 'self' wss:", queue: queue)
    let socket = try SocketServer(port: ports.socket, appPort: ports.app, tls: identity.options(),
                                  pairing: pairing, queue: queue, makeInput: makeInput)
    return (page, socket)
}

let servers: (pages: [HTTPServer], sockets: [SocketServer]) = {
    do {
        let setup = try HTTPServer(port: setupPort, tls: nil, assets: setupAssets,
                                   policy: "\(basePolicy); connect-src 'self' https:", queue: queue)
        var apps = [try secureApp(local.identity, ports: localPorts)]
        if let tailscale { apps.append(try secureApp(tailscale.identity, ports: tailscalePorts)) }
        return ([setup] + apps.map(\.0), apps.map(\.1))
    } catch {
        fputs("Could not start Tactile: \(error)\n", stderr)
        exit(1)
    }
}()

servers.pages.forEach { $0.start() }
servers.sockets.forEach { $0.start() }
Banner.show(setupPort: setupPort, appPort: localPorts.app, tailscaleURL: tailscaleURL,
            code: pairing.code, fingerprint: local.fingerprint, dryRun: dryRun)

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let stopSources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
    let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
    source.setEventHandler {
        servers.sockets.forEach { $0.stop() }
        print("\nTactile stopped.")
        exit(0)
    }
    source.resume()
    return source
}

dispatchMain()
