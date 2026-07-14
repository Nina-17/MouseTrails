import MouseIncCore
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

    func testSingleWindowLayoutsUseQuartzScreenCoordinates() throws {
        let bounds = CGRect(x: 100, y: 50, width: 1_200, height: 800)
        let expected: [WindowAction: CGRect] = [
            .fill: bounds,
            .tileLeft: CGRect(x: 100, y: 50, width: 600, height: 800),
            .tileRight: CGRect(x: 700, y: 50, width: 600, height: 800),
            .tileTop: CGRect(x: 100, y: 50, width: 1_200, height: 400),
            .tileBottom: CGRect(x: 100, y: 450, width: 1_200, height: 400),
            .tileTopLeft: CGRect(x: 100, y: 50, width: 600, height: 400),
            .tileTopRight: CGRect(x: 700, y: 50, width: 600, height: 400),
            .tileBottomLeft: CGRect(x: 100, y: 450, width: 600, height: 400),
            .tileBottomRight: CGRect(x: 700, y: 450, width: 600, height: 400)
        ]

        for (action, frame) in expected {
            XCTAssertEqual(
                try XCTUnwrap(WindowLayoutCalculator.frames(for: action, in: bounds)),
                [frame],
                "Unexpected frame for \(action)"
            )
        }
    }

    func testNonLayoutActionsDoNotProduceLayoutFrames() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let nonLayoutActions: [WindowAction] = [
            .center, .maximize, .restorePreviousSize, .minimize, .close, .closeAll,
            .quitApplication
        ]
        for action in nonLayoutActions {
            XCTAssertNil(WindowLayoutCalculator.frames(for: action, in: bounds))
        }
    }
}
