import CoreGraphics
import XCTest
@testable import MouseIncCore

final class GestureSessionTests: XCTestCase {
    private let settings = GestureSession.Settings(
        startDistance: 10,
        maximumDuration: 5
    )

    func testShortClickReplaysOriginalSecondaryClick() {
        var session = GestureSession()
        let expected = GestureSession.ReplayContext(
            quartzPoint: CGPoint(x: 20, y: 30),
            flags: [.maskControl, .maskShift],
            clickState: 2
        )
        begin(&session, replay: expected, now: 100)

        XCTAssertEqual(session.finish(at: 101), .replay(expected))
        XCTAssertEqual(session.phase, .idle)
        XCTAssertFalse(session.isActive)
    }

    func testCrossingThresholdRecognizesAndInvertsQuartzDeltaY() throws {
        var session = GestureSession()
        begin(&session, appKitPoint: CGPoint(x: 100, y: 100), now: 10)

        XCTAssertEqual(
            session.recordDelta(deltaX: 6, deltaY: 8, now: 11),
            .gestureStarted
        )
        XCTAssertEqual(session.phase, .gesture)

        let result = session.finish(at: 12)
        guard case let .recognize(points, targetBundleIdentifier) = result else {
            return XCTFail("Expected recognition, got \(result)")
        }
        XCTAssertEqual(targetBundleIdentifier, "com.example.Target")
        XCTAssertEqual(points.first, CGPoint(x: 100, y: 100))
        XCTAssertEqual(points.last, CGPoint(x: 106, y: 92))
    }

    func testTimeoutBeforeThresholdReplaysOnMouseUp() {
        var session = GestureSession()
        let replay = GestureSession.ReplayContext(
            quartzPoint: CGPoint(x: 3, y: 4),
            flags: .maskCommand,
            clickState: 1
        )
        begin(&session, replay: replay, now: 20)

        XCTAssertEqual(session.expire(at: 25), .expired(replayOnMouseUp: true))
        XCTAssertEqual(session.phase, .timedOut(replayOnMouseUp: true))
        XCTAssertEqual(session.finish(at: 26), .replay(replay))
    }

    func testTimeoutAfterThresholdCancelsWithoutReplay() {
        var session = GestureSession()
        begin(&session, now: 30)
        XCTAssertEqual(
            session.recordDelta(deltaX: 10, deltaY: 0, now: 31),
            .gestureStarted
        )

        XCTAssertEqual(session.expire(at: 35), .expired(replayOnMouseUp: false))
        XCTAssertEqual(session.phase, .timedOut(replayOnMouseUp: false))
        XCTAssertEqual(session.finish(at: 36), .cancelled)
    }

    func testFractionalDeltasAccumulateBeforeSampling() throws {
        var session = GestureSession()
        let fractionalSettings = GestureSession.Settings(
            startDistance: 1,
            maximumDuration: 5
        )
        begin(&session, settings: fractionalSettings, now: 40)

        for index in 1 ... 6 {
            _ = session.recordDelta(
                deltaX: 0.2,
                deltaY: 0.2,
                now: 40 + Double(index) * 0.1
            )
        }

        XCTAssertEqual(session.phase, .gesture)
        let lastPoint = try XCTUnwrap(session.points.last)
        XCTAssertEqual(lastPoint.x, CGFloat(1.2), accuracy: 0.000_001)
        XCTAssertEqual(lastPoint.y, CGFloat(-1.2), accuracy: 0.000_001)
    }

    func testResetAndMissingSessionPassThrough() {
        var session = GestureSession()

        XCTAssertEqual(
            session.recordDelta(deltaX: 20, deltaY: 20, now: 1),
            .passthrough
        )
        XCTAssertEqual(session.expire(at: 1), .inactive)
        XCTAssertEqual(session.finish(at: 1), .passthrough)

        begin(&session, now: 50)
        XCTAssertTrue(session.isActive)
        session.reset()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(session.points, [])
        XCTAssertEqual(session.finish(at: 51), .passthrough)
    }

    private func begin(
        _ session: inout GestureSession,
        appKitPoint: CGPoint = .zero,
        replay: GestureSession.ReplayContext = GestureSession.ReplayContext(
            quartzPoint: .zero,
            flags: [],
            clickState: 1
        ),
        settings: GestureSession.Settings? = nil,
        now: TimeInterval
    ) {
        session.begin(
            quartzPoint: replay.quartzPoint,
            appKitPoint: appKitPoint,
            targetBundleIdentifier: "com.example.Target",
            replayFlags: replay.flags,
            replayClickState: replay.clickState,
            settings: settings ?? self.settings,
            now: now
        )
    }
}
