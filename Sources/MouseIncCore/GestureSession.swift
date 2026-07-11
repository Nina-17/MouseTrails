import CoreGraphics
import Foundation

/// Input-source-agnostic state for one secondary-click gesture.
///
/// Both a mouse and a trackpad arrive here as right-button events. Pointer
/// movement is reconstructed from HID deltas because the cursor location can
/// remain pinned while the event tap is suppressing a right-button drag.
package struct GestureSession {
    package enum Phase: Equatable {
        case idle
        case tracking
        case gesture
        case timedOut(replayOnMouseUp: Bool)
    }

    package struct Settings: Equatable {
        package var startDistance: CGFloat
        package var maximumDuration: TimeInterval

        package init(startDistance: Double, maximumDuration: TimeInterval) {
            self.startDistance = max(0, CGFloat(startDistance))
            self.maximumDuration = max(0, maximumDuration)
        }
    }

    package struct ReplayContext: Equatable {
        package var quartzPoint: CGPoint
        package var flags: CGEventFlags
        package var clickState: Int64

        package init(quartzPoint: CGPoint, flags: CGEventFlags, clickState: Int64) {
            self.quartzPoint = quartzPoint
            self.flags = flags
            self.clickState = clickState
        }
    }

    package enum DragResult: Equatable {
        case passthrough
        case tracking
        case gestureStarted
        case gestureUpdated
        case timedOut(replayOnMouseUp: Bool, newlyExpired: Bool)
    }

    package enum TimeoutResult: Equatable {
        case inactive
        case pending(remaining: TimeInterval)
        case expired(replayOnMouseUp: Bool)
        case alreadyExpired(replayOnMouseUp: Bool)
    }

    package enum FinishResult: Equatable {
        case passthrough
        case replay(ReplayContext)
        case recognize(points: [CGPoint], targetBundleIdentifier: String?)
        case cancelled
    }

    private struct Context {
        var replay: ReplayContext
        var targetBundleIdentifier: String?
        var points: [CGPoint]
        var currentPoint: CGPoint
        var startedAt: TimeInterval
        var settings: Settings
    }

    package private(set) var phase: Phase = .idle
    private var context: Context?

    package var isActive: Bool {
        phase != .idle
    }

    package var points: [CGPoint] {
        context?.points ?? []
    }

    package init() {}

    package mutating func begin(
        quartzPoint: CGPoint,
        appKitPoint: CGPoint,
        targetBundleIdentifier: String?,
        replayFlags: CGEventFlags,
        replayClickState: Int64,
        settings: Settings,
        now: TimeInterval
    ) {
        context = Context(
            replay: ReplayContext(
                quartzPoint: quartzPoint,
                flags: replayFlags,
                clickState: replayClickState
            ),
            targetBundleIdentifier: targetBundleIdentifier,
            points: [appKitPoint],
            currentPoint: appKitPoint,
            startedAt: now,
            settings: settings
        )
        phase = .tracking
    }

    package mutating func recordDelta(
        deltaX: CGFloat,
        deltaY: CGFloat,
        now: TimeInterval
    ) -> DragResult {
        guard context != nil else { return .passthrough }

        switch expire(at: now) {
        case let .expired(replayOnMouseUp):
            return .timedOut(replayOnMouseUp: replayOnMouseUp, newlyExpired: true)
        case let .alreadyExpired(replayOnMouseUp):
            return .timedOut(replayOnMouseUp: replayOnMouseUp, newlyExpired: false)
        case .inactive:
            return .passthrough
        case .pending:
            break
        }

        guard deltaX != 0 || deltaY != 0, var context else {
            return phase == .gesture ? .gestureUpdated : .tracking
        }

        // Quartz deltaY grows downward while AppKit coordinates grow upward.
        // Always update currentPoint, even when the delta is too small to add a
        // rendered sample. This keeps sub-point HID deltas cumulative.
        context.currentPoint = CGPoint(
            x: context.currentPoint.x + deltaX,
            y: context.currentPoint.y - deltaY
        )

        if let lastPoint = context.points.last,
           hypot(
               context.currentPoint.x - lastPoint.x,
               context.currentPoint.y - lastPoint.y
           ) >= 0.5 {
            context.points.append(context.currentPoint)
        }

        let firstPoint = context.points[0]
        let crossedThreshold = hypot(
            context.currentPoint.x - firstPoint.x,
            context.currentPoint.y - firstPoint.y
        ) >= context.settings.startDistance

        let startedGesture = phase == .tracking && crossedThreshold
        if startedGesture {
            if context.points.last != context.currentPoint {
                context.points.append(context.currentPoint)
            }
            phase = .gesture
        }

        self.context = context
        if startedGesture { return .gestureStarted }
        return phase == .gesture ? .gestureUpdated : .tracking
    }

    package mutating func expire(at now: TimeInterval) -> TimeoutResult {
        guard let context else { return .inactive }

        if case let .timedOut(replayOnMouseUp) = phase {
            return .alreadyExpired(replayOnMouseUp: replayOnMouseUp)
        }

        let elapsed = max(0, now - context.startedAt)
        let remaining = context.settings.maximumDuration - elapsed
        guard remaining <= 0 else {
            return .pending(remaining: remaining)
        }

        let replayOnMouseUp = phase == .tracking
        phase = .timedOut(replayOnMouseUp: replayOnMouseUp)
        return .expired(replayOnMouseUp: replayOnMouseUp)
    }

    package mutating func finish(at now: TimeInterval) -> FinishResult {
        guard var context else { return .passthrough }
        _ = expire(at: now)

        if context.points.last != context.currentPoint {
            context.points.append(context.currentPoint)
        }

        let result: FinishResult
        switch phase {
        case .idle:
            result = .passthrough
        case .tracking:
            result = .replay(context.replay)
        case .gesture:
            result = .recognize(
                points: context.points,
                targetBundleIdentifier: context.targetBundleIdentifier
            )
        case let .timedOut(replayOnMouseUp):
            result = replayOnMouseUp ? .replay(context.replay) : .cancelled
        }

        reset()
        return result
    }

    package mutating func reset() {
        phase = .idle
        context = nil
    }
}
