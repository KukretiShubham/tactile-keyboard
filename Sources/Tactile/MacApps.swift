import AppKit
import TactileCore

/// Brings an installed app to the front, opening it if it isn't running, when
/// its hotkey tab is tapped on the iPad.
enum AppFocus {
    /// With `window`, the app's frontmost window whose title includes it comes
    /// first: terminals show the running program (e.g. "codex") in the title.
    /// Call on the main thread.
    static func bring(_ id: String, window hint: String? = nil) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            if let error { Log.warn("Couldn't bring \(id) to the front: \(error.localizedDescription)") }
            guard let app, let hint else { return }
            DispatchQueue.main.async { raiseWindow(of: app, titled: hint) }
        }
    }

    /// Raises the app's first window (front to back) whose title includes
    /// `hint`, using Accessibility, which Tactile already has for typing.
    @discardableResult
    private static func raiseWindow(of app: NSRunningApplication, titled hint: String) -> Bool {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }
        for window in windows {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            guard let title = title as? String, title.range(of: hint, options: .caseInsensitive) != nil else { continue }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            return true
        }
        return false
    }
}

/// Icons of apps installed on this Mac, for the iPad's hotkey tabs. Tactile
/// ships no other company's logos: each icon comes from the app itself.
enum AppIcons {
    private static var cache: [String: String] = [:]

    /// PNG data URLs for the apps among `ids` (bundle IDs) that are installed.
    /// Call on the main thread.
    static func dataURLs(for ids: [String]) -> [String: String] {
        var found: [String: String] = [:]
        for id in ids {
            if let cached = cache[id] {
                found[id] = cached
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                      let png = png(NSWorkspace.shared.icon(forFile: url.path), pixels: 96) {
                let dataURL = "data:image/png;base64," + png.base64EncodedString()
                cache[id] = dataURL
                found[id] = dataURL
            }
        }
        return found
    }

    private static func png(_ image: NSImage, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
