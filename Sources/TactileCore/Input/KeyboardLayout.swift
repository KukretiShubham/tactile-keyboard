import Carbon.HIToolbox
import Foundation

/// What each key types on the Mac's current keyboard layout, so the iPad's
/// key labels can match it (for example AZERTY, or a non-Latin layout).
/// Keys stay physical positions either way; only their labels change.
public enum KeyboardLayout {
    /// Unshifted and shifted characters per key code, e.g. "KeyQ": ["a", "A"]
    /// on AZERTY. Keys that type nothing printable are left out.
    /// Text Input Sources must be read on the main thread.
    public static func currentLabels() -> [String: [String]] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> [String: [String]] in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return [:] }
            var labels: [String: [String]] = [:]
            for code in KeyMap.characterKeys {
                guard let keyCode = KeyMap.codes[code] else { continue }
                let base = character(layout, keyCode, shifted: false)
                guard !base.isEmpty else { continue }
                labels[code] = [base, character(layout, keyCode, shifted: true)]
            }
            return labels
        }
    }

    private static func character(_ layout: UnsafePointer<UCKeyboardLayout>, _ keyCode: CGKeyCode, shifted: Bool) -> String {
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let modifiers = shifted ? UInt32(shiftKey >> 8) & 0xFF : 0
        let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), modifiers,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeys, characters.count, &length, &characters)
        guard status == noErr else { return "" }
        let text = String(utf16CodeUnits: characters, count: length)
        // Control characters and whitespace make no sense as a label.
        return text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespaces.contains($0) }
            ? text : ""
    }
}
