import AppKit
import CoreImage
import SwiftUI
import TactileCore

/// The "Pair an iPad" window: a QR code to scan, the code to type, and the
/// addresses to open. It follows the live pairing code.
final class PairingWindowController {
    final class Model: ObservableObject {
        @Published var state: TactileService.Snapshot?
    }

    private let model = Model()
    private var window: NSWindow?

    func update(_ state: TactileService.Snapshot) {
        model.state = state
    }

    func show(_ state: TactileService.Snapshot) {
        model.state = state
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PairingView(model: model)))
            window.title = "Pair a Device"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    struct PairingView: View {
        @ObservedObject var model: Model

        var body: some View {
            if let state = model.state {
                content(state)
            }
        }

        private func content(_ state: TactileService.Snapshot) -> some View {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Pair a Device")
                        .font(.title2.weight(.semibold))
                    Text("Scan with the iPad's Camera. Tactile opens and pairs on its own.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                QRImage(text: state.pairingLink)
                    .frame(width: 200, height: 200)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("Pairing QR code")

                VStack(spacing: 2) {
                    Text("Or enter this code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(state.code.prefix(3)) \(state.code.suffix(3))")
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Each code works once.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                VStack(spacing: 0) {
                    if let tailscale = state.tailscaleURL {
                        LinkRow(title: "With Tailscale (no setup)", url: tailscale)
                        Divider().padding(.leading, 14)
                    }
                    LinkRow(title: "On this Wi-Fi", url: state.setupURLs.first ?? "")
                }
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Certificate SHA-256\n\(state.fingerprint)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 24)
            .frame(width: 400)
        }
    }

    private struct LinkRow: View {
        let title: String
        let url: String

        var body: some View {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(url)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button("Copy") { Mac.copy(url) }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private struct QRImage: View {
        let text: String

        var body: some View {
            if let image = Self.render(text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            }
        }

        private static func render(_ text: String) -> NSImage? {
            guard let qr = QRCode.image(for: text),
                  let cgImage = CIContext().createCGImage(qr, from: qr.extent.integral) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }
}
