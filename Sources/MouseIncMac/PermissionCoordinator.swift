import AppKit
import CoreGraphics
import MouseIncCore

enum PermissionCoordinator {
    static var snapshot: PermissionSnapshot {
        PermissionSnapshot(
            states: [
                .accessibility: AccessibilityPermission.isGranted ? .granted : .denied,
                .screenRecording: CGPreflightScreenCaptureAccess() ? .granted : .denied
            ]
        )
    }

    static func systemSettingsURL(for permission: SystemPermission) -> URL? {
        let anchor: String
        switch permission {
        case .accessibility:
            anchor = "Privacy_Accessibility"
        case .screenRecording:
            anchor = "Privacy_ScreenCapture"
        }
        return URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        )
    }

    @MainActor
    @discardableResult
    static func openSystemSettings(for permission: SystemPermission) -> Bool {
        guard let url = systemSettingsURL(for: permission) else { return false }
        return NSWorkspace.shared.open(url)
    }

    static func displayName(for permission: SystemPermission) -> String {
        switch permission {
        case .accessibility: return "辅助功能"
        case .screenRecording: return "屏幕录制"
        }
    }
}
