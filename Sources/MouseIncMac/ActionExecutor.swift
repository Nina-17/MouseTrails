import AppKit
import MouseIncCore

@MainActor
final class ActionExecutor {
    struct ExecutionContext: Equatable, Sendable {
        var gestureBounds: CGRect?

        init(gestureBounds: CGRect? = nil) {
            self.gestureBounds = gestureBounds
        }
    }

    typealias EventLogger = @MainActor (DiagnosticEvent, [String: String]) -> Void
    typealias WindowActionHandler = @MainActor (WindowAction) -> Bool
    typealias CaptureActionHandler = @MainActor (CaptureAction, CGRect?) -> Bool
    typealias OCRActionHandler = @MainActor (OCRAction, CGRect?) -> Bool
    typealias SearchSelectedTextHandler = @MainActor (String) -> Bool
    typealias OpenFocusedApplicationPathHandler = @MainActor () -> Bool
    typealias KeyStrokeHandler = @MainActor (ParsedKeyStroke) -> Bool

    private var executionTask: Task<Void, Never>?
    private var activeExecutionID: UUID?
    private let eventLogger: EventLogger
    private let windowActionHandler: WindowActionHandler
    private let captureActionHandler: CaptureActionHandler
    private let ocrActionHandler: OCRActionHandler
    private let searchSelectedTextHandler: SearchSelectedTextHandler
    private let openFocusedApplicationPathHandler: OpenFocusedApplicationPathHandler
    private let keyStrokeHandler: KeyStrokeHandler

    init(
        eventLogger: @escaping EventLogger = { event, metadata in
            DiagnosticLogger.shared.log(event: event, metadata: metadata)
        },
        windowActionHandler: @escaping WindowActionHandler = AccessibilityWindowActions.perform,
        captureActionHandler: @escaping CaptureActionHandler = { _, _ in false },
        ocrActionHandler: @escaping OCRActionHandler = { _, _ in false },
        searchSelectedTextHandler: @escaping SearchSelectedTextHandler = { _ in false },
        openFocusedApplicationPathHandler: @escaping OpenFocusedApplicationPathHandler = { false },
        keyStrokeHandler: @escaping KeyStrokeHandler = { _ in false }
    ) {
        self.eventLogger = eventLogger
        self.windowActionHandler = windowActionHandler
        self.captureActionHandler = captureActionHandler
        self.ocrActionHandler = ocrActionHandler
        self.searchSelectedTextHandler = searchSelectedTextHandler
        self.openFocusedApplicationPathHandler = openFocusedApplicationPathHandler
        self.keyStrokeHandler = keyStrokeHandler
    }

    var isExecuting: Bool {
        executionTask != nil
    }

    func execute(
        _ actions: [ActionDefinition],
        options: ActionSequenceOptions = ActionSequenceOptions(),
        context: ExecutionContext = ExecutionContext()
    ) {
        if executionTask != nil {
            switch options.interruptionPolicy {
            case .cancelPrevious:
                cancel()
            case .ignoreNew:
                eventLogger(.actionSequenceIgnored, ["reason": "activeSequence"])
                return
            }
        }

        let executionID = UUID()
        activeExecutionID = executionID
        eventLogger(.actionSequenceStarted, ["actionCount": String(actions.count)])

        executionTask = Task { @MainActor [weak self] in
            for (index, action) in actions.enumerated() {
                guard !Task.isCancelled else { return }

                let succeeded: Bool
                if action.type == .delay {
                    succeeded = await Self.wait(
                        value: action.value,
                        maximumDelay: options.maximumDelay
                    )
                } else {
                    guard let self else { return }
                    succeeded = self.executeImmediately(action, context: context)
                }

                guard !Task.isCancelled else { return }

                if !succeeded {
                    self?.logActionFailure(action, index: index)
                    if options.failurePolicy == .stop {
                        self?.finish(executionID: executionID, outcome: "failed")
                        return
                    }
                }
            }

            guard !Task.isCancelled else { return }
            self?.finish(executionID: executionID, outcome: "completed")
        }
    }

    func cancel() {
        guard executionTask != nil else { return }
        executionTask?.cancel()
        executionTask = nil
        activeExecutionID = nil
        eventLogger(.actionSequenceCancelled, [:])
    }

    private func executeImmediately(_ action: ActionDefinition, context: ExecutionContext) -> Bool {
        switch action.type {
        case .keyStroke:
            return sendKeyStroke(action.value)
        case .openURL:
            guard let url = URL(string: action.value), url.scheme != nil else {
                return false
            }
            return NSWorkspace.shared.open(url)
        case .launchApplication:
            return launchApplication(action.value)
        case .delay:
            return false
        case .windowAction:
            guard let windowAction = WindowAction(rawValue: action.value) else { return false }
            return windowActionHandler(windowAction)
        case .captureAction:
            guard let captureAction = CaptureAction(rawValue: action.value) else { return false }
            return captureActionHandler(captureAction, context.gestureBounds)
        case .ocrAction:
            guard let ocrAction = OCRAction(rawValue: action.value) else { return false }
            return ocrActionHandler(ocrAction, context.gestureBounds)
        case .searchSelectedText:
            return searchSelectedTextHandler(action.value)
        case .openFocusedApplicationPath:
            return openFocusedApplicationPathHandler()
        }
    }

    private static func wait(value: String, maximumDelay: TimeInterval) async -> Bool {
        let safeMaximumDelay = min(max(maximumDelay, 0), 3_600)
        guard
            maximumDelay.isFinite,
            let seconds = TimeInterval(value),
            seconds.isFinite,
            seconds >= 0,
            seconds <= safeMaximumDelay
        else {
            return false
        }

        let nanoseconds = UInt64(seconds * 1_000_000_000)
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func launchApplication(_ value: String) -> Bool {
        if value.hasPrefix("/") {
            guard FileManager.default.fileExists(atPath: value) else { return false }
            let url = URL(fileURLWithPath: value)
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return true
        } else if let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) {
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: .init())
            return true
        }
        return false
    }

    private func sendKeyStroke(_ value: String) -> Bool {
        guard
            let keyStroke = KeyStrokeParser.parse(value),
            let keyCode = KeyMap.code(for: keyStroke.key)
        else {
            return false
        }

        if keyStrokeHandler(keyStroke) {
            return true
        }

        var flags: CGEventFlags = []
        for modifier in keyStroke.modifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .control: flags.insert(.maskControl)
            case .option: flags.insert(.maskAlternate)
            case .shift: flags.insert(.maskShift)
            }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        guard let keyDown, let keyUp else { return false }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func logActionFailure(_ action: ActionDefinition, index: Int) {
        eventLogger(
            .actionFailed,
            [
                "index": String(index),
                "type": action.type.rawValue
            ]
        )
    }

    private func finish(executionID: UUID, outcome: String) {
        guard activeExecutionID == executionID else { return }
        executionTask = nil
        activeExecutionID = nil
        eventLogger(.actionSequenceFinished, ["outcome": outcome])
    }
}

private enum KeyMap {
    private static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "return": 36, "enter": 36,
        "left": 123, "right": 124, "down": 125, "up": 126
    ]

    static func code(for token: String) -> CGKeyCode? {
        codes[token]
    }
}
