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

      --port N           Web page port (the socket uses N + 1). Default 8420.
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

let httpPort = option("--port").flatMap(UInt16.init) ?? 8420
let socketPort = httpPort + 1
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

let servers: (HTTPServer, SocketServer) = {
    do {
        let http = try HTTPServer(port: httpPort, socketPort: socketPort, webRoot: webRoot, queue: queue)
        let socket = try SocketServer(port: socketPort, httpPort: httpPort, pairing: pairing, queue: queue) {
            dryRun ? LoggingInput() as InputTarget : InputSession()
        }
        return (http, socket)
    } catch {
        fputs("Could not start Tactile: \(error)\n", stderr)
        exit(1)
    }
}()

servers.0.start()
servers.1.start()
Banner.show(port: httpPort, code: pairing.code, dryRun: dryRun)

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let stopSources = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
    let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
    source.setEventHandler {
        servers.1.stop()
        print("\nTactile stopped.")
        exit(0)
    }
    source.resume()
    return source
}

dispatchMain()
