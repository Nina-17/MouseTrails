import Foundation
import XCTest
@testable import MouseIncCore

final class RectangleGestureRecognizerTests: XCTestCase {
    private let recognizer = GestureRecognizer(simplificationTolerance: 18, minimumGestureLength: 40)

    func testRecognizesImperfectOpenRectangleInBothDirections() {
        let counterclockwise = polyline([
            CGPoint(x: 12, y: 8), CGPoint(x: 108, y: 5),
            CGPoint(x: 114, y: 72), CGPoint(x: 7, y: 78),
            CGPoint(x: 4, y: 18), CGPoint(x: 17, y: 12)
        ])
        XCTAssertEqual(recognizer.recognize(counterclockwise), "SQUARE_COUNTERCLOCKWISE")
        XCTAssertEqual(recognizer.recognize(counterclockwise.reversed()), "SQUARE_CLOCKWISE")
    }

    func testRecognizesWideHandDrawnRectangle() {
        let points = polyline([
            CGPoint(x: 0, y: 0), CGPoint(x: 220, y: 4),
            CGPoint(x: 216, y: 54), CGPoint(x: 5, y: 58),
            CGPoint(x: 1, y: 6)
        ])
        XCTAssertEqual(recognizer.recognize(points), "SQUARE_COUNTERCLOCKWISE")
    }

    func testRecognizesThreeSidesWithBroadCurvedCorners() {
        let points = polyline([
            CGPoint(x: 2, y: 22), CGPoint(x: 5, y: 9), CGPoint(x: 18, y: 2),
            CGPoint(x: 88, y: 3), CGPoint(x: 105, y: 16), CGPoint(x: 108, y: 50),
            CGPoint(x: 96, y: 68), CGPoint(x: 18, y: 71)
        ], samplesPerSegment: 8)
        XCTAssertEqual(recognizer.recognize(points), "SQUARE_COUNTERCLOCKWISE")
    }

    func testRejectsCircleCShapeAndZigzag() {
        let circle = (0...80).map { index in
            let angle = Double(index) / 80 * .pi * 2
            return CGPoint(x: 60 + cos(angle) * 50, y: 60 + sin(angle) * 50)
        }
        let cShape = (10...70).map { index in
            let angle = Double(index) / 80 * .pi * 2
            return CGPoint(x: 60 + cos(angle) * 50, y: 60 + sin(angle) * 50)
        }
        let zigzag = polyline([
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 0, y: 80), CGPoint(x: 100, y: 80)
        ])

        XCTAssertFalse(recognizer.recognize(circle)?.hasPrefix("SQUARE") == true)
        XCTAssertFalse(recognizer.recognize(cShape)?.hasPrefix("SQUARE") == true)
        XCTAssertFalse(recognizer.recognize(zigzag)?.hasPrefix("SQUARE") == true)
    }

    private func polyline(_ vertices: [CGPoint], samplesPerSegment: Int = 12) -> [CGPoint] {
        zip(vertices, vertices.dropFirst()).flatMap { start, end in
            (0..<samplesPerSegment).map { index in
                let fraction = Double(index) / Double(samplesPerSegment)
                let wobble = index.isMultiple(of: 3) ? 1.2 : -0.8
                return CGPoint(
                    x: start.x + fraction * (end.x - start.x) + wobble,
                    y: start.y + fraction * (end.y - start.y) - wobble
                )
            }
        } + [vertices.last!]
    }
}
