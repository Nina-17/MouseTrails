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

    func testCornerLayoutsUseQuartzScreenCoordinates() throws {
        let bounds = CGRect(x: 100, y: 50, width: 1_200, height: 800)
        let expected: [WindowAction: CGRect] = [
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

    func testNativeWindowActionsUseMacOSMenuCommands() {
        let modifiers: UInt32 = (1 << 2) | (1 << 3)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.fill)?.virtualKey, nil)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.center)?.virtualKey, nil)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.tileLeft)?.virtualKey, 123)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.tileRight)?.virtualKey, 124)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.tileTop)?.virtualKey, 126)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.tileBottom)?.virtualKey, 125)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.tileTopLeft)?.virtualKey, nil)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.tileTopRight)?.virtualKey, nil)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.tileBottomLeft)?.virtualKey, nil)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.tileBottomRight)?.virtualKey, nil)
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.restorePreviousSize)?.virtualKey, nil)
        XCTAssertTrue(NativeWindowMenuCommand.forAction(.fill)?.titles.contains("Fill") == true)
        XCTAssertTrue(
            NativeWindowMenuCommand.forAction(.restorePreviousSize)?.titles
                .contains("Return to Previous Size") == true
        )
        XCTAssertEqual(NativeWindowMenuCommand.forAction(.fill)?.modifiers, modifiers)
        XCTAssertTrue(NativeWindowMenuCommand.forAction(.tileTopLeft)?.titles.contains("Top Left") == true)
    }

    func testNonLayoutActionsDoNotProduceLayoutFrames() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let nonLayoutActions: [WindowAction] = [
            .center, .maximize, .fill, .restorePreviousSize,
            .tileLeft, .tileRight, .tileTop, .tileBottom,
            .minimize, .close, .closeAll, .quitApplication
        ]
        for action in nonLayoutActions {
            XCTAssertNil(WindowLayoutCalculator.frames(for: action, in: bounds))
        }
    }
}
