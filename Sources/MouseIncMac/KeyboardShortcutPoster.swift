import CoreGraphics
import Foundation

enum KeyboardShortcutPoster {
    private struct Modifier {
        let flag: CGEventFlags
        let keyCode: CGKeyCode
    }

    private static let modifiers = [
        Modifier(flag: .maskControl, keyCode: 59),
        Modifier(flag: .maskAlternate, keyCode: 58),
        Modifier(flag: .maskShift, keyCode: 56),
        Modifier(flag: .maskCommand, keyCode: 55)
    ]

    static func post(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let activeModifiers = modifiers.filter { flags.contains($0.flag) }
        var activeFlags: CGEventFlags = []

        for modifier in activeModifiers {
            activeFlags.insert(modifier.flag)
            guard post(
                keyCode: modifier.keyCode,
                keyDown: true,
                flags: activeFlags,
                source: source
            ) else {
                release(activeModifiers, flags: activeFlags, source: source)
                return false
            }
        }

        guard post(keyCode: keyCode, keyDown: true, flags: flags, source: source) else {
            release(activeModifiers, flags: activeFlags, source: source)
            return false
        }
        usleep(30_000)
        guard post(keyCode: keyCode, keyDown: false, flags: flags, source: source) else {
            release(activeModifiers, flags: activeFlags, source: source)
            return false
        }
        release(activeModifiers, flags: activeFlags, source: source)
        return true
    }

    private static func release(
        _ modifiers: [Modifier],
        flags: CGEventFlags,
        source: CGEventSource?
    ) {
        var remainingFlags = flags
        for modifier in modifiers.reversed() {
            remainingFlags.remove(modifier.flag)
            _ = post(
                keyCode: modifier.keyCode,
                keyDown: false,
                flags: remainingFlags,
                source: source
            )
        }
    }

    private static func post(
        keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags,
        source: CGEventSource?
    ) -> Bool {
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: keyDown
        ) else { return false }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        return true
    }
}
