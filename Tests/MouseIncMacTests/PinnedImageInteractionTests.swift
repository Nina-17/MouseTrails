import XCTest
@testable import MouseIncMac

final class PinnedImageInteractionTests: XCTestCase {
    func testCompactToggleRestoresExpandedFrame() {
        let original = CGRect(x: 100, y: 200, width: 400, height: 240)
        var state = PinnedImageInteractionState(frame: original)

        state.toggleCompact()
        XCTAssertTrue(state.isCompact)
        XCTAssertEqual(state.frame, CGRect(x: 264, y: 368, width: 72, height: 72))

        state.toggleCompact()
        XCTAssertFalse(state.isCompact)
        XCTAssertEqual(state.frame, original)
    }

    func testMovingCompactImageAlsoMovesRestoreDestination() {
        let original = CGRect(x: 100, y: 200, width: 400, height: 240)
        var state = PinnedImageInteractionState(frame: original)

        state.toggleCompact()
        state.moveBy(dx: 25, dy: -10)
        state.toggleCompact()

        XCTAssertEqual(state.frame, original.offsetBy(dx: 25, dy: -10))
    }

    func testOpacityIsClampedToUsableRange() {
        var state = PinnedImageInteractionState(frame: .zero)

        state.adjustOpacity(by: -10)
        XCTAssertEqual(state.opacity, 0.2)
        state.adjustOpacity(by: 10)
        XCTAssertEqual(state.opacity, 1)
    }

    func testOnlyExpandedStateIsEligibleForCopy() {
        var state = PinnedImageInteractionState(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertTrue(state.allowsCopy)

        state.toggleCompact()
        XCTAssertFalse(state.allowsCopy)
    }
}
