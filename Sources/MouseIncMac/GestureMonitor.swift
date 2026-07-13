@preconcurrency import AppKit
import MouseIncCore
import OSLog

@MainActor
final class GestureMonitor: NSObject {
    enum StartResult {
        case started
        case eventTapCreationFailed
    }

    private static let replayMarker: Int64 = 0x4D49_4E43
    private let logger = Logger(subsystem: "com.mason.mouseincmac", category: "GestureMonitor")

    private let configurationProvider: () -> AppConfiguration
    private let overlay: GestureOverlay
    private let executor: ActionExecutor
    private let edgeScrollController: EdgeScrollController
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var session = GestureSession()
    private var timeoutTask: Task<Void, Never>?
    private var didLogDrag = false
    private var edgeCooldown = EdgeScrollCooldown()

    var onGesture: ((String) -> Void)?

    var isRunning: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    init(
        configuration: @escaping () -> AppConfiguration,
        overlay: GestureOverlay,
        executor: ActionExecutor,
        edgeScrollController: EdgeScrollController = EdgeScrollController()
    ) {
        configurationProvider = configuration
        self.overlay = overlay
        self.executor = executor
        self.edgeScrollController = edgeScrollController
        super.init()
    }

    deinit {
        timeoutTask?.cancel()
    }

    func start() -> StartResult {
        if let eventTap {
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                clearSession()
                CGEvent.tapEnable(tap: eventTap, enable: true)
                DiagnosticLogger.shared.log("Existing HID event tap was re-enabled")
            }
            return .started
        }
        DiagnosticLogger.shared.log(
            "Starting HID event tap; accessibility=\(AccessibilityPermission.isGranted), " +
            "postEvent=\(AccessibilityPermission.isPostEventGranted)"
        )

