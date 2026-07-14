import MouseIncCore
import XCTest

final class GestureTemplateRecognizerTests: XCTestCase {
    func testLegacyBuiltInSIsRemoved() {
        XCTAssertFalse(GestureTemplate.builtIns.contains { $0.identifier == "LETTER_S" })
    }

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

    func testMainRecognizerReturnsTemplateIdentifierForLetterW() {
        let points = GestureTemplate.builtIns.first { $0.identifier == "LETTER_W" }!.points.map {
            CGPoint(x: $0.x * 140 + 20, y: $0.y * 120 + 40)
        }

        XCTAssertEqual(
            GestureRecognizer(simplificationTolerance: 8, minimumGestureLength: 40).recognize(points),
            "LETTER_W"
        )
    }
}
