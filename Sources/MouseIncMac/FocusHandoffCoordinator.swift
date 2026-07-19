import AppKit
@preconcurrency import ApplicationServices

/// After MouseTrails closes the last visible window of an application, macOS
/// can leave its menu-bar focus on that now-closed application.  This restores
/// focus to the normal window directly behind it.
@MainActor
enum FocusHandoffCoordinator {
    struct Snapshot: Sendable {
        let closingProcessIdentifier: pid_t
        let closingWindowNumber: Int
        let candidateProcessIdentifier: pid_t
        let candidateWindowNumber: Int?
    }

    static func snapshot(closing window: AXUIElement) -> Snapshot? {
        var closingPID: pid_t = 0
        guard AXUIElementGetPid(window, &closingPID) == .success else { return nil }

        let closingFrame = frame(of: window)
        let windows = onscreenWindows()
        let closingNumber = windowNumber(of: window)
            ?? windows.first(where: { listedWindow in
                listedWindow.ownerPID == closingPID
                    && closingFrame.map { frame in
                        let overlap = frame.intersection(listedWindow.bounds)
                        return !overlap.isNull && overlap.width > 0 && overlap.height > 0
                    } == true
            })?.number
        guard let closingNumber else {
            DiagnosticLogger.shared.log(
                "Focus handoff snapshot unavailable: closing window could not be mapped; pid=\(closingPID)"
            )
            return nil
        }

        return snapshot(
            closingProcessIdentifier: closingPID,
            closingWindowNumber: closingNumber,
            closingFrame: closingFrame,
            windows: windows
        )
    }

    /// Close-all commands can make AXFocusedWindow unavailable before the
    /// command is dispatched.  Capture the topmost normal window belonging to
    /// the same process directly from the compositor in that case.
    static func snapshot(closingProcessIdentifier processIdentifier: pid_t) -> Snapshot? {
        let windows = onscreenWindows()
        guard let closingWindow = windows.first(where: {
            $0.ownerPID == processIdentifier
                && $0.layer == 0
                && $0.alpha > 0
                && $0.bounds.width > 40
                && $0.bounds.height > 40
        }) else {
            DiagnosticLogger.shared.log(
                "Focus handoff snapshot has no visible source window; pid=\(processIdentifier)"
            )
            return nil
        }
        return snapshot(
            closingProcessIdentifier: processIdentifier,
            closingWindowNumber: closingWindow.number,
            closingFrame: closingWindow.bounds,
            windows: windows
        )
    }

    private static func snapshot(
        closingProcessIdentifier closingPID: pid_t,
        closingWindowNumber closingNumber: Int,
        closingFrame: CGRect?,
        windows: [ListedWindow]
    ) -> Snapshot? {

        guard let closingIndex = windows.firstIndex(where: { $0.number == closingNumber }) else {
            DiagnosticLogger.shared.log(
                "Focus handoff snapshot unavailable: closing window is not on screen; pid=\(closingPID)"
            )
            return nil
        }

        let candidateStart = windows.index(after: closingIndex)
        guard candidateStart < windows.endIndex else {
            return finderFallbackSnapshot(
                closingProcessIdentifier: closingPID,
                closingWindowNumber: closingNumber
            )
        }

        let candidates = windows[candidateStart...].filter {
            $0.ownerPID != closingPID
                && $0.layer == 0
                && $0.alpha > 0
                && $0.bounds.width > 40
                && $0.bounds.height > 40
                && $0.ownerPID != NSRunningApplication.current.processIdentifier
        }
        let candidate = candidates.sorted { left, right in
            let leftOverlap = closingFrame.map { $0.intersects(left.bounds) } ?? false
            let rightOverlap = closingFrame.map { $0.intersects(right.bounds) } ?? false
            if leftOverlap != rightOverlap { return leftOverlap }
            return false
        }.first
        guard let candidate else {
            return finderFallbackSnapshot(
                closingProcessIdentifier: closingPID,
                closingWindowNumber: closingNumber
            )
        }

        return Snapshot(
            closingProcessIdentifier: closingPID,
            closingWindowNumber: closingNumber,
            candidateProcessIdentifier: candidate.ownerPID,
            candidateWindowNumber: candidate.number
        )
    }

    private static func finderFallbackSnapshot(
        closingProcessIdentifier: pid_t,
        closingWindowNumber: Int
    ) -> Snapshot? {
        guard let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first else {
            DiagnosticLogger.shared.log(
                "Focus handoff snapshot has no eligible candidate or Finder fallback; " +
                "pid=\(closingProcessIdentifier)"
            )
            return nil
        }
        DiagnosticLogger.shared.log(
            "Focus handoff selected Finder desktop fallback; pid=\(closingProcessIdentifier)"
        )
        return Snapshot(
            closingProcessIdentifier: closingProcessIdentifier,
            closingWindowNumber: closingWindowNumber,
            candidateProcessIdentifier: finder.processIdentifier,
            candidateWindowNumber: nil
        )
    }

