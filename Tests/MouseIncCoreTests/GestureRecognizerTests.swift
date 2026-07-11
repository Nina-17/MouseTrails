import Foundation
import XCTest
@testable import MouseIncCore

final class GestureRecognizerTests: XCTestCase {
    private let recognizer = GestureRecognizer(
        simplificationTolerance: 5,
        minimumGestureLength: 20
    )

    func testRecognizesEightDirections() {
        let cases: [(CGPoint, String)] = [
            (CGPoint(x: 0, y: 100), "UP"),
            (CGPoint(x: 0, y: -100), "DOWN"),
            (CGPoint(x: -100, y: 0), "LEFT"),
            (CGPoint(x: 100, y: 0), "RIGHT"),
            (CGPoint(x: -100, y: 100), "UP_LEFT"),
            (CGPoint(x: 100, y: 100), "UP_RIGHT"),
            (CGPoint(x: -100, y: -100), "DOWN_LEFT"),
            (CGPoint(x: 100, y: -100), "DOWN_RIGHT")
        ]

        for (end, expected) in cases {
            XCTAssertEqual(
                recognizer.recognize([.zero, end]),
                expected,
                "Failed direction \(expected)"
            )
        }
    }

    func testExistingCardinalGestureToleratesSmallDrift() {
        XCTAssertEqual(
            recognizer.recognize([.zero, CGPoint(x: 20, y: 100)]),
            "UP"
        )
        XCTAssertEqual(
            recognizer.recognize([.zero, CGPoint(x: 100, y: -20)]),
            "RIGHT"
        )
    }

    func testExistingLShapeRemainsDistinctFromSingleDiagonal() {
        let lShape = [
            CGPoint(x: 0, y: 100),
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0)
        ]

        XCTAssertEqual(recognizer.recognize(lShape), "DOWN-RIGHT")
        XCTAssertEqual(
            recognizer.recognize([CGPoint(x: 0, y: 100), CGPoint(x: 100, y: 0)]),
            "DOWN_RIGHT"
        )
    }

    func testDiagonalPolylineKeepsSegmentOrder() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 60, y: 60),
            CGPoint(x: 120, y: 0)
        ]

        XCTAssertEqual(recognizer.recognize(points), "UP_RIGHT-DOWN_RIGHT")
    }
}
