import MouseIncCore
import XCTest

final class GestureTemplateRecognizerTests: XCTestCase {
    func testLegacyBuiltInLettersAreRemoved() {
        XCTAssertFalse(GestureTemplate.builtIns.contains { $0.identifier == "LETTER_S" })
        XCTAssertFalse(GestureTemplate.builtIns.contains { $0.identifier == "LETTER_W" })
        XCTAssertTrue(GestureTemplate.builtIns.isEmpty)
    }

    func testRejectsUnrelatedPathAtStrictThreshold() {
        let recognizer = GestureTemplateRecognizer(minimumScore: 0.95)
        let path = [
            CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 80),
            CGPoint(x: 90, y: 10), CGPoint(x: 120, y: 90)
        ]

        XCTAssertNil(recognizer.recognize(path))
    }

    func testMainRecognizerDoesNotReturnRetiredLetterW() {
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 80), CGPoint(x: 60, y: 20),
            CGPoint(x: 90, y: 80), CGPoint(x: 120, y: 0)
        ]
        XCTAssertNotEqual(
            GestureRecognizer(simplificationTolerance: 8, minimumGestureLength: 40).recognize(points),
            "LETTER_W"
        )
    }
}
