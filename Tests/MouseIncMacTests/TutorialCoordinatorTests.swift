import AppKit
import Foundation
import MouseIncCore
import XCTest
@testable import MouseIncMac

@MainActor
final class TutorialCoordinatorTests: XCTestCase {
    func testEditingAndBrowsingTasksAdvanceOnlyAfterRealResults() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(coordinator.shouldPresentOnLaunch)
        XCTAssertEqual(coordinator.handleRecognizedGesture("UP"), .notHandled)

        coordinator.begin()
        XCTAssertEqual(coordinator.handleRecognizedGesture("UP"), .consume)
        coordinator.nextFromWelcome()
        XCTAssertEqual(coordinator.page, .editing)
        XCTAssertEqual(coordinator.expectedGestureIdentifier, "UP")

        XCTAssertEqual(coordinator.handleRecognizedGesture("LEFT"), .consume)
        XCTAssertNil(coordinator.successEventID)

        let pasteboard = NSPasteboard.general
        XCTAssertEqual(coordinator.handleRecognizedGesture("UP"), .execute)
        pasteboard.clearContents()
        pasteboard.setString(TutorialCoordinator.editingSentence, forType: .string)
        try await Task.sleep(for: .milliseconds(1_100))

        XCTAssertEqual(coordinator.expectedGestureIdentifier, "DOWN")
        XCTAssertNotNil(coordinator.successEventID)
        coordinator.updatePastedText(TutorialCoordinator.editingSentence)
        try await Task.sleep(for: .milliseconds(800))

        XCTAssertEqual(coordinator.page, .browsing)
        XCTAssertEqual(coordinator.expectedGestureIdentifier, "LEFT")
        XCTAssertEqual(coordinator.handleRecognizedGesture("LEFT"), .consume)
        XCTAssertEqual(coordinator.browserPageIndex, 0)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(coordinator.expectedGestureIdentifier, "RIGHT")

        XCTAssertEqual(coordinator.handleRecognizedGesture("RIGHT"), .consume)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(coordinator.expectedGestureIdentifier, "LETTER_S")

        XCTAssertEqual(coordinator.handleRecognizedGesture("LETTER_S"), .execute)
        XCTAssertNil(coordinator.configurationForCurrentContext)
        coordinator.applicationDidBecomeActive()
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(coordinator.page, .windows)
        XCTAssertEqual(coordinator.expectedGestureIdentifier, "DOWN-RIGHT")

