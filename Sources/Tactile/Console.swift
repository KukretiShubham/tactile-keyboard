import CoreImage
import Darwin
import Foundation
import SystemConfiguration

enum Log {
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func info(_ message: String) { print("\(clock.string(from: Date()))  \(message)") }
    static func warn(_ message: String) { print("\u{1B}[33m⚠︎ \(message)\u{1B}[0m") }
    static func input(_ message: String) { print("\u{1B}[2m\(clock.string(from: Date()))  \(message)\u{1B}[0m") }
}

enum HostInfo {
    static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }

    static var bonjourName: String? {
        (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" }
    }

    /// IPv4 addresses on active interfaces, Wi-Fi/Ethernet first.
    static var ipv4Addresses: [String] {
        var found: [(name: String, address: String)] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            found.append((String(cString: entry.pointee.ifa_name), String(decoding: bytes, as: UTF8.self)))
        }
        return found.sorted { $0.name.hasPrefix("en") && !$1.name.hasPrefix("en") }.map(\.address)
    }

    /// This Mac's tailnet name, when Tactile has a Tailscale certificate for it.
    static var tailscaleName: String?

    static var reachableHosts: Set<String> {
        var hosts: Set<String> = ["localhost", "127.0.0.1"]
        hosts.formUnion(ipv4Addresses)
        if let name = bonjourName { hosts.insert(name.lowercased()) }
        if let name = tailscaleName { hosts.insert(name.lowercased()) }
        return hosts
    }
}

enum Banner {
    static func show(setupPort: UInt16, appPort: UInt16, tailscaleURL: String?, code: String, fingerprint: String, dryRun: Bool) {
        let hosts = [HostInfo.bonjourName].compactMap { $0 } + HostInfo.ipv4Addresses
        let host = hosts.first ?? "localhost"
        let setupURL = "http://\(host):\(setupPort)"
        let spacedCode = "\(code.prefix(3)) \(code.suffix(3))"
        let bold = "\u{1B}[1m", dim = "\u{1B}[2m", reset = "\u{1B}[0m"

        print("")
        print("  \(bold)Tactile is running\(reset) 🔒\(dryRun ? "  \(dim)(dry run — input is only logged)\(reset)" : "")")
        print("")
        // Scanning pairs too: the code rides after "#", which never leaves the iPad.
        qrLines(for: "\(setupURL)/#pair=\(code)").forEach { print("  \($0)") }
        print("")
        if let tailscaleURL {
            print("  With Tailscale      \(bold)\(tailscaleURL)\(reset)")
            print("  \(dim)(iPads running Tailscale open this directly — no certificate setup)\(reset)")
            print("")
        }
        print("  Open on your iPad   \(bold)\(setupURL)\(reset)")
        hosts.dropFirst().forEach { print("                      http://\($0):\(setupPort)") }
        print(tailscaleURL == nil
              ? "  \(dim)(It installs this Mac's certificate once, then opens https://\(host):\(appPort))\(reset)"
              : "  \(dim)(Goes to Tailscale when it can; otherwise sets up this Mac's certificate once)\(reset)")
        print("  Pairing code        \(bold)\(spacedCode)\(reset)")
        print("")
        print("  Certificate SHA-256 \(fingerprint.prefix(47))")
        print("                      \(fingerprint.dropFirst(48))")
        print("  \(dim)Check it matches the one on the iPad's setup page before trusting it.\(reset)")
        print("")
        print("  \(dim)Tip: open the secure page, then Share → Add to Home Screen for full screen.\(reset)")
        print("  \(dim)Press Ctrl-C to stop.\(reset)")
        print("")
    }

    /// Renders a QR code with half-block characters, two modules per line.
    private static func qrLines(for text: String) -> [String] {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return [] }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else { return [] }

        let extent = image.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        CIContext().render(image, toBitmap: &pixels, rowBytes: width * 4, bounds: extent,
                           format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        func dark(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return pixels[(y * width + x) * 4] < 128
        }

        let margin = 1
        var lines: [String] = []
        for y in stride(from: -margin, to: height + margin, by: 2) {
            var line = "\u{1B}[30;107m"
            for x in -margin..<(width + margin) {
                switch (dark(x, y), dark(x, y + 1)) {
                case (true, true): line += "█"
                case (true, false): line += "▀"
                case (false, true): line += "▄"
                case (false, false): line += " "
                }
            }
            lines.append(line + "\u{1B}[0m")
        }
        return lines
    }
}
