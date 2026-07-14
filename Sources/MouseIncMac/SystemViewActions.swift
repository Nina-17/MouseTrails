import AppKit
import MouseIncCore

struct SystemViewShortcut: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

@MainActor
enum SystemViewActions {
    static let applicationCandidates = [
        "/System/Applications/Apps.app",
        "/System/Applications/Launchpad.app"
    ]

    static func shortcut(for action: SystemViewAction) -> SystemViewShortcut? {
        switch action {
        case .missionControl:
            return SystemViewShortcut(keyCode: 126, flags: .maskControl)
        case .appExpose:
            return SystemViewShortcut(keyCode: 125, flags: .maskControl)
        case .showDesktop:
            return SystemViewShortcut(keyCode: 103, flags: [])
        case .previousSpace:
            return SystemViewShortcut(keyCode: 123, flags: .maskControl)
        case .nextSpace:
            return SystemViewShortcut(keyCode: 124, flags: .maskControl)
        case .launchpad:
            return nil
        }
    }

    static func perform(_ action: SystemViewAction) -> Bool {
        if action == .launchpad {
            return openApplicationsView()
        }
        guard let shortcut = shortcut(for: action) else { return false }
        return post(shortcut)
    }

    private static func openApplicationsView() -> Bool {
        guard let path = applicationCandidates.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else { return false }
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: .init()
        )
        return true
    }

    private static func post(_ shortcut: SystemViewShortcut) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: shortcut.keyCode,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: shortcut.keyCode,
                keyDown: false
            )
        else { return false }
        keyDown.flags = shortcut.flags
        keyUp.flags = shortcut.flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
