import AppKit
import MouseIncCore

struct SystemViewShortcut: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

@MainActor
enum SystemViewActions {
    static let applicationsViewCandidates = [
        "/System/Applications/Apps.app",
        "/System/Applications/Launchpad.app"
    ]
    static let missionControlCandidates = [
        "/System/Applications/Mission Control.app"
    ]

    private static let symbolicHotKeyIDs: [SystemViewAction: String] = [.showDesktop: "36"]

    static func shortcut(for action: SystemViewAction) -> SystemViewShortcut? {
        switch action {
        case .missionControl, .appExpose:
            return nil
        case .showDesktop:
            return SystemViewShortcut(keyCode: 103, flags: .maskSecondaryFn)
        case .previousSpace, .nextSpace:
            return nil
        case .launchpad:
            return nil
        }
    }

    static func perform(_ action: SystemViewAction) -> Bool {
        switch action {
        case .missionControl:
            return openSystemApplication(candidates: missionControlCandidates)
        case .appExpose:
            return SystemWorkspaceActions.showFrontApplicationWindows()
        case .previousSpace:
            return SystemWorkspaceActions.switchSpace(.previous)
        case .nextSpace:
            return SystemWorkspaceActions.switchSpace(.next)
        case .launchpad:
            return openSystemApplication(candidates: applicationsViewCandidates)
        default:
            guard let shortcut = resolvedShortcut(
                for: action,
                preferences: symbolicHotKeyPreferences()
            ) else { return false }
            // Gesture actions are selected inside the HID mouse-up callback.
            // Dock ignores global shortcuts posted before that callback has
            // returned, so deliver them on the next main-queue turn.
            DispatchQueue.main.async {
                if !post(shortcut) {
                    DiagnosticLogger.shared.log(
                        "System shortcut event creation failed; action=\(action.rawValue)"
                    )
                }
            }
            return true
        }
    }

    static func resolvedShortcut(
        for action: SystemViewAction,
        preferences: [String: Any]?
    ) -> SystemViewShortcut? {
        guard let fallback = shortcut(for: action) else { return nil }
        guard let identifier = symbolicHotKeyIDs[action],
              let entry = preferences?[identifier] as? [String: Any] else {
            return fallback
        }
        if let enabled = entry["enabled"] as? Bool, !enabled { return nil }
        guard
            let value = entry["value"] as? [String: Any],
            let parameters = value["parameters"] as? [NSNumber],
            parameters.count >= 3,
            parameters[1].uint64Value != UInt64(UInt16.max)
        else { return fallback }
        return SystemViewShortcut(
            keyCode: CGKeyCode(parameters[1].uint16Value),
            flags: CGEventFlags(rawValue: parameters[2].uint64Value)
        )
    }

    private static func symbolicHotKeyPreferences() -> [String: Any]? {
        CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any]
    }

    private static func openSystemApplication(candidates: [String]) -> Bool {
        guard let path = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else { return false }
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: .init()
        )
        return true
    }

    private static func post(_ shortcut: SystemViewShortcut) -> Bool {
        KeyboardShortcutPoster.post(
            keyCode: shortcut.keyCode,
            flags: shortcut.flags
        )
    }
}
