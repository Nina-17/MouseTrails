import Foundation
import XCTest
@testable import MouseIncMac

@MainActor
final class TutorialCoordinatorTests: XCTestCase {
    func testTutorialCompletionPersistsAndPracticeProducesSuccessEvent() throws {
        let suiteName = "TutorialCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = TutorialCoordinator(defaults: defaults)

        XCTAssertTrue(coordinator.shouldPresentOnLaunch)
        XCTAssertFalse(coordinator.handleRecognizedGesture("UP"))

        coordinator.begin()
        coordinator.next()
        XCTAssertEqual(coordinator.page, .defaultGestures)
        XCTAssertEqual(coordinator.selectedIdentifier, "UP")

        XCTAssertTrue(coordinator.handleRecognizedGesture("LEFT"))
        XCTAssertTrue(coordinator.practicedIdentifiers.isEmpty)
        XCTAssertNil(coordinator.successEventID)

        XCTAssertTrue(coordinator.handleRecognizedGesture(nil))
        XCTAssertTrue(coordinator.feedback?.contains("没有识别出轨迹") == true)

        XCTAssertTrue(coordinator.handleRecognizedGesture("UP"))
        XCTAssertEqual(coordinator.practicedIdentifiers, ["UP"])
        XCTAssertNotNil(coordinator.successEventID)

        coordinator.finish()
        XCTAssertFalse(coordinator.shouldPresentOnLaunch)
        XCTAssertFalse(coordinator.isPresenting)
    }

    func testPinAndOCRAreSeparateFromDefaultGestureLessons() throws {
        let defaultLesson = Set(TutorialPage.defaultGestures.gestureIdentifiers)
        let windowLesson = Set(TutorialPage.windowGestures.gestureIdentifiers)

        XCTAssertFalse(defaultLesson.contains("SQUARE_CLOCKWISE"))
        XCTAssertFalse(defaultLesson.contains("SQUARE_COUNTERCLOCKWISE"))
        XCTAssertFalse(windowLesson.contains("SQUARE_CLOCKWISE"))
        XCTAssertEqual(TutorialPage.pinnedImage.gestureIdentifiers, ["SQUARE_CLOCKWISE"])
        XCTAssertEqual(TutorialPage.ocr.gestureIdentifiers, ["SQUARE_COUNTERCLOCKWISE"])
    }
}
