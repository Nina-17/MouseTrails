import MouseIncCore
import XCTest
@testable import MouseIncMac

@MainActor
final class SystemViewActionsTests: XCTestCase {
    func testOnlyShowDesktopDependsOnAKeyboardShortcut() throws {
        XCTAssertEqual(
            SystemViewActions.shortcut(for: .showDesktop),
            SystemViewShortcut(keyCode: 103, flags: .maskSecondaryFn)
        )
        XCTAssertNil(SystemViewActions.shortcut(for: .appExpose))
        XCTAssertNil(SystemViewActions.shortcut(for: .missionControl))
        XCTAssertNil(SystemViewActions.shortcut(for: .previousSpace))
        XCTAssertNil(SystemViewActions.shortcut(for: .nextSpace))
        XCTAssertNil(SystemViewActions.shortcut(for: .launchpad))
    }

    func testApplicationsViewSupportsCurrentAndLegacyMacOSPaths() {
        XCTAssertEqual(SystemViewActions.applicationsViewCandidates.first, "/System/Applications/Apps.app")
        XCTAssertTrue(SystemViewActions.applicationsViewCandidates.contains("/System/Applications/Launchpad.app"))
        XCTAssertNotNil(SystemViewActions.applicationsViewCandidates.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }))
        XCTAssertNotNil(SystemViewActions.missionControlCandidates.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }))
    }

    func testCustomSystemShortcutOverridesFallbackAndDisabledShortcutIsRejected() {
        let customPreferences: [String: Any] = [
            "36": [
                "enabled": true,
                "value": [
                    "parameters": [NSNumber(value: 0), NSNumber(value: 12), NSNumber(value: 1_048_576)]
                ]
            ]
        ]
        XCTAssertEqual(
            SystemViewActions.resolvedShortcut(for: .showDesktop, preferences: customPreferences),
            SystemViewShortcut(keyCode: 12, flags: .maskCommand)
        )

        let disabledPreferences: [String: Any] = ["36": ["enabled": false]]
        XCTAssertNil(
            SystemViewActions.resolvedShortcut(for: .showDesktop, preferences: disabledPreferences)
        )
    }

    func testMissingOrIncompletePreferenceUsesKnownSystemFallback() {
        XCTAssertEqual(
            SystemViewActions.resolvedShortcut(for: .showDesktop, preferences: [:]),
            SystemViewActions.shortcut(for: .showDesktop)
        )
        XCTAssertEqual(
            SystemViewActions.resolvedShortcut(
                for: .showDesktop,
                preferences: ["36": ["enabled": true]]
            ),
            SystemViewActions.shortcut(for: .showDesktop)
        )
    }

    func testDockControlSwipeUsesOppositeNormalVelocityDirections() {
        let next = DockControlSwipeConfiguration(direction: .next)
        XCTAssertEqual(next.progress, 1)
        XCTAssertEqual(next.velocityX, 1)

        let previous = DockControlSwipeConfiguration(direction: .previous)
        XCTAssertEqual(previous.progress, -1)
        XCTAssertEqual(previous.velocityX, -1)
    }
}
