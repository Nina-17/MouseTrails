import CoreGraphics
import MouseIncCore

enum PermissionCoordinator {
    static var snapshot: PermissionSnapshot {
        PermissionSnapshot(
            states: [
                .accessibility: AccessibilityPermission.isGranted ? .granted : .denied,
                .screenRecording: CGPreflightScreenCaptureAccess() ? .granted : .denied,
                .inputMonitoring: CGPreflightListenEventAccess() ? .granted : .denied
            ]
        )
    }
}
