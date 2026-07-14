import MouseIncCore
import XCTest
@testable import MouseIncMac

@MainActor
final class SystemViewActionsTests: XCTestCase {
    func testEveryKeyboardDrivenSystemViewHasStableShortcut() throws {
        XCTAssertEqual(
            SystemViewActions.shortcut(for: .missionControl),
            SystemViewShortcut(keyCode: 126, flags: .maskControl)
        )
        XCTAssertEqual(
            SystemViewActions.shortcut(for: .appExpose),
            SystemViewShortcut(keyCode: 125, flags: .maskControl)
        )
        XCTAssertEqual(
            SystemViewActions.shortcut(for: .showDesktop),
            SystemViewShortcut(keyCode: 103, flags: [])
        )
        XCTAssertEqual(
            SystemViewActions.shortcut(for: .previousSpace),
            SystemViewShortcut(keyCode: 123, flags: .maskControl)
        )
        XCTAssertEqual(
            SystemViewActions.shortcut(for: .nextSpace),
            SystemViewShortcut(keyCode: 124, flags: .maskControl)
        )
        XCTAssertNil(SystemViewActions.shortcut(for: .launchpad))
    }

    func testApplicationsViewSupportsCurrentAndLegacyMacOSPaths() {
        XCTAssertEqual(SystemViewActions.applicationCandidates.first, "/System/Applications/Apps.app")
        XCTAssertTrue(SystemViewActions.applicationCandidates.contains("/System/Applications/Launchpad.app"))
        XCTAssertNotNil(SystemViewActions.applicationCandidates.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }))
    }
}
