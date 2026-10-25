import AppKit
import CoreGraphics

/// Posts real keyboard and mouse events for one connected iPad.
public final class InputSession: InputTarget {
    public init() {}

    private let source = CGEventSource(stateID: .hidSystemState)
    private let doubleClickInterval = NSEvent.doubleClickInterval
    private var heldKeys: Set<CGKeyCode> = []
    private var heldButtons: Set<MouseButton> = []
    private var lastClick: (button: MouseButton, time: TimeInterval, point: CGPoint, count: Int)?

    private var modifierFlags: CGEventFlags {
        heldKeys.reduce(into: CGEventFlags()) { flags, code in
            if let flag = KeyMap.modifierFlags[code] { flags.insert(flag) }
        }
    }

    private var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    // MARK: Keyboard

    public func keyDown(_ name: String, isRepeat: Bool) {
        guard let code = KeyMap.codes[name] else { return }
        heldKeys.insert(code)
        postKey(code, down: true, isRepeat: isRepeat)
    }

    public func keyUp(_ name: String) {
        guard let code = KeyMap.codes[name], heldKeys.remove(code) != nil else { return }
        postKey(code, down: false)
    }

    public func type(_ text: String) {
        for character in text {
            if character.isNewline {
                tap(KeyMap.returnKey)
                continue
            }
            let units = Array(String(character).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    public func system(_ action: SystemAction) {
        switch action {
        case .volumeUp: media(0)
        case .volumeDown: media(1)
        case .brightnessUp: media(2)
        case .brightnessDown: media(3)
        case .mute: media(7)
        case .playPause: media(16)
        case .next: media(17)
        case .previous: media(18)
        case .missionControl: tap(KeyMap.up, with: .maskControl)
        case .appExpose: tap(KeyMap.down, with: .maskControl)
        case .spaceLeft: tap(KeyMap.left, with: .maskControl)
        case .spaceRight: tap(KeyMap.right, with: .maskControl)
        case .spotlight: tap(KeyMap.space, with: .maskCommand)
        case .lockScreen: tap(KeyMap.q, with: [.maskControl, .maskCommand])
        }
    }

    private func postKey(_ code: CGKeyCode, down: Bool, isRepeat: Bool = false, extra: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        var flags = modifierFlags.union(extra)
        if KeyMap.arrowKeys.contains(code) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        if KeyMap.navigationKeys.contains(code) { flags.insert(.maskSecondaryFn) }
        event.flags = flags
        if isRepeat { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        event.post(tap: .cghidEventTap)
    }

    private func tap(_ code: CGKeyCode, with extra: CGEventFlags = []) {
        postKey(code, down: true, extra: extra)
        postKey(code, down: false, extra: extra)
    }

    /// Media and brightness keys travel as NX system-defined events, not key codes.
    private func media(_ key: Int) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: (key << 16) | (state << 8), data2: -1
            )?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Pointer

    public func move(dx: Double, dy: Double) {
        let current = cursor
        let target = Display.clamp(CGPoint(x: current.x + dx, y: current.y + dy), near: current)
        let (type, button): (CGEventType, CGMouseButton) =
            heldButtons.contains(.left) ? (.leftMouseDragged, .left)
            : heldButtons.contains(.right) ? (.rightMouseDragged, .right)
            : (.mouseMoved, .left)
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: button) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx.rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy.rounded()))
        event.flags = modifierFlags
        event.post(tap: .cghidEventTap)
    }

    public func button(_ button: MouseButton, down: Bool) {
        let point = cursor
        if down {
            guard heldButtons.insert(button).inserted else { return }
            let now = ProcessInfo.processInfo.systemUptime
            var count = 1
            if let last = lastClick, last.button == button, now - last.time < doubleClickInterval,
               hypot(last.point.x - point.x, last.point.y - point.y) < 6 {
                count = min(last.count + 1, 3)
            }
            lastClick = (button, now, point, count)
        } else {
            guard heldButtons.remove(button) != nil else { return }
        }

        let type: CGEventType = switch (button, down) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                                  mouseButton: button == .left ? .left : .right) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: Int64(lastClick?.count ?? 1))
        event.flags = modifierFlags
        event.post(tap: .cghidEventTap)
    }

    public func scroll(dx: Double, dy: Double) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0) else { return }
        event.flags = modifierFlags
        event.post(tap: .cghidEventTap)
    }

    public func releaseAll() {
        // Let go of regular keys before modifiers so nothing fires as a shortcut.
        let order = heldKeys.sorted { (KeyMap.modifierFlags[$0] == nil) && (KeyMap.modifierFlags[$1] != nil) }
        for code in order {
            heldKeys.remove(code)
            postKey(code, down: false)
        }
        for button in heldButtons { self.button(button, down: false) }
    }
}

enum Display {
    /// Keeps the pointer on a connected display.
    static func clamp(_ point: CGPoint, near current: CGPoint) -> CGPoint {
        let screens = activeBounds()
        if screens.isEmpty || screens.contains(where: { $0.contains(point) }) { return point }
        let home = screens.first { $0.contains(current) } ?? screens[0]
        return CGPoint(x: min(max(point.x, home.minX), home.maxX - 1),
                       y: min(max(point.y, home.minY), home.maxY - 1))
    }

    private static func activeBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }
}
