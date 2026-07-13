import XCTest
@testable import MouseIncMac

final class AccessibilityWindowActionsTests: XCTestCase {
    func testCloseAllTerminatesSafariAndChrome() {
        XCTAssertEqual(
            CloseAllWindowStrategy.forBundleIdentifier("com.apple.Safari"),
            .terminateApplication
        )
        XCTAssertEqual(
            CloseAllWindowStrategy.forBundleIdentifier("com.google.Chrome"),
            .terminateApplication
        )
    }

    func testCloseAllKeepsShortcutForFinderAndOtherApplications() {
        XCTAssertEqual(
            CloseAllWindowStrategy.forBundleIdentifier("com.apple.finder"),
            .sendCloseAllShortcut
        )
        XCTAssertEqual(
            CloseAllWindowStrategy.forBundleIdentifier("com.example.application"),
            .sendCloseAllShortcut
        )
    }
}