        let eventTypes: [CGEventType] = [.rightMouseDown, .rightMouseDragged, .rightMouseUp, .scrollWheel]
        let mask = eventTypes.reduce(CGEventMask(0)) { partial, eventType in
            partial | (CGEventMask(1) << CGEventMask(eventType.rawValue))
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: gestureEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("CGEvent tap creation failed")
            DiagnosticLogger.shared.log("CGEvent tap creation failed")
            return .eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        logger.info("Event tap started")
        DiagnosticLogger.shared.log("HID event tap started; enabled=\(CGEvent.tapIsEnabled(tap: tap))")
        return .started
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        executor.cancel()
        clearSession()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let previousPhase = session.phase
            clearSession()
            DiagnosticLogger.shared.log(
                "Event tap was disabled; type=\(type.rawValue); " +
                "clearedSession=\(previousPhase != .idle); re-enabling"
            )
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Replayed clicks are posted downstream at the session tap. The marker
        // is an additional guard in case macOS ever surfaces one back at HID.
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker {
            return Unmanaged.passUnretained(event)
        }

        let configuration = configurationProvider()
        let options = configuration.gestureOptions
        let now = ProcessInfo.processInfo.systemUptime

        switch type {
        case .scrollWheel:
            handleEdgeScroll(event: event, configuration: configuration, now: now)
            return Unmanaged.passUnretained(event)
        case .rightMouseDown:
            guard options.enabled else {
                clearSession()
                return Unmanaged.passUnretained(event)
            }

            clearSession()
            let settings = GestureSession.Settings(
                startDistance: options.startDistance,
                maximumDuration: options.maximumDuration
            )
            session.begin(
                quartzPoint: event.location,
                appKitPoint: NSEvent.mouseLocation,
                targetBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                replayFlags: event.flags,
                replayClickState: event.getIntegerValueField(.mouseEventClickState),
                settings: settings,
                now: now
            )
            didLogDrag = false
            scheduleTimeout(after: settings.maximumDuration)
            logger.debug("Right mouse button pressed")
            DiagnosticLogger.shared.log(
                "Right down at quartz=\(event.location), appKit=\(NSEvent.mouseLocation)"
            )
            return nil

        case .rightMouseDragged:
            guard session.isActive else {
                return Unmanaged.passUnretained(event)
            }

            let deltaX = CGFloat(event.getDoubleValueField(.mouseEventDeltaX))
            let deltaY = CGFloat(event.getDoubleValueField(.mouseEventDeltaY))
            if !didLogDrag {
                DiagnosticLogger.shared.log(
                    "First HID rightMouseDragged received; delta=(\(deltaX), \(deltaY)), " +
                    "eventLocation=\(event.location), globalLocation=\(NSEvent.mouseLocation)"
                )
                didLogDrag = true
            }

            let result = session.recordDelta(
                deltaX: deltaX,
                deltaY: deltaY,
                now: now
            )
            handleDragResult(result, showsTrail: options.showsTrail)
            return nil

        case .rightMouseUp:
            guard session.isActive else {
                return Unmanaged.passUnretained(event)
            }

            timeoutTask?.cancel()
            timeoutTask = nil
            overlay.hide()

            switch session.finish(at: now) {
            case .passthrough:
                didLogDrag = false
                return Unmanaged.passUnretained(event)

            case let .recognize(points, targetBundleIdentifier):
                let recognizer = GestureRecognizer(
                    simplificationTolerance: options.simplificationTolerance,
                    minimumGestureLength: options.minimumGestureLength
                )
                if let gesture = recognizer.recognize(points) {
                    if let binding = configuration.binding(
                        for: gesture,
                        bundleIdentifier: targetBundleIdentifier
                    ) {
                        executor.execute(
                            binding.actions,
                            options: configuration.actionSequenceOptions,
                            context: .init(gestureBounds: Self.boundingRect(of: points))
                        )
                        logger.info("Gesture matched: \(gesture, privacy: .public)")
                        DiagnosticLogger.shared.log("Gesture matched: \(gesture); action=\(binding.name)")
                        onGesture?("\(gesture) · \(binding.name)")
                    } else {
                        logger.info("Gesture has no binding: \(gesture, privacy: .public)")
                        DiagnosticLogger.shared.log("Gesture has no binding: \(gesture)")
                        if options.reportsFailures {
                            onGesture?("\(gesture) · 未绑定")
                        }
                    }
                } else {
                    logger.info("Gesture was not recognized")
                    DiagnosticLogger.shared.log("Gesture was not recognized; pointCount=\(points.count)")
                    if options.reportsFailures {
                        onGesture?("未识别")
                    }
                }

            case let .replay(replay):
                logger.debug("Replaying a regular right click")
                DiagnosticLogger.shared.log("Movement below threshold; replaying right click")
                replayRightClick(
                    at: replay.quartzPoint,
                    flags: replay.flags,
                    clickState: replay.clickState
                )

            case .cancelled:
                logger.debug("Timed-out gesture cancelled without replay")
            }

            didLogDrag = false
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleEdgeScroll(event: CGEvent, configuration: AppConfiguration, now: TimeInterval) {
        let options = configuration.edgeScrollOptions
        guard options.enabled, !session.isActive else { return }
        let lineDelta = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let pointDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let delta = pointDelta != 0 ? pointDelta : lineDelta
        guard delta != 0 else { return }
        let detector = EdgeScrollDetector(inset: options.inset)
        guard let edge = detector.edge(at: NSEvent.mouseLocation, in: NSScreen.screens.map(\.frame)),
              edge == .left || edge == .right else { return }
        edgeCooldown.interval = options.cooldown
        guard edgeCooldown.shouldFire(edge: edge, now: now) else { return }
        let succeeded = edgeScrollController.adjust(edge, by: delta > 0 ? 1 : -1, step: options.step)
        DiagnosticLogger.shared.log(
            "Edge scroll edge=\(edge.rawValue) delta=\(delta) adjusted=\(succeeded)"
        )
        if succeeded {
            onGesture?(edge == .left ? "边缘亮度" : "边缘音量")
        }
    }

    private static func boundingRect(of points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }

    private func replayRightClick(at point: CGPoint, flags: CGEventFlags, clickState: Int64) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        )
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        )
        down?.flags = flags
        up?.flags = flags
        down?.setIntegerValueField(.mouseEventClickState, value: clickState)
        up?.setIntegerValueField(.mouseEventClickState, value: clickState)
        down?.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        // Posting at the session tap is downstream from our HID event tap, so
        // a normal right click cannot start another gesture session.
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private func handleDragResult(_ result: GestureSession.DragResult, showsTrail: Bool) {
        switch result {
        case .passthrough, .tracking:
            break
        case .gestureStarted:
            DiagnosticLogger.shared.log("Gesture threshold crossed")
            updateOverlay(showsTrail: showsTrail)
        case .gestureUpdated:
            updateOverlay(showsTrail: showsTrail)
        case let .timedOut(replayOnMouseUp, newlyExpired):
            overlay.hide()
            if newlyExpired {
                logTimeout(replayOnMouseUp: replayOnMouseUp)
            }
        }
    }

    private func updateOverlay(showsTrail: Bool) {
        if showsTrail {
            overlay.show(points: session.points)
        } else {
            overlay.hide()
        }
    }

    private func scheduleTimeout(after duration: TimeInterval) {
        timeoutTask?.cancel()
        let nanoseconds = UInt64(min(max(0, duration), 86_400) * 1_000_000_000)
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.expireActiveSession()
        }
    }

    private func expireActiveSession() {
        switch session.expire(at: ProcessInfo.processInfo.systemUptime) {
        case let .expired(replayOnMouseUp):
            overlay.hide()
            logTimeout(replayOnMouseUp: replayOnMouseUp)
            timeoutTask = nil
        case let .pending(remaining):
            scheduleTimeout(after: remaining)
        case .inactive, .alreadyExpired:
            timeoutTask = nil
        }
    }

    private func logTimeout(replayOnMouseUp: Bool) {
        if replayOnMouseUp {
            logger.info("Gesture timed out before crossing threshold")
            DiagnosticLogger.shared.log(
                "Gesture timed out before threshold; regular right click will replay on mouse up"
            )
        } else {
            logger.info("Gesture timed out after crossing threshold")
            DiagnosticLogger.shared.log(
                "Gesture timed out after threshold; cancelling without right-click replay"
            )
        }
    }

    private func clearSession() {
        timeoutTask?.cancel()
        timeoutTask = nil
        overlay.hide()
        session.reset()
        didLogDrag = false
    }
}

private func gestureEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<GestureMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated {
        monitor.handle(type: type, event: event)
    }
}
