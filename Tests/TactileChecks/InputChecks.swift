import Foundation
import TactileCore

/// Records input instead of posting it.
final class RecordingInput: InputTarget {
    private let lock = NSLock()
    private var log: [String] = []

    var events: [String] { lock.withLock { log } }
    /// Events other than the "release everything" sent whenever a device disconnects.
    var typed: [String] { events.filter { $0 != "release" } }
    private func add(_ event: String) { lock.withLock { log.append(event) } }

    func keyDown(_ code: String, isRepeat: Bool) { add("down \(code)") }
    func keyUp(_ code: String) { add("up \(code)") }
    func move(dx: Double, dy: Double) { add("move \(dx) \(dy)") }
    func button(_ button: MouseButton, down: Bool) { add("\(button.rawValue) \(down ? "down" : "up")") }
    func scroll(dx: Double, dy: Double) { add("scroll \(dx) \(dy)") }
    func system(_ action: SystemAction) { add("system \(action.rawValue)") }
    func type(_ text: String) { add("type \(text)") }
    func releaseAll() { add("release") }
}

enum InputChecks {
    static func run(_ checks: Checks) {
        checks.run("key map: every key the iPad sends has a Mac key code") {
            let letters = (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { "Key\(Character(UnicodeScalar($0)))" }
            let digits = (0...9).map { "Digit\($0)" }
            let others = ["MetaLeft", "MetaRight", "ShiftLeft", "ShiftRight", "AltLeft", "AltRight", "ControlLeft",
                          "Tab", "Enter", "Space", "Backspace", "Escape", "Equal", "Minus", "Delete",
                          "PageUp", "PageDown", "Home", "End", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"]
                + (1...12).map { "F\($0)" }
            for code in letters + digits + others {
                try expect(KeyMap.codes[code] != nil, "\(code) is mapped")
            }
            try expectEqual(Set(KeyMap.codes.values).count, KeyMap.codes.count, "distinct Mac key codes")
        }

        checks.run("shortcuts: keys go down in order and up in reverse") {
            let input = RecordingInput()
            input.combo(["MetaLeft", "ShiftLeft", "KeyZ"])
            try expectEqual(input.events, ["down MetaLeft", "down ShiftLeft", "down KeyZ", "up KeyZ", "up ShiftLeft", "up MetaLeft"], "events")
        }

        checks.run("keyboard layout: labels come from the Mac's current layout") {
            let labels = KeyboardLayout.currentLabels()
            try expect(!labels.isEmpty, "some keys are labelled")
            let characterKeys = Set(KeyMap.characterKeys)
            for (code, pair) in labels {
                try expect(characterKeys.contains(code), "\(code) is a character key")
                try expect(pair.count == 2 && !pair[0].isEmpty, "\(code) has an unshifted label")
            }
        }
    }
}
