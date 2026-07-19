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

    func testOnlySteamSplitProcessUsesLogicalHideCloseFallback() {
        XCTAssertEqual(
            LogicalWindowCloseFallback.forApplications(
                inputBundleIdentifier: "com.valvesoftware.steam.helper",
                logicalBundleIdentifier: "com.valvesoftware.steam"
            ),
            .hideLogicalApplication
        )
        XCTAssertEqual(
            LogicalWindowCloseFallback.forApplications(
                inputBundleIdentifier: "zlibrary",
                logicalBundleIdentifier: "zlibrary"
            ),
            .none
        )
        XCTAssertEqual(
            LogicalWindowCloseFallback.forApplications(
                inputBundleIdentifier: "com.example.helper",
                logicalBundleIdentifier: "com.example.application"
            ),
            .none
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

    func testFallbackLayoutCalculatesWholeAndHalfDesktopFrames() throws {
        let bounds = CGRect(x: 0, y: 32, width: 1_470, height: 844)
        let current = CGRect(x: 400, y: 200, width: 900, height: 600)

        XCTAssertEqual(
            try XCTUnwrap(WindowLayoutCalculator.targetFrame(
                for: .fill,
                currentFrame: current,
                in: bounds
            )),
            bounds
        )
        XCTAssertEqual(
            try XCTUnwrap(WindowLayoutCalculator.targetFrame(
                for: .tileLeft,
                currentFrame: current,
                in: bounds
            )),
            CGRect(x: 0, y: 32, width: 735, height: 844)
        )
        XCTAssertEqual(
            try XCTUnwrap(WindowLayoutCalculator.targetFrame(
                for: .tileBottom,
                currentFrame: current,
                in: bounds
            )),
            CGRect(x: 0, y: 454, width: 1_470, height: 422)
        )
    }

    func testConstrainedFallbackKeepsAcceptedSizeAndRequestedEdge() throws {
        let bounds = CGRect(x: 0, y: 32, width: 1_470, height: 844)
        let steamMinimum = CGSize(width: 1_010, height: 600)
        let zLibraryMinimum = CGSize(width: 1_100, height: 843)

        XCTAssertEqual(
            try XCTUnwrap(WindowLayoutCalculator.anchoredFrame(
                for: .tileLeft,
                acceptedSize: steamMinimum,
                in: bounds
            )),
            CGRect(x: 0, y: 32, width: 1_010, height: 600)
        )
        XCTAssertEqual(
            try XCTUnwrap(WindowLayoutCalculator.anchoredFrame(
                for: .tileRight,
                acceptedSize: zLibraryMinimum,
                in: bounds
            )),
            CGRect(x: 370, y: 32, width: 1_100, height: 843)
        )
        XCTAssertEqual(
            try XCTUnwrap(WindowLayoutCalculator.anchoredFrame(
                for: .tileBottom,
                acceptedSize: zLibraryMinimum,
                in: bounds
            )),
            CGRect(x: 0, y: 33, width: 1_100, height: 843)
        )
    }
}
