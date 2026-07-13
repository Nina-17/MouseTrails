import MouseIncCore
import XCTest
@testable import MouseIncMac

@MainActor
final class ActionExecutorTests: XCTestCase {
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


    func testCaptureActionUsesInjectedHandler() async throws {
        var receivedAction: CaptureAction?
        let executor = ActionExecutor(
            eventLogger: { _, _ in },
            windowActionHandler: { _ in true },
            captureActionHandler: { action in
                receivedAction = action
                return true
            }
        )

        executor.execute([.init(type: .captureAction, value: CaptureAction.pinRegion.rawValue)])
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(receivedAction, .pinRegion)
        XCTAssertFalse(executor.isExecuting)
    }

    private func makeExecutor() -> ActionExecutor {
        ActionExecutor(
            eventLogger: { _, _ in },
            windowActionHandler: { _ in true }
        )
    }
}
