import CoreGraphics

/// Maps W3C `KeyboardEvent.code` names to macOS virtual key codes (ANSI layout).
public enum KeyMap {
    public static let codes: [String: CGKeyCode] = [
        "KeyA": 0x00, "KeyS": 0x01, "KeyD": 0x02, "KeyF": 0x03, "KeyH": 0x04, "KeyG": 0x05,
        "KeyZ": 0x06, "KeyX": 0x07, "KeyC": 0x08, "KeyV": 0x09, "KeyB": 0x0B, "KeyQ": 0x0C,
        "KeyW": 0x0D, "KeyE": 0x0E, "KeyR": 0x0F, "KeyY": 0x10, "KeyT": 0x11, "KeyO": 0x1F,
        "KeyU": 0x20, "KeyI": 0x22, "KeyP": 0x23, "KeyL": 0x25, "KeyJ": 0x26, "KeyK": 0x28,
        "KeyN": 0x2D, "KeyM": 0x2E,

        "Digit1": 0x12, "Digit2": 0x13, "Digit3": 0x14, "Digit4": 0x15, "Digit5": 0x17,
        "Digit6": 0x16, "Digit7": 0x1A, "Digit8": 0x1C, "Digit9": 0x19, "Digit0": 0x1D,

        "Equal": 0x18, "Minus": 0x1B, "BracketRight": 0x1E, "BracketLeft": 0x21, "Quote": 0x27,
        "Semicolon": 0x29, "Backslash": 0x2A, "Comma": 0x2B, "Slash": 0x2C, "Period": 0x2F,
        "Backquote": 0x32, "IntlBackslash": 0x0A,

        "Enter": 0x24, "Tab": 0x30, "Space": 0x31, "Backspace": 0x33, "Escape": 0x35,
        "Delete": 0x75, "Home": 0x73, "End": 0x77, "PageUp": 0x74, "PageDown": 0x79,
        "ArrowLeft": 0x7B, "ArrowRight": 0x7C, "ArrowDown": 0x7D, "ArrowUp": 0x7E,

        "MetaLeft": 0x37, "MetaRight": 0x36, "ShiftLeft": 0x38, "ShiftRight": 0x3C,
        "AltLeft": 0x3A, "AltRight": 0x3D, "ControlLeft": 0x3B, "ControlRight": 0x3E,

        "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76, "F5": 0x60, "F6": 0x61,
        "F7": 0x62, "F8": 0x64, "F9": 0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
    ]

    /// Keys that type a character, whose labels follow the Mac's keyboard layout.
    public static var characterKeys: [String] {
        codes.keys.filter { $0.hasPrefix("Key") || $0.hasPrefix("Digit") || punctuation.contains($0) }.sorted()
    }

    private static let punctuation: Set = ["Equal", "Minus", "BracketRight", "BracketLeft", "Quote", "Semicolon",
                                           "Backslash", "Comma", "Slash", "Period", "Backquote", "IntlBackslash"]

    static let modifierFlags: [CGKeyCode: CGEventFlags] = [
        0x37: .maskCommand, 0x36: .maskCommand,
        0x38: .maskShift, 0x3C: .maskShift,
        0x3A: .maskAlternate, 0x3D: .maskAlternate,
        0x3B: .maskControl, 0x3E: .maskControl,
    ]

    /// Keys a hardware Mac keyboard reports with the fn (and keypad) flag set.
    static let arrowKeys: Set<CGKeyCode> = [0x7B, 0x7C, 0x7D, 0x7E]
    static let navigationKeys: Set<CGKeyCode> = [0x75, 0x73, 0x77, 0x74, 0x79]

    static let returnKey: CGKeyCode = 0x24
    static let space: CGKeyCode = 0x31
    static let q: CGKeyCode = 0x0C
    static let left: CGKeyCode = 0x7B
    static let right: CGKeyCode = 0x7C
    static let down: CGKeyCode = 0x7D
    static let up: CGKeyCode = 0x7E
}
