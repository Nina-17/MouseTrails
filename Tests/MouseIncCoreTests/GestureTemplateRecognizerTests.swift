import MouseIncCore
import XCTest

final class GestureTemplateRecognizerTests: XCTestCase {
    func testBuiltInTemplatesRecognizeScaledTranslatedSamples() {
        let recognizer = GestureTemplateRecognizer()

        for template in GestureTemplate.builtIns {
            let transformed = template.points.enumerated().map { index, point in
                CGPoint(
                    x: point.x * 180 + 320 + sin(Double(index)) * 0.7,
                    y: point.y * 140 - 90 + cos(Double(index)) * 0.7
                )
            }
            XCTAssertEqual(recognizer.recognize(transformed)?.identifier, template.identifier)
        }
    }

    func testRejectsUnrelatedPathAtStrictThreshold() {
        let recognizer = GestureTemplateRecognizer(minimumScore: 0.95)
        let path = [
            CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 80),
            CGPoint(x: 90, y: 10), CGPoint(x: 120, y: 90)
        ]

        XCTAssertNil(recognizer.recognize(path))
    }

    func testMainRecognizerReturnsTemplateIdentifierForCircle() {
        let points = GestureTemplate.builtIns.first { $0.identifier == "CIRCLE" }!.points.map {
            CGPoint(x: $0.x * 100, y: $0.y * 100)
        }

        XCTAssertEqual(
            GestureRecognizer(simplificationTolerance: 8, minimumGestureLength: 40).recognize(points),
            "CIRCLE"
        )
    }
}
