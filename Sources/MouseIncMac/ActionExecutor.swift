import AppKit
import MouseIncCore

@MainActor
final class ActionExecutor {
    func execute(_ actions: [ActionDefinition]) {
        for action in actions {
            switch action.type {
            case .keyStroke:
                sendKeyStroke(action.value)
            case .openURL:
                if let url = URL(string: action.value) {
                    NSWorkspace.shared.open(url)
                }
            case .launchApplication:
                launchApplication(action.value)
            }
        }
    }

    private func launchApplication(_ value: String) {
        if value.hasPrefix("/") {
            let url = URL(fileURLWithPath: value)
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) {
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: .init())
        }
    }

    private func sendKeyStroke(_ value: String) {
        let tokens = value.split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard let keyToken = tokens.last, let keyCode = KeyMap.code(for: keyToken) else {
            return
        }

        var flags: CGEventFlags = []
        for token in tokens.dropLast() {
            switch token {
            case "command", "cmd": flags.insert(.maskCommand)
            case "control", "ctrl": flags.insert(.maskControl)
            case "option", "alt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: break
            }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

private enum KeyMap {
    private static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "return": 36, "enter": 36,
        "left": 123, "right": 124, "down": 125, "up": 126
    ]

    static func code(for token: String) -> CGKeyCode? {
        codes[token]
    }
}

