import Foundation
import XCTest
@testable import MouseIncCore

final class CustomGestureRecognizerTests: XCTestCase {
    func testTrainerBuildsThreeNormalizedSamplesAndRecognizerMatchesVariation() throws {
        let samples = [
            transformed(baseShape, scaleX: 100, scaleY: 90, offsetX: 0, offsetY: 0),
            transformed(baseShape, scaleX: 140, scaleY: 110, offsetX: 80, offsetY: -30),
            transformed(baseShape, scaleX: 90, scaleY: 130, offsetX: -50, offsetY: 70)
        ]
        let result = try CustomGestureTrainer.train(
            identifier: "CUSTOM_TEST",
            name: "测试轨迹",
            rawSamples: samples
        )

        XCTAssertEqual(result.definition.samples.count, 3)
        XCTAssertTrue(result.definition.samples.allSatisfy { $0.count == 64 })
        XCTAssertGreaterThanOrEqual(result.cohesionScore, 0.70)

        let candidate = transformed(baseShape, scaleX: 125, scaleY: 105, offsetX: 30, offsetY: 40)
        let match = CustomGestureRecognizer(definitions: [result.definition]).recognize(candidate)
        XCTAssertEqual(match?.identifier, "CUSTOM_TEST")
        XCTAssertGreaterThanOrEqual(match?.score ?? 0, 0.78)
    }

    func testRecognizerRejectsAmbiguousTopCandidates() throws {
        let shape = transformed(baseShape, scaleX: 100, scaleY: 100, offsetX: 0, offsetY: 0)
        let samples = [shape, shape, shape]
        let first = try CustomGestureTrainer.train(
            identifier: "CUSTOM_A",
            name: "A",
            rawSamples: samples
        ).definition
        var second = first
        second.identifier = "CUSTOM_B"
        second.name = "B"

        XCTAssertNil(CustomGestureRecognizer(definitions: [first, second]).recognize(shape))
    }

    func testRecognizerRejectsShortAndReversedCandidates() throws {
        let upward = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100)]
        let definition = try CustomGestureTrainer.train(
            identifier: "CUSTOM_UPWARD",
            name: "向上",
            rawSamples: [upward, upward, upward]
        ).definition
        let recognizer = CustomGestureRecognizer(definitions: [definition])

        XCTAssertNil(recognizer.recognize([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 20)]))
        XCTAssertNil(recognizer.recognize(Array(upward.reversed())))
    }

    func testTrainerRejectsInconsistentSamples() {
        let vertical = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100)]
        let horizontal = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]

        XCTAssertThrowsError(try CustomGestureTrainer.train(
            identifier: "CUSTOM_BAD",
            name: "不一致",
            rawSamples: [
                transformed(baseShape, scaleX: 100, scaleY: 100, offsetX: 0, offsetY: 0),
                vertical,
                horizontal
            ]
        )) { error in
            guard case CustomGestureTrainingError.inconsistentSamples = error else {
                return XCTFail("Expected inconsistentSamples, got \(error)")
            }
        }
    }

    func testTrainerRejectsSamplesThatAreTooShort() {
        let short = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]

        XCTAssertThrowsError(try CustomGestureTrainer.train(
            identifier: "CUSTOM_SHORT",
            name: "过短",
            rawSamples: [short, short, short]
        )) { error in
            XCTAssertEqual(error as? CustomGestureTrainingError, .invalidSample(0))
        }
    }

    func testTrainerWarnsWhenSamplesOverlapBoundFixedGesture() throws {
        let upward = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100)]
        let result = try CustomGestureTrainer.train(
            identifier: "CUSTOM_UP",
            name: "向上",
            rawSamples: [upward, upward, upward],
            fixedGestureIdentifiers: ["UP"]
        )

        XCTAssertTrue(result.warnings.contains { $0.contains("UP") })
    }

    private var baseShape: [CGPoint] {
        [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.15, y: 0.75),
            CGPoint(x: 0.55, y: 0.35),
            CGPoint(x: 1, y: 1)
        ]
    }

    private func transformed(
        _ points: [CGPoint],
        scaleX: Double,
        scaleY: Double,
        offsetX: Double,
        offsetY: Double
    ) -> [CGPoint] {
        points.map {
            CGPoint(x: $0.x * scaleX + offsetX, y: $0.y * scaleY + offsetY)
        }
    }
}
