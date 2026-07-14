import MouseIncCore
import XCTest
@testable import MouseIncMac

final class PermissionCoordinatorTests: XCTestCase {
    func testOnlyUsedPermissionDomainsAreExposed() {
        XCTAssertEqual(SystemPermission.allCases, [.accessibility, .screenRecording])
    }

    func testPermissionSettingsURLsUseExpectedPrivacyAnchors() {
        XCTAssertEqual(
            PermissionCoordinator.systemSettingsURL(for: .accessibility)?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        XCTAssertEqual(
            PermissionCoordinator.systemSettingsURL(for: .screenRecording)?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    func testPermissionDisplayNamesAreUserFacing() {
        XCTAssertEqual(PermissionCoordinator.displayName(for: .accessibility), "辅助功能")
        XCTAssertEqual(PermissionCoordinator.displayName(for: .screenRecording), "屏幕录制")
    }
}
