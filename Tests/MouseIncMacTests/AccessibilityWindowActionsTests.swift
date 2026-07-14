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

    func testMultiWindowLayoutsPreserveFocusedWindowOrdering() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1_000, height: 600)
        let left = CGRect(x: 0, y: 0, width: 500, height: 600)
        let right = CGRect(x: 500, y: 0, width: 500, height: 600)
        let top = CGRect(x: 0, y: 0, width: 1_000, height: 300)
        let bottom = CGRect(x: 0, y: 300, width: 1_000, height: 300)
        let topLeft = CGRect(x: 0, y: 0, width: 500, height: 300)
        let topRight = CGRect(x: 500, y: 0, width: 500, height: 300)
        let bottomLeft = CGRect(x: 0, y: 300, width: 500, height: 300)
        let bottomRight = CGRect(x: 500, y: 300, width: 500, height: 300)

        XCTAssertEqual(WindowLayoutCalculator.frames(for: .arrangeLeftRight, in: bounds), [left, right])
        XCTAssertEqual(WindowLayoutCalculator.frames(for: .arrangeRightLeft, in: bounds), [right, left])
        XCTAssertEqual(WindowLayoutCalculator.frames(for: .arrangeTopBottom, in: bounds), [top, bottom])
        XCTAssertEqual(WindowLayoutCalculator.frames(for: .arrangeBottomTop, in: bounds), [bottom, top])
        XCTAssertEqual(
            WindowLayoutCalculator.frames(for: .arrangeFour, in: bounds),
            [topLeft, topRight, bottomLeft, bottomRight]
        )
        XCTAssertEqual(
            WindowLayoutCalculator.frames(for: .arrangeLeftAndQuarters, in: bounds),
            [left, topRight, bottomRight]
        )
        XCTAssertEqual(
            WindowLayoutCalculator.frames(for: .arrangeRightAndQuarters, in: bounds),
            [right, topLeft, bottomLeft]
        )
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
