import ApplicationServices

public enum MouseButton: String, Sendable {
    case left = "l"
    case right = "r"
}

/// Media keys and system shortcuts the iPad can trigger directly.
public enum SystemAction: String, CaseIterable, Sendable {
    case volumeUp, volumeDown, mute
    case brightnessUp, brightnessDown
    case playPause, next, previous
    case missionControl, appExpose, spaceLeft, spaceRight
    case spotlight, lockScreen
}

/// Where a connected device's input goes. `InputSession` posts real events;
/// `LoggingInput` (dry run) and test recorders implement it too.
public protocol InputTarget: AnyObject {
    func keyDown(_ code: String, isRepeat: Bool)
    func keyUp(_ code: String)
    func move(dx: Double, dy: Double)
    func button(_ button: MouseButton, down: Bool)
    func scroll(dx: Double, dy: Double)
    func system(_ action: SystemAction)
    func type(_ text: String)
    func releaseAll()
}

extension InputTarget {
    /// A keyboard shortcut in one go, e.g. ["MetaLeft", "KeyC"]: keys go down
    /// in order and come up in reverse, so modifiers apply to the last key.
    public func combo(_ codes: [String]) {
        codes.forEach { keyDown($0, isRepeat: false) }
        codes.reversed().forEach { keyUp($0) }
    }
}

public enum Accessibility {
    /// Whether macOS lets Tactile post input. With `prompt`, macOS asks the
    /// user (once) and adds Tactile to Privacy & Security → Accessibility.
    public static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }
}

/// Stand-in used with --dry-run: prints what would have been sent.
public final class LoggingInput: InputTarget {
    public init() {}
    public func keyDown(_ code: String, isRepeat: Bool) { Log.input("key down \(code)\(isRepeat ? " (repeat)" : "")") }
    public func keyUp(_ code: String) { Log.input("key up   \(code)") }
    public func move(dx: Double, dy: Double) { Log.input(String(format: "move %.1f, %.1f", dx, dy)) }
    public func button(_ button: MouseButton, down: Bool) { Log.input("\(button) button \(down ? "down" : "up")") }
    public func scroll(dx: Double, dy: Double) { Log.input(String(format: "scroll %.0f, %.0f", dx, dy)) }
    public func system(_ action: SystemAction) { Log.input("system \(action.rawValue)") }
    public func type(_ text: String) { Log.input("type \"\(text)\"") }
    public func releaseAll() { Log.input("release all") }
}
