import Foundation
import XCTest
@testable import MouseIncCore

final class RectangleGestureRecognizerTests: XCTestCase {
    private let recognizer = GestureRecognizer(simplificationTolerance: 18, minimumGestureLength: 40)

    func testRecognizesImperfectOpenRectangleInBothDirections() {
        let clockwise = polyline([
            CGPoint(x: 12, y: 8), CGPoint(x: 108, y: 5),
            CGPoint(x: 114, y: 72), CGPoint(x: 7, y: 78),
            CGPoint(x: 4, y: 18), CGPoint(x: 17, y: 12)
        ])
        XCTAssertEqual(recognizer.recognize(clockwise), "SQUARE")
        XCTAssertEqual(recognizer.recognize(clockwise.reversed()), "SQUARE")
    }

    func testRecognizesWideHandDrawnRectangle() {
        let points = polyline([
            CGPoint(x: 0, y: 0), CGPoint(x: 220, y: 4),
            CGPoint(x: 216, y: 54), CGPoint(x: 5, y: 58),
            CGPoint(x: 1, y: 6)
        ])
        XCTAssertEqual(recognizer.recognize(points), "SQUARE")
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

        XCTAssertNotEqual(recognizer.recognize(circle), "SQUARE")
        XCTAssertNotEqual(recognizer.recognize(cShape), "SQUARE")
        XCTAssertNotEqual(recognizer.recognize(zigzag), "SQUARE")
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
