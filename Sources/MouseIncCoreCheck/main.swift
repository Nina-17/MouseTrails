import Foundation
import MouseIncCore

private enum CheckFailure: Error, CustomStringConvertible {
    case mismatch(name: String, expected: String?, actual: String?)
    case assertion(name: String, detail: String)

    var description: String {
        switch self {
        case let .mismatch(name, expected, actual):
            return "\(name): expected \(expected ?? "nil"), got \(actual ?? "nil")"
        case let .assertion(name, detail):
            return "\(name): \(detail)"
        }
    }
}

private func check(_ name: String, _ actual: String?, equals expected: String?) throws {
    guard actual == expected else {
        throw CheckFailure.mismatch(name: name, expected: expected, actual: actual)
    }
}

private func check(_ name: String, _ condition: @autoclosure () -> Bool, _ detail: String) throws {
    guard condition() else {
        throw CheckFailure.assertion(name: name, detail: detail)
    }
}

private func runChecks() throws {
    let recognizer = GestureRecognizer(
        simplificationTolerance: 5,
        minimumGestureLength: 20
    )

    try check("up", recognizer.recognize([.init(x: 0, y: 0), .init(x: 0, y: 100)]), equals: "UP")
    try check("down", recognizer.recognize([.init(x: 0, y: 100), .init(x: 0, y: 0)]), equals: "DOWN")
    try check("left", recognizer.recognize([.init(x: 100, y: 0), .init(x: 0, y: 0)]), equals: "LEFT")
    try check("right", recognizer.recognize([.init(x: 0, y: 0), .init(x: 100, y: 0)]), equals: "RIGHT")

    let corner = [
        CGPoint(x: 0, y: 100),
        CGPoint(x: 0, y: 50),
        CGPoint(x: 0, y: 0),
        CGPoint(x: 50, y: 0),
        CGPoint(x: 100, y: 0)
    ]
    try check("corner", recognizer.recognize(corner), equals: "DOWN-RIGHT")
    try check("tiny", recognizer.recognize([.init(x: 0, y: 0), .init(x: 3, y: 2)]), equals: nil)

    let global = GestureBinding(
        gesture: "UP",
        name: "Global",
        actions: [.init(type: .keyStroke, value: "Command+C")]
    )
    let safari = GestureBinding(
        gesture: "UP",
        name: "Safari",
        bundleIdentifiers: ["com.apple.Safari"],
        actions: [.init(type: .keyStroke, value: "Command+L")]
    )
    let configuration = AppConfiguration(bindings: [global, safari])
    guard configuration.binding(for: "UP", bundleIdentifier: "com.apple.Safari") == safari else {
        throw CheckFailure.mismatch(name: "specific binding", expected: "Safari", actual: nil)
    }
    guard configuration.binding(for: "UP", bundleIdentifier: "com.apple.TextEdit") == global else {
        throw CheckFailure.mismatch(name: "global binding", expected: "Global", actual: nil)
    }

    let encoded = try JSONEncoder().encode(configuration)
    let decoded = try JSONDecoder().decode(AppConfiguration.self, from: encoded)
    guard decoded == configuration else {
        throw CheckFailure.mismatch(name: "configuration round trip", expected: "equal", actual: "different")
    }

    try runGestureSessionChecks()
}

private func runGestureSessionChecks() throws {
    let settings = GestureSession.Settings(startDistance: 10, maximumDuration: 5)
    let replay = GestureSession.ReplayContext(
        quartzPoint: CGPoint(x: 20, y: 30),
        flags: [.maskControl],
        clickState: 2
    )

    var shortClick = GestureSession()
    shortClick.begin(
        quartzPoint: replay.quartzPoint,
        appKitPoint: CGPoint(x: 100, y: 100),
        targetBundleIdentifier: "com.example.Target",
        replayFlags: replay.flags,
        replayClickState: replay.clickState,
        settings: settings,
        now: 10
    )
    try check(
        "short click replay",
        shortClick.finish(at: 11) == .replay(replay),
        "a sub-threshold secondary click was not replayed"
    )

    var gesture = GestureSession()
    gesture.begin(
        quartzPoint: .zero,
        appKitPoint: CGPoint(x: 100, y: 100),
        targetBundleIdentifier: "com.example.Target",
        replayFlags: [],
        replayClickState: 1,
        settings: settings,
        now: 20
    )
    try check(
        "gesture threshold",
        gesture.recordDelta(deltaX: 6, deltaY: 8, now: 21) == .gestureStarted,
        "a 10-point HID delta did not start a gesture"
    )
    guard case let .recognize(points, target) = gesture.finish(at: 22) else {
        throw CheckFailure.assertion(name: "gesture finish", detail: "gesture was not sent for recognition")
    }
    try check("gesture target", target == "com.example.Target", "frontmost application was not preserved")
    try check(
        "delta coordinate conversion",
        points.last == CGPoint(x: 106, y: 92),
        "Quartz deltaY was not converted to AppKit coordinates"
    )

    var timeoutBeforeThreshold = GestureSession()
    timeoutBeforeThreshold.begin(
        quartzPoint: replay.quartzPoint,
        appKitPoint: .zero,
        targetBundleIdentifier: nil,
        replayFlags: replay.flags,
        replayClickState: replay.clickState,
        settings: settings,
        now: 30
    )
    try check(
        "timeout before threshold",
        timeoutBeforeThreshold.expire(at: 35) == .expired(replayOnMouseUp: true),
        "timeout before threshold should preserve the regular right click"
    )
    try check(
        "timeout replay",
        timeoutBeforeThreshold.finish(at: 36) == .replay(replay),
        "timed-out short click was not replayed"
    )

    var timeoutAfterThreshold = GestureSession()
    timeoutAfterThreshold.begin(
        quartzPoint: .zero,
        appKitPoint: .zero,
        targetBundleIdentifier: nil,
        replayFlags: [],
        replayClickState: 1,
        settings: settings,
        now: 40
    )
    _ = timeoutAfterThreshold.recordDelta(deltaX: 10, deltaY: 0, now: 41)
    try check(
        "timeout after threshold",
        timeoutAfterThreshold.expire(at: 45) == .expired(replayOnMouseUp: false),
        "gesture timeout should not schedule a context menu"
    )
    try check(
        "timeout cancellation",
        timeoutAfterThreshold.finish(at: 46) == .cancelled,
        "timed-out gesture unexpectedly replayed a right click"
    )

    var fractional = GestureSession()
    fractional.begin(
        quartzPoint: .zero,
        appKitPoint: .zero,
        targetBundleIdentifier: nil,
        replayFlags: [],
        replayClickState: 1,
        settings: .init(startDistance: 1, maximumDuration: 5),
        now: 50
    )
    for index in 1 ... 6 {
        _ = fractional.recordDelta(
            deltaX: 0.2,
            deltaY: 0.2,
            now: 50 + Double(index) * 0.1
        )
    }
    try check(
        "fractional delta accumulation",
        fractional.phase == .gesture,
        "sub-point HID deltas were discarded instead of accumulated"
    )
}

do {
    try runChecks()
    print("MouseIncCore checks passed")
} catch {
    FileHandle.standardError.write(Data("MouseIncCore checks failed: \(error)\n".utf8))
    exit(1)
}