    static func scheduleIfNeeded(_ snapshot: Snapshot?) {
        guard let snapshot else { return }
        Task { @MainActor in
            for delay in [50_000_000, 120_000_000, 250_000_000, 500_000_000, 800_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delay))
                guard !Task.isCancelled else { return }
                if onscreenWindows().contains(where: { $0.number == snapshot.closingWindowNumber }) {
                    continue
                }
                guard !hasVisibleNormalWindow(processIdentifier: snapshot.closingProcessIdentifier) else {
                    return
                }
                activate(snapshot)
                return
            }
        }
    }

    /// Batch-close animations can remove windows one at a time.  Unlike the
    /// single-window path, keep observing intermediate states until the source
    /// application has remained windowless for two consecutive samples.
    static func scheduleAfterClosingAll(_ snapshot: Snapshot?) {
        guard let snapshot else { return }
        Task { @MainActor in
            var consecutiveWindowlessSamples = 0
            let delays: [UInt64] = [
                50_000_000,
                100_000_000,
                150_000_000,
                200_000_000,
                300_000_000,
                500_000_000,
                800_000_000,
                1_000_000_000
            ]
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }

                if hasVisibleNormalWindow(processIdentifier: snapshot.closingProcessIdentifier) {
                    consecutiveWindowlessSamples = 0
                    continue
                }
                consecutiveWindowlessSamples += 1
                guard consecutiveWindowlessSamples >= 2 else { continue }

                if let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                   frontmostPID != snapshot.closingProcessIdentifier {
                    DiagnosticLogger.shared.log(
                        "Focus handoff skipped: user focus changed during close-all; " +
                        "fromPID=\(snapshot.closingProcessIdentifier); currentPID=\(frontmostPID)"
                    )
                    return
                }
                activate(snapshot)
                return
            }
            DiagnosticLogger.shared.log(
                "Focus handoff timed out: source windows remained during close-all; " +
                "pid=\(snapshot.closingProcessIdentifier)"
            )
        }
    }

    private static func activate(_ snapshot: Snapshot) {
        guard let application = NSRunningApplication(
            processIdentifier: snapshot.candidateProcessIdentifier
        ) else {
            DiagnosticLogger.shared.log(
                "Focus handoff failed: candidate process is no longer running; pid=\(snapshot.candidateProcessIdentifier)"
            )
            return
        }

        _ = application.activate(options: [])
        let applicationElement = AXUIElementCreateApplication(snapshot.candidateProcessIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 0.3)
        _ = AXUIElementSetAttributeValue(
            applicationElement,
            kAXFrontmostAttribute as CFString,
            true as CFBoolean
        )
        if let candidateWindowNumber = snapshot.candidateWindowNumber,
           let window = windowElement(
               processIdentifier: snapshot.candidateProcessIdentifier,
               number: candidateWindowNumber
           ) {
            _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        DiagnosticLogger.shared.log(
            "Focus handoff requested; fromPID=\(snapshot.closingProcessIdentifier); " +
            "toPID=\(snapshot.candidateProcessIdentifier)"
        )
    }

    private struct ListedWindow {
        let number: Int
        let ownerPID: pid_t
        let layer: Int
        let alpha: Double
        let bounds: CGRect
    }

    private static func onscreenWindows() -> [ListedWindow] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return raw.compactMap { dictionary in
            guard
                let number = dictionary[kCGWindowNumber as String] as? NSNumber,
                let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                let layer = dictionary[kCGWindowLayer as String] as? NSNumber,
                let rawBounds = dictionary[kCGWindowBounds as String]
            else { return nil }
            let boundsDictionary = rawBounds as! CFDictionary
            guard let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
            let alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return ListedWindow(
                number: number.intValue,
                ownerPID: pid_t(ownerPID.int32Value),
                layer: layer.intValue,
                alpha: alpha,
                bounds: bounds
            )
        }
    }

    private static func hasVisibleNormalWindow(processIdentifier: pid_t) -> Bool {
        onscreenWindows().contains {
            $0.ownerPID == processIdentifier
                && $0.layer == 0
                && $0.alpha > 0
                && $0.bounds.width > 40
                && $0.bounds.height > 40
        }
    }

    private static func windowElement(processIdentifier: pid_t, number: Int) -> AXUIElement? {
        let application = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [Any]
        else { return nil }
        return windows.compactMap { value -> AXUIElement? in
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
        }.first { windowNumber(of: $0) == number }
    }

    private static func windowNumber(of window: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &value) == .success,
            let number = value as? NSNumber
        else { return nil }
        return number.intValue
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionValue,
            let sizeValue,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        let positionAX = unsafeDowncast(positionValue, to: AXValue.self)
        let sizeAX = unsafeDowncast(sizeValue, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionAX, .cgPoint, &position),
            AXValueGetValue(sizeAX, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }
}
