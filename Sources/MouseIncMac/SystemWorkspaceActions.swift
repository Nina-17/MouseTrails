import AppKit
import CoreGraphics
import Darwin
import Foundation

enum SpaceNavigationDirection {
    case previous
    case next
}

struct DockControlSwipeConfiguration: Equatable {
    let progress: Double
    let velocityX: Double

    init(direction: SpaceNavigationDirection) {
        let sign = direction == .next ? 1.0 : -1.0
        progress = sign
        velocityX = sign
    }
}

@MainActor
enum SystemWorkspaceActions {
    private typealias CoreDockNotificationFunction = @convention(c) (CFString, UnsafeRawPointer?) -> Void

    // These values are private CGS/Dock event fields. They represent the same
    // high-velocity horizontal swipe consumed by Dock for changing Spaces.
    private enum DockControlField {
        static let eventType = CGEventField(rawValue: 55)!
        static let gestureHIDType = CGEventField(rawValue: 110)!
        static let swipeMotion = CGEventField(rawValue: 123)!
        static let swipeProgress = CGEventField(rawValue: 124)!
        static let swipeVelocityX = CGEventField(rawValue: 129)!
        static let gesturePhase = CGEventField(rawValue: 132)!
    }

    private static let coreDockNotification = loadCoreDockNotification()

    static func switchSpace(_ direction: SpaceNavigationDirection) -> Bool {
        guard let event = CGEvent(source: nil) else {
            DiagnosticLogger.shared.log("DockControl space swipe event creation failed")
            return false
        }

        let configuration = DockControlSwipeConfiguration(direction: direction)
        event.setIntegerValueField(DockControlField.eventType, value: 30)
        event.setIntegerValueField(DockControlField.gestureHIDType, value: 23)
        event.setIntegerValueField(DockControlField.swipeMotion, value: 1)
        event.setDoubleValueField(DockControlField.swipeProgress, value: configuration.progress)
        event.setDoubleValueField(DockControlField.swipeVelocityX, value: configuration.velocityX)

        event.setIntegerValueField(DockControlField.gesturePhase, value: 1)
        event.post(tap: .cgSessionEventTap)
        event.setIntegerValueField(DockControlField.gesturePhase, value: 4)
        event.post(tap: .cgSessionEventTap)

        DiagnosticLogger.shared.log(
            "DockControl space swipe posted direction=\(direction) velocity=\(configuration.velocityX)"
        )
        return true
    }

    static func showFrontApplicationWindows() -> Bool {
        guard let coreDockNotification else {
            DiagnosticLogger.shared.log("CoreDockSendNotification is unavailable")
            return false
        }
        guard NSWorkspace.shared.frontmostApplication != nil else { return false }
        coreDockNotification("com.apple.expose.front.awake" as CFString, nil)
        DiagnosticLogger.shared.log("CoreDock App Expose notification sent")
        return true
    }

    private static func loadCoreDockNotification() -> CoreDockNotificationFunction? {
        let candidates = [
            "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock",
            "/System/Library/PrivateFrameworks/CoreDock.framework/CoreDock"
        ]
        for candidate in candidates {
            guard let handle = dlopen(candidate, RTLD_LAZY),
                  let symbol = dlsym(handle, "CoreDockSendNotification") else { continue }
            return unsafeBitCast(symbol, to: CoreDockNotificationFunction.self)
        }
        return nil
    }
}
