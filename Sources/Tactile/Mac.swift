import AppKit
import TactileCore

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
