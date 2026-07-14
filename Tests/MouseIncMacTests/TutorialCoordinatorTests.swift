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
        var persistedConfiguration: AppConfiguration?
        coordinator.persistCustomSearchGesture = { definition, binding in
            persistedConfiguration = TutorialCoordinator.installingSearchGesture(
                definition,
                binding: binding,
                in: AppConfiguration()
            )
        }

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
        XCTAssertTrue(coordinator.isPreparingCustomSearchGesture)
        XCTAssertNil(coordinator.expectedGestureIdentifier)

        coordinator.startCustomSearchGestureRecording()
        let sample = [
            CGPoint(x: 100, y: 100), CGPoint(x: 25, y: 92),
            CGPoint(x: 5, y: 72), CGPoint(x: 52, y: 50),
            CGPoint(x: 96, y: 30), CGPoint(x: 72, y: 8), CGPoint(x: 0, y: 0)
        ]
        XCTAssertTrue(coordinator.customGestureRecorder.consume(points: sample))
        XCTAssertTrue(coordinator.customGestureRecorder.consume(points: sample.map {
            CGPoint(x: $0.x * 1.05, y: $0.y * 0.95)
        }))
        XCTAssertTrue(coordinator.customGestureRecorder.consume(points: sample.map {
            CGPoint(x: $0.x + 18, y: $0.y - 12)
        }))

        let customSearchGesture = try XCTUnwrap(coordinator.expectedGestureIdentifier)
        XCTAssertTrue(customSearchGesture.hasPrefix(TutorialCoordinator.tutorialSearchGesturePrefix))
        XCTAssertEqual(coordinator.handleRecognizedGesture("SQUARE_CLOCKWISE"), .consume)
        XCTAssertEqual(persistedConfiguration?.customGestures.first?.identifier, customSearchGesture)
        XCTAssertEqual(
            persistedConfiguration?.binding(for: customSearchGesture, bundleIdentifier: nil)?.actions.first?.type,
            .searchSelectedText
        )

        XCTAssertEqual(coordinator.handleRecognizedGesture(customSearchGesture), .execute)
        XCTAssertNil(coordinator.configurationForCurrentContext)
        coordinator.applicationDidBecomeActive()
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(coordinator.page, .windows)
        XCTAssertEqual(coordinator.expectedGestureIdentifier, "DOWN-RIGHT")

        coordinator.finish()
        XCTAssertFalse(coordinator.shouldPresentOnLaunch)
        XCTAssertFalse(coordinator.isPresenting)
    }

    func testInstallingTutorialSearchGestureReplacesOnlyTutorialAndLegacySearchBindings() throws {
        let oldTutorial = try CustomGestureTrainer.train(
            identifier: "CUSTOM_TUTORIAL_SEARCH_OLD",
            name: "旧教程搜索",
            rawSamples: Array(repeating: [
                CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 80), CGPoint(x: 100, y: 0)
            ], count: 3)
        ).definition
        let manual = try CustomGestureTrainer.train(
            identifier: "CUSTOM_MANUAL",
            name: "用户手势",
            rawSamples: Array(repeating: [
                CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 100), CGPoint(x: 100, y: 20)
            ], count: 3)
        ).definition
        let replacement = try CustomGestureTrainer.train(
            identifier: "CUSTOM_TUTORIAL_SEARCH_NEW",
            name: "搜索选中文字",
            rawSamples: Array(repeating: [
                CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 70),
                CGPoint(x: 100, y: 30), CGPoint(x: 0, y: 0)
            ], count: 3)
        ).definition
        let source = AppConfiguration(
            customGestures: [oldTutorial, manual],
            bindings: [
                GestureBinding(
                    gesture: oldTutorial.identifier,
                    name: "旧教程搜索",
                    actions: [.init(type: .searchSelectedText, value: "https://example.com?q={query}")]
                ),
                GestureBinding(
                    gesture: manual.identifier,
                    name: "用户手势",
                    actions: [.init(type: .keyStroke, value: "Command+C")]
                ),
                GestureBinding(
                    gesture: "LETTER_S",
                    name: "旧内置搜索",
                    actions: [.init(type: .searchSelectedText, value: "https://example.com?q={query}")]
                )
            ]
        )
        let binding = GestureBinding(
            gesture: replacement.identifier,
            name: "搜索选中文字",
            actions: [.init(type: .searchSelectedText, value: "https://www.google.com/search?q={query}")]
        )

        let installed = TutorialCoordinator.installingSearchGesture(
            replacement,
            binding: binding,
            in: source
        )

        XCTAssertEqual(
            Set(installed.customGestures.map(\.identifier)),
            Set([manual.identifier, replacement.identifier])
        )
        XCTAssertNotNil(installed.binding(for: manual.identifier, bundleIdentifier: nil))
        XCTAssertNotNil(installed.binding(for: replacement.identifier, bundleIdentifier: nil))
        XCTAssertNil(installed.binding(for: "LETTER_S", bundleIdentifier: nil))
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

        XCTAssertEqual(coordinator.page, .edgeScroll)
        XCTAssertEqual(coordinator.recognizedText, TutorialCoordinator.ocrSample)

        let edgeConfiguration = try XCTUnwrap(coordinator.configurationForCurrentContext)
        XCTAssertTrue(edgeConfiguration.edgeScrollOptions.enabled)
        coordinator.handleEdgeScroll(.left)
        XCTAssertEqual(coordinator.completedEdgeScrollSteps, [.brightness])
        XCTAssertEqual(coordinator.page, .edgeScroll)
        coordinator.handleEdgeScroll(.right)
        XCTAssertEqual(
            coordinator.completedEdgeScrollSteps,
            Set(EdgeScrollTutorialStep.allCases)
        )
        try await Task.sleep(for: .milliseconds(1_100))

        XCTAssertEqual(coordinator.page, .finish)
        let finishConfiguration = try XCTUnwrap(coordinator.configurationForCurrentContext)
        XCTAssertFalse(finishConfiguration.edgeScrollOptions.enabled)
    }

    func testEdgeScrollLessonIgnoresUnsupportedAndRepeatedEdges() throws {
        let (coordinator, defaults, suiteName) = try makeCoordinator()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        coordinator.begin()
        coordinator.nextFromWelcome()
        coordinator.skipCurrentScene()
        coordinator.skipCurrentScene()
        coordinator.skipCurrentScene()
        coordinator.skipCurrentScene()
        coordinator.skipCurrentScene()

        XCTAssertEqual(coordinator.page, .edgeScroll)
        coordinator.handleEdgeScroll(.top)
        coordinator.handleEdgeScroll(.bottom)
        XCTAssertTrue(coordinator.completedEdgeScrollSteps.isEmpty)

        coordinator.handleEdgeScroll(.right)
        let completedCount = coordinator.completedGestureCount
        coordinator.handleEdgeScroll(.right)
        XCTAssertEqual(coordinator.completedGestureCount, completedCount)
        XCTAssertEqual(coordinator.completedEdgeScrollSteps, [.volume])
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
