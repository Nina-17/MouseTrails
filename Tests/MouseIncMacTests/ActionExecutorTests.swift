import MouseIncCore
import XCTest
@testable import MouseIncMac

@MainActor
final class ActionExecutorTests: XCTestCase {
    func testOCRNotificationPreviewNormalizesAndTruncatesText() {
        XCTAssertEqual(
            UserNotificationCoordinator.previewText("第一行\n  第二行", limit: 20),
            "第一行 第二行"
        )
        XCTAssertEqual(
            UserNotificationCoordinator.previewText("123456789", limit: 5),
            "12345…"
        )
    }

    func testDelaySequenceCompletes() async throws {
        let executor = makeExecutor()

        executor.execute([.delay(seconds: 0.01)])
        XCTAssertTrue(executor.isExecuting)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(executor.isExecuting)
    }

    func testCancelStopsPendingDelay() async throws {
        let executor = makeExecutor()

        executor.execute([.delay(seconds: 1)])
        executor.cancel()

        XCTAssertFalse(executor.isExecuting)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(executor.isExecuting)
    }

    func testCancelPreviousRunsNewSequence() async throws {
        let executor = makeExecutor()
        let options = ActionSequenceOptions(interruptionPolicy: .cancelPrevious)

        executor.execute([.delay(seconds: 1)], options: options)
        executor.execute([.delay(seconds: 0.01)], options: options)

        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(executor.isExecuting)
    }

    func testIgnoreNewKeepsOriginalSequence() async throws {
        let executor = makeExecutor()
        let options = ActionSequenceOptions(interruptionPolicy: .ignoreNew)

        executor.execute([.delay(seconds: 0.05)], options: options)
        executor.execute([.delay(seconds: 1)], options: options)

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(executor.isExecuting)
    }

    func testInvalidDelayStopsSequence() async throws {
        let executor = makeExecutor()

        executor.execute(
            [.init(type: .delay, value: "invalid")],
            options: .init(failurePolicy: .stop)
        )

        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(executor.isExecuting)
    }

    func testWindowActionUsesInjectedHandler() async throws {
        var receivedAction: WindowAction?
        let executor = ActionExecutor(
            eventLogger: { _, _ in },
            windowActionHandler: { action in
                receivedAction = action
                return true
            }
        )

        executor.execute([.init(type: .windowAction, value: WindowAction.center.rawValue)])
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(receivedAction, .center)
        XCTAssertFalse(executor.isExecuting)
    }

    func testSystemViewActionUsesInjectedHandler() async throws {
        var receivedAction: SystemViewAction?
        var loggedEvents: [(DiagnosticEvent, [String: String])] = []
        let executor = ActionExecutor(
            eventLogger: { event, metadata in
                loggedEvents.append((event, metadata))
            },
            systemViewActionHandler: { action in
                receivedAction = action
                return true
            }
        )

        executor.execute([.init(
            type: .systemViewAction,
            value: SystemViewAction.missionControl.rawValue
        )])
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(receivedAction, .missionControl)
        let invocation = try XCTUnwrap(loggedEvents.first { $0.0 == .actionInvoked })
        XCTAssertEqual(invocation.1["type"], ActionDefinition.Kind.systemViewAction.rawValue)
        XCTAssertEqual(invocation.1["value"], SystemViewAction.missionControl.rawValue)
        XCTAssertEqual(invocation.1["accepted"], "true")
        XCTAssertFalse(executor.isExecuting)
    }

    func testRejectedWindowActionLogsRawValueAndFailure() async throws {
        var loggedEvents: [(DiagnosticEvent, [String: String])] = []
        let executor = ActionExecutor(
            eventLogger: { event, metadata in
                loggedEvents.append((event, metadata))
            },
            windowActionHandler: { _ in false }
        )

        executor.execute([.init(type: .windowAction, value: WindowAction.tileLeft.rawValue)])
        try await Task.sleep(nanoseconds: 20_000_000)

        let invocation = try XCTUnwrap(loggedEvents.first { $0.0 == .actionInvoked })
        XCTAssertEqual(invocation.1["type"], ActionDefinition.Kind.windowAction.rawValue)
        XCTAssertEqual(invocation.1["value"], WindowAction.tileLeft.rawValue)
        XCTAssertEqual(invocation.1["accepted"], "false")
        XCTAssertTrue(loggedEvents.contains { $0.0 == .actionFailed })
        XCTAssertFalse(executor.isExecuting)
    }


    func testCaptureActionUsesInjectedHandler() async throws {
        var receivedAction: CaptureAction?
        let executor = ActionExecutor(
            eventLogger: { _, _ in },
            windowActionHandler: { _ in true },
            captureActionHandler: { action, bounds in
                receivedAction = action
                XCTAssertEqual(bounds, CGRect(x: 10, y: 20, width: 30, height: 40))
                return true
            }
        )

        executor.execute(
            [.init(type: .captureAction, value: CaptureAction.pinRegion.rawValue)],
            context: .init(gestureBounds: CGRect(x: 10, y: 20, width: 30, height: 40))
        )
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(receivedAction, .pinRegion)
        XCTAssertFalse(executor.isExecuting)
    }

    func testOCRActionUsesInjectedHandler() async throws {
        var receivedAction: OCRAction?
        let expectedBounds = CGRect(x: 15, y: 25, width: 120, height: 80)
        let executor = ActionExecutor(
            eventLogger: { _, _ in },
            windowActionHandler: { _ in true },
            captureActionHandler: { _, _ in true },
            ocrActionHandler: { action, bounds in
                receivedAction = action
                XCTAssertEqual(bounds, expectedBounds)
                return true
            }
        )

        executor.execute(
            [.init(type: .ocrAction, value: OCRAction.recognizeRegion.rawValue)],
            context: .init(gestureBounds: expectedBounds)
        )
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(receivedAction, .recognizeRegion)
        XCTAssertFalse(executor.isExecuting)
    }

    func testCommandCCanBeHandledBySelectedPinnedImage() async throws {
        var receivedKeyStroke: ParsedKeyStroke?
        let executor = ActionExecutor(
            eventLogger: { _, _ in },
            keyStrokeHandler: { keyStroke in
                receivedKeyStroke = keyStroke
                return true
            }
        )

        executor.execute([.init(type: .keyStroke, value: "Command+C")])
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(
            receivedKeyStroke,
            ParsedKeyStroke(modifiers: [.command], key: "c")
        )
        XCTAssertFalse(executor.isExecuting)
    }

    private func makeExecutor() -> ActionExecutor {
        ActionExecutor(
            eventLogger: { _, _ in },
            windowActionHandler: { _ in true }
        )
    }
}