        coordinator.finish()
        XCTAssertFalse(coordinator.shouldPresentOnLaunch)
        XCTAssertFalse(coordinator.isPresenting)
    }

    func testTutorialConfigurationIsTemporaryAndExcludesQuitApplication() throws {
        var source = AppConfiguration()
        source.edgeScrollOptions.enabled = true
        source.bindings.append(GestureBinding(
            gesture: "UP-LEFT",
            name: "退出当前应用",
            actions: [.init(type: .windowAction, value: WindowAction.quitApplication.rawValue)]
        ))
        let (coordinator, defaults, suiteName) = try makeCoordinator(configuration: source)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        coordinator.begin()
        let temporary = try XCTUnwrap(coordinator.configurationForCurrentContext)

        XCTAssertTrue(temporary.gestureOptions.enabled)
        XCTAssertFalse(temporary.edgeScrollOptions.enabled)
        XCTAssertFalse(temporary.bindings.contains { binding in
            binding.actions.contains {
                $0.type == .windowAction && $0.value == WindowAction.quitApplication.rawValue
            }
        })
        XCTAssertTrue(source.edgeScrollOptions.enabled)
        XCTAssertTrue(source.bindings.contains { $0.gesture == "UP-LEFT" })
    }

    func testClosingTutorialDoesNotMarkItCompleteForSystemRestart() throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        coordinator.begin()
        coordinator.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        XCTAssertFalse(coordinator.isPresenting)
        XCTAssertTrue(coordinator.shouldPresentOnLaunch)

        coordinator.begin()
        coordinator.skip()
        XCTAssertFalse(coordinator.shouldPresentOnLaunch)
    }

    func testPinnedImageLessonRequiresEveryInteractionAndUserClose() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        coordinator.begin()
        coordinator.nextFromWelcome()
        coordinator.skipCurrentScene()
        coordinator.skipCurrentScene()
        coordinator.skipCurrentScene()

        XCTAssertEqual(coordinator.page, .pinnedImage)
        XCTAssertEqual(coordinator.expectedGestureIdentifier, "SQUARE_CLOCKWISE")

        let firstID = UUID()
        coordinator.handlePinnedImageInteraction(id: firstID, event: .created)
        coordinator.handlePinnedImageInteraction(id: firstID, event: .closed)
        XCTAssertEqual(coordinator.expectedGestureIdentifier, "SQUARE_CLOCKWISE")

        let id = UUID()
        coordinator.handlePinnedImageInteraction(id: id, event: .created)
        XCTAssertNil(coordinator.expectedGestureIdentifier)
        coordinator.handlePinnedImageInteraction(id: id, event: .moved)
        XCTAssertTrue(coordinator.completedPinnedImageSteps.contains(.drag))
        coordinator.handlePinnedImageInteraction(id: id, event: .collapsed)
        XCTAssertTrue(coordinator.completedPinnedImageSteps.contains(.collapse))
        coordinator.handlePinnedImageInteraction(id: id, event: .savedAs)
        XCTAssertTrue(coordinator.completedPinnedImageSteps.contains(.saveAs))
        coordinator.handlePinnedImageInteraction(id: id, event: .expanded)
        coordinator.handlePinnedImageInteraction(id: id, event: .opacityAdjusted)
        coordinator.handlePinnedImageInteraction(id: id, event: .copied)

        XCTAssertEqual(coordinator.page, .pinnedImage)
        XCTAssertTrue(coordinator.feedback?.contains("右键关闭") == true)
        coordinator.handlePinnedImageInteraction(id: id, event: .closed)
        try await Task.sleep(for: .milliseconds(800))

        XCTAssertEqual(coordinator.page, .ocr)
        XCTAssertEqual(coordinator.expectedGestureIdentifier, "SQUARE_COUNTERCLOCKWISE")
        XCTAssertEqual(
            coordinator.completedPinnedImageSteps,
            Set(PinnedImageTutorialStep.allCases)
        )
    }

    func testRectanglePreviewsStartAtRequestedTopCorners() throws {
        let clockwise = try XCTUnwrap(
            GesturePreview.rectanglePreviewPoints(for: "SQUARE_CLOCKWISE")
        )
        let counterclockwise = try XCTUnwrap(
            GesturePreview.rectanglePreviewPoints(for: "SQUARE_COUNTERCLOCKWISE")
        )

        XCTAssertEqual(clockwise.first, CGPoint(x: 1, y: 1))
        XCTAssertEqual(clockwise[1], CGPoint(x: 1, y: 0))
        XCTAssertEqual(counterclockwise.first, CGPoint(x: 0, y: 1))
        XCTAssertEqual(counterclockwise[1], CGPoint(x: 0, y: 0))
    }

    func testOCRRequiresCopiedNonemptyResult() async throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        coordinator.begin()
        coordinator.nextFromWelcome()
        coordinator.skipCurrentScene()
        coordinator.skipCurrentScene()
        coordinator.skipCurrentScene()
        coordinator.skipCurrentScene()

        XCTAssertEqual(coordinator.page, .ocr)
        coordinator.handleOCRResult(.success(""))
        XCTAssertEqual(coordinator.page, .ocr)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TutorialCoordinator.ocrSample, forType: .string)
        coordinator.handleOCRResult(.success(TutorialCoordinator.ocrSample))
        try await Task.sleep(for: .milliseconds(1_100))

        XCTAssertEqual(coordinator.page, .finish)
        XCTAssertEqual(coordinator.recognizedText, TutorialCoordinator.ocrSample)
    }

    private func makeCoordinator(
        configuration: AppConfiguration = AppConfiguration()
    ) throws -> (TutorialCoordinator, UserDefaults, String) {
        let suiteName = "TutorialCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let coordinator = TutorialCoordinator(
            defaults: defaults,
            tutorialConfiguration: configuration,
            allowsHeadlessInteraction: true
        )
        return (coordinator, defaults, suiteName)
    }
}
