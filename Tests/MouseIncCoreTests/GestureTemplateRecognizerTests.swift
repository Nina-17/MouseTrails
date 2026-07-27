import MouseIncCore
import XCTest

final class GestureTemplateRecognizerTests: XCTestCase {
    func testBuiltInLettersAreRemoved() {
        XCTAssertFalse(GestureTemplate.builtIns.contains { $0.identifier == "LETTER_S" })
        XCTAssertFalse(GestureTemplate.builtIns.contains { $0.identifier == "LETTER_M" })
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

    func testDirectionRecognizerDoesNotReturnRetiredLetterIdentifiers() {
        let m = [
            CGPoint(x: 0, y: 0), CGPoint(x: 28, y: 92), CGPoint(x: 60, y: 8),
            CGPoint(x: 92, y: 90), CGPoint(x: 120, y: 0)
        ]
        let w = [
            CGPoint(x: 0, y: 95), CGPoint(x: 28, y: 0), CGPoint(x: 60, y: 88),
            CGPoint(x: 92, y: 2), CGPoint(x: 120, y: 96)
        ]

        let recognizer = GestureRecognizer(simplificationTolerance: 8, minimumGestureLength: 40)
        XCTAssertNotEqual(recognizer.recognize(m), "LETTER_M")
        XCTAssertNotEqual(recognizer.recognize(w), "LETTER_W")
    }
}
