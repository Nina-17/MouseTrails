import MouseIncCore
import XCTest

final class EdgeScrollTests: XCTestCase {
    func testDetectsEachEdgeAndIgnoresInterior() {
        let detector = EdgeScrollDetector(inset: 3)
        let screen = CGRect(x: 0, y: 0, width: 100, height: 80)

        XCTAssertEqual(detector.edge(at: CGPoint(x: 50, y: 79), in: [screen]), .top)
        XCTAssertEqual(detector.edge(at: CGPoint(x: 50, y: 1), in: [screen]), .bottom)
        XCTAssertEqual(detector.edge(at: CGPoint(x: 1, y: 40), in: [screen]), .left)
        XCTAssertEqual(detector.edge(at: CGPoint(x: 99, y: 40), in: [screen]), .right)
        XCTAssertNil(detector.edge(at: CGPoint(x: 50, y: 40), in: [screen]))
    }

    func testUsesContainingScreenAtSharedDisplayBoundary() {
        let detector = EdgeScrollDetector(inset: 2)
        let left = CGRect(x: -100, y: 0, width: 100, height: 80)
        let right = CGRect(x: 0, y: 0, width: 100, height: 80)

        XCTAssertEqual(detector.edge(at: CGPoint(x: 0, y: 40), in: [left, right]), .left)
    }

    func testCooldownIsPerEdge() {
        var cooldown = EdgeScrollCooldown(interval: 0.6)

        XCTAssertTrue(cooldown.shouldFire(edge: .left, now: 1))
        XCTAssertFalse(cooldown.shouldFire(edge: .left, now: 1.2))
        XCTAssertTrue(cooldown.shouldFire(edge: .right, now: 1.2))
        XCTAssertTrue(cooldown.shouldFire(edge: .left, now: 1.6))
    }
}
