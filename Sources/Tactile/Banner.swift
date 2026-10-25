import AppKit
import CoreImage
import TactileCore

enum QRCode {
    /// A QR code with one pixel per module; scale it up without smoothing.
    static func image(for text: String) -> CIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        return filter.outputImage
    }
}

/// Small AppKit helpers shared by the menu bar and the pairing window.
enum Mac {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func showLog() {
        NSWorkspace.shared.open(Paths.logFile)
    }
}

/// What Terminal shows when Tactile runs outside the menu bar app.
enum Banner {
    static func show(_ state: TactileService.Snapshot) {
        let bold = "\u{1B}[1m", dim = "\u{1B}[2m", reset = "\u{1B}[0m"
        let spacedCode = "\(state.code.prefix(3)) \(state.code.suffix(3))"

        print("")
        print("  \(bold)Tactile is running\(reset) 🔒\(state.dryRun ? "  \(dim)(dry run — input is only logged)\(reset)" : "")")
        print("")
        // Scanning pairs too: the code rides after "#", which never leaves the iPad.
        qrLines(for: state.pairingLink).forEach { print("  \($0)") }
        print("")
        if let tailscaleURL = state.tailscaleURL {
            print("  With Tailscale      \(bold)\(tailscaleURL)\(reset)")
            print("  \(dim)(iPads running Tailscale open this directly — no certificate setup)\(reset)")
            print("")
        }
        print("  Open on your iPad   \(bold)\(state.setupURLs.first ?? "")\(reset)")
        state.setupURLs.dropFirst().forEach { print("                      \($0)") }
        print(state.tailscaleURL == nil
              ? "  \(dim)(It installs this Mac's certificate once, then opens \(state.localURL))\(reset)"
              : "  \(dim)(Goes to Tailscale when it can; otherwise sets up this Mac's certificate once)\(reset)")
        print("  Pairing code        \(bold)\(spacedCode)\(reset)")
        print("")
        print("  Certificate SHA-256 \(state.fingerprint.prefix(47))")
        print("                      \(state.fingerprint.dropFirst(48))")
        print("  \(dim)Check it matches the one on the iPad's setup page before trusting it.\(reset)")
        print("")
        print("  \(dim)Tip: open the secure page, then Share → Add to Home Screen for full screen.\(reset)")
        print("  \(dim)Press Ctrl-C to stop.\(reset)")
        print("")
    }

    /// Renders a QR code with half-block characters, two modules per line.
    private static func qrLines(for text: String) -> [String] {
        guard let image = QRCode.image(for: text) else { return [] }

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
