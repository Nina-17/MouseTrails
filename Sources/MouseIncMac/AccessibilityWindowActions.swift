import AppKit
@preconcurrency import ApplicationServices
import MouseIncCore

enum CloseAllWindowStrategy: Equatable {
    case terminateApplication
    case sendCloseAllShortcut

    static func forBundleIdentifier(_ bundleIdentifier: String?) -> Self {
        switch bundleIdentifier {
        case "com.apple.Safari",
             "com.apple.SafariTechnologyPreview",
             "com.google.Chrome",
             "com.google.Chrome.beta",
             "com.google.Chrome.canary",
             "com.google.Chrome.dev":
            return .terminateApplication
        default:
            return .sendCloseAllShortcut
        }
    }
}

enum LogicalWindowCloseFallback: Equatable {
    case none
    case hideLogicalApplication

    static func forApplications(
        inputBundleIdentifier: String?,
        logicalBundleIdentifier: String?
    ) -> Self {
        if inputBundleIdentifier == "com.valvesoftware.steam.helper",
           logicalBundleIdentifier == "com.valvesoftware.steam" {
            return .hideLogicalApplication
        }
        return .none
    }
}

enum WindowLayoutRegion: Equatable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

struct NativeWindowMenuCommand: Equatable {
    let virtualKey: Int?
    let modifiers: UInt32
    let titles: [String]

    static func forAction(_ action: WindowAction) -> Self? {
        // AX menu shortcut modifiers omit the Fn/Globe key. Native window
        // commands are exposed as Control + NoCommand plus their virtual key.
        let modifiers: UInt32 = (1 << 2) | (1 << 3)
        switch action {
        case .fill:
            return Self(virtualKey: nil, modifiers: modifiers, titles: ["Fill", "填充", "填滿"])
        case .center:
            return Self(virtualKey: nil, modifiers: modifiers, titles: ["Center", "居中", "置中"])
        case .tileLeft:
            return Self(virtualKey: 123, modifiers: modifiers, titles: ["Left", "左侧", "左側"])
        case .tileRight:
            return Self(virtualKey: 124, modifiers: modifiers, titles: ["Right", "右侧", "右側"])
        case .tileTop:
            return Self(virtualKey: 126, modifiers: modifiers, titles: ["Top", "顶部", "上方"])
        case .tileBottom:
            return Self(virtualKey: 125, modifiers: modifiers, titles: ["Bottom", "底部", "下方"])
        case .tileTopLeft:
            return Self(virtualKey: nil, modifiers: modifiers, titles: ["Top Left", "左上角", "左上方"])
        case .tileTopRight:
            return Self(virtualKey: nil, modifiers: modifiers, titles: ["Top Right", "右上角", "右上方"])
        case .tileBottomLeft:
            return Self(virtualKey: nil, modifiers: modifiers, titles: ["Bottom Left", "左下角", "左下方"])
        case .tileBottomRight:
            return Self(virtualKey: nil, modifiers: modifiers, titles: ["Bottom Right", "右下角", "右下方"])
        case .restorePreviousSize:
            return Self(
                virtualKey: nil,
                modifiers: modifiers,
                titles: ["Return to Previous Size", "恢复到之前的大小", "回復成先前大小"]
            )
        default: return nil
        }
    }
}

struct WindowLayoutCalculator {
    static func regions(for action: WindowAction) -> [WindowLayoutRegion]? {
        switch action {
        case .tileTopLeft: return [.topLeft]
        case .tileTopRight: return [.topRight]
        case .tileBottomLeft: return [.bottomLeft]
        case .tileBottomRight: return [.bottomRight]
        default: return nil
        }
    }

    static func frames(for action: WindowAction, in bounds: CGRect) -> [CGRect]? {
        regions(for: action)?.map { frame(for: $0, in: bounds) }
    }

    static func frame(for region: WindowLayoutRegion, in bounds: CGRect) -> CGRect {
        let halfWidth = bounds.width / 2
        let halfHeight = bounds.height / 2
        switch region {
        case .topLeft:
            return CGRect(x: bounds.minX, y: bounds.minY, width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: bounds.midX, y: bounds.minY, width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: bounds.minX, y: bounds.midY, width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: bounds.midX, y: bounds.midY, width: halfWidth, height: halfHeight)
        }
    }

    static func targetFrame(
        for action: WindowAction,
        currentFrame: CGRect,
        in bounds: CGRect
    ) -> CGRect? {
        if let cornerFrame = frames(for: action, in: bounds)?.first {
            return cornerFrame
        }
        switch action {
        case .fill:
            return bounds
        case .center:
            let size = CGSize(
                width: min(currentFrame.width, bounds.width),
                height: min(currentFrame.height, bounds.height)
            )
            return CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .tileLeft:
            return CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width / 2,
                height: bounds.height
            )
        case .tileRight:
            return CGRect(
                x: bounds.midX,
                y: bounds.minY,
                width: bounds.width / 2,
                height: bounds.height
            )
        case .tileTop:
            return CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: bounds.height / 2
            )
        case .tileBottom:
            return CGRect(
                x: bounds.minX,
                y: bounds.midY,
                width: bounds.width,
                height: bounds.height / 2
            )
        default:
            return nil
        }
    }

    /// Apps such as Steam and Z-Library clamp requested sizes to their own
    /// minimums. Keep the size the app accepted and re-anchor it to the edge
    /// the user requested instead of treating that constraint as a failure.
    static func anchoredFrame(
        for action: WindowAction,
        acceptedSize: CGSize,
        in bounds: CGRect
    ) -> CGRect? {
        guard acceptedSize.width > 0, acceptedSize.height > 0 else { return nil }
        let left = bounds.minX
        let right = max(bounds.minX, bounds.maxX - acceptedSize.width)
        let top = bounds.minY
        let bottom = max(bounds.minY, bounds.maxY - acceptedSize.height)
        let centerX = bounds.midX - acceptedSize.width / 2
        let centerY = bounds.midY - acceptedSize.height / 2

        let origin: CGPoint
        switch action {
        case .fill:
            origin = CGPoint(x: left, y: top)
        case .center:
            origin = CGPoint(x: centerX, y: centerY)
        case .tileLeft:
            origin = CGPoint(x: left, y: top)
        case .tileRight:
            origin = CGPoint(x: right, y: top)
        case .tileTop:
            origin = CGPoint(x: left, y: top)
        case .tileBottom:
            origin = CGPoint(x: left, y: bottom)
        case .tileTopLeft:
            origin = CGPoint(x: left, y: top)
        case .tileTopRight:
            origin = CGPoint(x: right, y: top)
        case .tileBottomLeft:
            origin = CGPoint(x: left, y: bottom)
        case .tileBottomRight:
            origin = CGPoint(x: right, y: bottom)
        default:
            return nil
        }
        return CGRect(origin: origin, size: acceptedSize)
    }
}

@MainActor
enum AccessibilityWindowActions {
    private struct WindowIdentity: Hashable {
        enum Token: Hashable {
            case windowNumber(Int)
            case accessibilityIdentifier(String)
            case elementHash(CFHashCode)
        }

        let processIdentifier: pid_t
        let token: Token
    }

    private static var savedFrames: [WindowIdentity: CGRect] = [:]
    private static var unsupportedMenuCommands: Set<MenuCapabilityKey> = []

    private struct MenuCapabilityKey: Hashable {
        let processIdentifier: pid_t
        let launchDate: Date?
        let command: String
    }

    static func perform(_ action: WindowAction, target: GestureExecutionTarget? = nil) -> Bool {
        switch action {
        case .center, .fill, .tileLeft, .tileRight, .tileTop, .tileBottom,
             .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight:
            return performNativeWindowMenuCommand(action, target: target)
                || applyLayout(action, target: target)
        case .maximize:
            return performNativeFullScreenMenuCommand(target: target)
                || toggleFullScreen(target: target)
        case .restorePreviousSize:
            if performNativeWindowMenuCommand(action, target: target) {
                return true
            }
            return restorePreviousFrame(target: target)
        case .minimize:
            return setBooleanAttribute(
                kAXMinimizedAttribute,
                value: true,
                target: target
            ) || pressWindowButton(kAXMinimizeButtonAttribute, target: target)
        case .close:
            return closeFocusedWindow(target: target)
        case .closeAll:
            return sendCloseAllShortcut(target: target)
        case .quitApplication:
            return quitApplication(target: target)
        }
    }

    /// Preserves the ordinary Command-W meaning (close tab when applicable,
    /// otherwise close window) while adding the focus handoff used after the
    /// final visible window goes away.
    static func closeWindowOrTab(target: GestureExecutionTarget?) -> Bool {
        guard let inputApplication = inputApplication(for: target) else { return false }
        let window = focusedWindow(target: target)
        let snapshot = window.flatMap(FocusHandoffCoordinator.snapshot)
        let application = menuApplication(for: target) ?? inputApplication
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 0.3)
        let closeTitles = ["Close Tab", "Close Window", "Close", "关闭标签页", "关闭窗口", "关闭"]
        let closeIdentifiers = ["closeTab:", "performClose:", "close:"]
        let menuClosed = elementAttribute(kAXMenuBarAttribute, from: applicationElement).flatMap {
            findMenuItem(
                titles: closeTitles,
                identifiers: closeIdentifiers,
                in: $0,
                depth: 0
            )
        }.map {
            AXUIElementPerformAction($0, kAXPressAction as CFString) == .success
        } ?? false

        if menuClosed {
            FocusHandoffCoordinator.scheduleIfNeeded(snapshot)
            return true
        }
        if let window, pressWindowButton(kAXCloseButtonAttribute, on: window) {
            FocusHandoffCoordinator.scheduleIfNeeded(snapshot)
            return true
        }
        if hideLogicalApplicationFallback(target: target, snapshot: snapshot) {
            return true
        }
        guard postCommandW() else { return false }
        FocusHandoffCoordinator.scheduleIfNeeded(snapshot)
        return true
    }

    private static func performNativeWindowMenuCommand(
        _ action: WindowAction,
        target: GestureExecutionTarget?
    ) -> Bool {
        guard let application = menuApplication(for: target),
              let command = NativeWindowMenuCommand.forAction(action) else { return false }
        let capabilityKey = menuCapabilityKey(
            application: application,
            command: action.rawValue
        )
        guard !unsupportedMenuCommands.contains(capabilityKey) else { return false }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 0.3)
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, from: applicationElement),
              let windowMenu = findWindowMenu(in: menuBar),
              let menuItem = findMenuItem(matching: command, in: windowMenu, depth: 0)
        else {
            unsupportedMenuCommands.insert(capabilityKey)
            DiagnosticLogger.shared.log(
                "Native window menu command not found; action=\(action.rawValue); " +
                "bundle=\(application.bundleIdentifier ?? "unknown")"
            )
            logMenuSnapshot(from: applicationElement, action: action)
            return false
        }
        let result = AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
        if result != .success {
            DiagnosticLogger.shared.log(
                "Native window menu command failed; action=\(action.rawValue); " +
                "AXError=\(result.rawValue)"
            )
        }
        return result == .success
    }

    private static func findMenuItem(
        matching command: NativeWindowMenuCommand,
        in element: AXUIElement,
        depth: Int
    ) -> AXUIElement? {
        guard depth <= 8 else { return nil }
        let title = stringAttribute(kAXTitleAttribute, from: element)
        let matchesTitle = title.map(command.titles.contains) ?? false
        let matchesShortcut = command.virtualKey.map { virtualKey in
            numberAttribute(kAXMenuItemCmdVirtualKeyAttribute, from: element)?.intValue
                == virtualKey &&
            numberAttribute(kAXMenuItemCmdModifiersAttribute, from: element)?.uint32Value
                == command.modifiers
        } ?? false
        if (matchesTitle || matchesShortcut),
           booleanAttribute(kAXEnabledAttribute, from: element) != false {
            return element
        }
        for child in elementArrayAttribute(kAXChildrenAttribute, from: element) {
            if let match = findMenuItem(matching: command, in: child, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private static func findWindowMenu(in menuBar: AXUIElement) -> AXUIElement? {
        let knownTitles = ["Window", "窗口", "窗户", "視窗", "ウインドウ", "윈도우"]
        return elementArrayAttribute(kAXChildrenAttribute, from: menuBar).first { element in
            guard let title = stringAttribute(kAXTitleAttribute, from: element) else { return false }
            return knownTitles.contains(title)
        }
    }

    private static func performNativeFullScreenMenuCommand(
        target: GestureExecutionTarget?
    ) -> Bool {
        guard let application = menuApplication(for: target) else { return false }
        let capabilityKey = menuCapabilityKey(
            application: application,
            command: WindowAction.maximize.rawValue
        )
        guard !unsupportedMenuCommands.contains(capabilityKey) else { return false }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 0.3)
        let titles = [
            "Enter Full Screen", "Exit Full Screen",
            "进入全屏幕", "退出全屏幕",
            "進入全螢幕", "離開全螢幕",
            "フルスクリーンにする", "フルスクリーンを解除"
        ]
        let identifiers = ["toggleFullScreen:", "enterFullScreenMode:", "exitFullScreenMode:"]
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, from: applicationElement),
              let menuItem = findMenuItem(
                  titles: titles,
                  identifiers: identifiers,
                  in: menuBar,
                  depth: 0
              )
        else {
            unsupportedMenuCommands.insert(capabilityKey)
            DiagnosticLogger.shared.log(
                "Native full-screen menu command not found; " +
                "bundle=\(application.bundleIdentifier ?? "unknown")"
            )
            return false
        }
        let result = AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
        if result != .success {
            DiagnosticLogger.shared.log(
                "Native full-screen menu command failed; AXError=\(result.rawValue)"
            )
        }
        return result == .success
    }

    private static func findMenuItem(
        titles: [String],
        identifiers: [String],
        in element: AXUIElement,
        depth: Int
    ) -> AXUIElement? {
        guard depth <= 8 else { return nil }
        let title = stringAttribute(kAXTitleAttribute, from: element)
        let identifier = stringAttribute(kAXIdentifierAttribute, from: element)
        if (title.map(titles.contains) == true || identifier.map(identifiers.contains) == true),
           booleanAttribute(kAXEnabledAttribute, from: element) != false {
            return element
        }
        for child in elementArrayAttribute(kAXChildrenAttribute, from: element) {
            if let match = findMenuItem(
                titles: titles,
                identifiers: identifiers,
                in: child,
                depth: depth + 1
            ) {
                return match
            }
        }
        return nil
    }

    private static func logMenuSnapshot(
        from applicationElement: AXUIElement,
        action: WindowAction
    ) {
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, from: applicationElement) else {
            DiagnosticLogger.shared.log("Window menu snapshot unavailable; action=\(action.rawValue)")
            return
        }
        let snapshotRoot = findWindowMenu(in: menuBar) ?? menuBar
        var lines: [String] = []
        appendMenuSnapshot(of: snapshotRoot, depth: 0, remaining: 120, to: &lines)
        DiagnosticLogger.shared.log(
            "Window menu snapshot; action=\(action.rawValue); entries=\(lines.count)\n" +
            lines.joined(separator: "\n")
        )
    }

    private static func appendMenuSnapshot(
        of element: AXUIElement,
        depth: Int,
        remaining: Int,
        to lines: inout [String]
    ) {
        guard depth <= 8, lines.count < remaining else { return }
        let children = elementArrayAttribute(kAXChildrenAttribute, from: element)
        let title = stringAttribute(kAXTitleAttribute, from: element) ?? ""
        let role = stringAttribute(kAXRoleAttribute, from: element) ?? ""
        let identifier = stringAttribute(kAXIdentifierAttribute, from: element) ?? ""
        let key = numberAttribute(kAXMenuItemCmdVirtualKeyAttribute, from: element)?.stringValue ?? "-"
        let modifiers = numberAttribute(kAXMenuItemCmdModifiersAttribute, from: element)?.stringValue ?? "-"
        if !title.isEmpty || key != "-" {
            lines.append(
                "\(String(repeating: "  ", count: depth))" +
                "title=\(title); role=\(role); id=\(identifier); " +
                "key=\(key); modifiers=\(modifiers); children=\(children.count)"
            )
        }
        for child in children {
            appendMenuSnapshot(of: child, depth: depth + 1, remaining: remaining, to: &lines)
        }
    }

    private static func quitApplication(target: GestureExecutionTarget?) -> Bool {
        guard let application = logicalApplication(for: target) else { return false }
        let accepted = application.terminate()
        DiagnosticLogger.shared.log(
            "Application termination requested; pid=\(application.processIdentifier); " +
            "bundle=\(application.bundleIdentifier ?? "unknown"); accepted=\(accepted)"
        )
        return accepted
    }

    private static func sendCloseAllShortcut(target: GestureExecutionTarget?) -> Bool {
        guard let inputApplication = inputApplication(for: target) else { return false }
        let logicalApplication = logicalApplication(for: target) ?? inputApplication
        let snapshot = focusedWindow(target: target).flatMap(FocusHandoffCoordinator.snapshot)
            ?? FocusHandoffCoordinator.snapshot(
                closingProcessIdentifier: inputApplication.processIdentifier
            )
        if CloseAllWindowStrategy.forBundleIdentifier(logicalApplication.bundleIdentifier)
            == .terminateApplication {
            let terminated = logicalApplication.terminate()
            if terminated {
                FocusHandoffCoordinator.scheduleAfterClosingAll(snapshot)
            }
            return terminated
        }
        if usesLogicalHideFallback(target: target) {
            _ = logicalApplication.hide()
            DiagnosticLogger.shared.log(
                "Close-all used logical-app hide fallback; " +
                "inputPID=\(inputApplication.processIdentifier); " +
                "logicalPID=\(logicalApplication.processIdentifier)"
            )
            FocusHandoffCoordinator.scheduleAfterClosingAll(snapshot)
            return true
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: false)
        else { return false }
        keyDown.flags = [.maskCommand, .maskAlternate]
        keyUp.flags = [.maskCommand, .maskAlternate]
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        FocusHandoffCoordinator.scheduleAfterClosingAll(snapshot)
        return true
    }

    private static func postCommandW() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 13, keyDown: false)
        else { return false }
        keyDown.flags = [.maskCommand]
        keyUp.flags = [.maskCommand]
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func closeFocusedWindow(target: GestureExecutionTarget?) -> Bool {
        guard let window = focusedWindow(target: target) else { return false }
        let snapshot = FocusHandoffCoordinator.snapshot(closing: window)
        if pressWindowButton(kAXCloseButtonAttribute, on: window) {
            FocusHandoffCoordinator.scheduleIfNeeded(snapshot)
            return true
        }
        return hideLogicalApplicationFallback(target: target, snapshot: snapshot)
    }

    private static func hideLogicalApplicationFallback(
        target: GestureExecutionTarget?,
        snapshot: FocusHandoffCoordinator.Snapshot?
    ) -> Bool {
        guard usesLogicalHideFallback(target: target),
              let inputApplication = inputApplication(for: target),
              let application = logicalApplication(for: target)
        else { return false }

        // Steam's visible CEF window exposes no AX close button and no Close
        // menu command. Hiding its logical host matches its red-button behavior
        // without killing the helper process that Steam would immediately relaunch.
        _ = application.hide()
        DiagnosticLogger.shared.log(
            "Close used logical-app hide fallback; " +
            "inputPID=\(inputApplication.processIdentifier); " +
            "logicalPID=\(application.processIdentifier)"
        )
        FocusHandoffCoordinator.scheduleIfNeeded(snapshot)
        return true
    }

    private static func setBooleanAttribute(
        _ attribute: String,
        value: Bool,
        target: GestureExecutionTarget?
    ) -> Bool {
        guard let window = focusedWindow(target: target) else { return false }
        return AXUIElementSetAttributeValue(
            window,
            attribute as CFString,
            value as CFBoolean
        ) == .success
    }

    private static func pressWindowButton(
        _ attribute: String,
        target: GestureExecutionTarget?
    ) -> Bool {
        guard let window = focusedWindow(target: target) else { return false }
        return pressWindowButton(attribute, on: window)
    }

    private static func pressWindowButton(_ attribute: String, on window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return false }
        return AXUIElementPerformAction(
            unsafeDowncast(value, to: AXUIElement.self),
            kAXPressAction as CFString
        ) == .success
    }

    private static func toggleFullScreen(target: GestureExecutionTarget?) -> Bool {
        guard let window = focusedWindow(target: target) else { return false }
        let fullScreenAttribute = "AXFullScreen"
        if let isFullScreen = booleanAttribute(fullScreenAttribute, from: window),
           setBooleanAttribute(fullScreenAttribute, value: !isFullScreen, on: window) {
            DiagnosticLogger.shared.log(
                "Full-screen toggled through AX fallback; value=\(!isFullScreen)"
            )
            return true
        }
        return pressWindowButton(kAXFullScreenButtonAttribute, on: window)
    }

    private static func applyLayout(
        _ action: WindowAction,
        target: GestureExecutionTarget?
    ) -> Bool {
        guard
            let window = focusedWindow(target: target),
            let currentFrame = frame(of: window),
            let visibleBounds = quartzVisibleBounds(containing: CGPoint(
                x: currentFrame.midX,
                y: currentFrame.midY
            )),
            let requestedFrame = WindowLayoutCalculator.targetFrame(
                for: action,
                currentFrame: currentFrame,
                in: visibleBounds
            ),
            let identity = identity(for: window)
        else { return false }

        let wasMinimized = booleanAttribute(kAXMinimizedAttribute, from: window) ?? false
        if wasMinimized,
           !setBooleanAttribute(kAXMinimizedAttribute, value: false, on: window) {
            return false
        }
        let frameWasAlreadySaved = savedFrames[identity] != nil
        if !frameWasAlreadySaved {
            savedFrames[identity] = currentFrame
        }

        guard setPosition(requestedFrame.origin, for: window),
              setSize(requestedFrame.size, for: window),
              let acceptedFrame = frame(of: window),
              let anchoredFrame = WindowLayoutCalculator.anchoredFrame(
                  for: action,
                  acceptedSize: acceptedFrame.size,
                  in: visibleBounds
              ),
              setPosition(anchoredFrame.origin, for: window),
              let finalFrame = frame(of: window)
        else {
            _ = setFrame(currentFrame, for: window)
            if wasMinimized {
                _ = setBooleanAttribute(kAXMinimizedAttribute, value: true, on: window)
            }
            if !frameWasAlreadySaved {
                savedFrames.removeValue(forKey: identity)
            }
            return false
        }

        let constrained = !approximatelyEqual(finalFrame.size, requestedFrame.size)
        DiagnosticLogger.shared.log(
            "AX layout fallback completed; action=\(action.rawValue); " +
            "requested=\(requestedFrame); actual=\(finalFrame); constrained=\(constrained)"
        )
        return finalFrame.width > 40
            && finalFrame.height > 40
            && finalFrame.intersects(visibleBounds)
    }

    private static func restorePreviousFrame(target: GestureExecutionTarget?) -> Bool {
        guard let window = focusedWindow(target: target),
              let identity = identity(for: window),
              let savedFrame = savedFrames[identity]
        else { return false }
        guard setFrame(savedFrame, for: window) else { return false }
        savedFrames.removeValue(forKey: identity)
        DiagnosticLogger.shared.log(
            "AX layout fallback restored previous frame; requested=\(savedFrame); " +
            "actual=\(String(describing: frame(of: window)))"
        )
        return true
    }

    private static func identity(for window: AXUIElement) -> WindowIdentity? {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(window, &processIdentifier) == .success else { return nil }
        let token: WindowIdentity.Token
        if let windowNumber = numberAttribute("AXWindowNumber", from: window)?.intValue {
            token = .windowNumber(windowNumber)
        } else if let identifier = stringAttribute(kAXIdentifierAttribute, from: window),
                  !identifier.isEmpty {
            token = .accessibilityIdentifier(identifier)
        } else {
            token = .elementHash(CFHash(window))
        }
        return WindowIdentity(
            processIdentifier: processIdentifier,
            token: token
        )
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard
            let position = pointAttribute(kAXPositionAttribute, from: window),
            let size = sizeAttribute(kAXSizeAttribute, from: window),
            size.width > 0,
            size.height > 0
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func setFrame(_ frame: CGRect, for window: AXUIElement) -> Bool {
        // Position first so apps do not clamp a growing window against its old
        // lower/right edge. Reapply the position after sizing because minimum
        // size constraints can otherwise push right/bottom layouts off-screen.
        setPosition(frame.origin, for: window)
            && setSize(frame.size, for: window)
            && setPosition(frame.origin, for: window)
    }

    private static func setPosition(_ position: CGPoint, for window: AXUIElement) -> Bool {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            value
        ) == .success
    }

    private static func setSize(_ size: CGSize, for window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            value
        ) == .success
    }

    private static func approximatelyEqual(_ left: CGSize, _ right: CGSize) -> Bool {
        let tolerance: CGFloat = 4
        return abs(left.width - right.width) <= tolerance
            && abs(left.height - right.height) <= tolerance
    }

    private static func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func booleanAttribute(_ attribute: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? Bool
    }

    private static func numberAttribute(_ attribute: String, from element: AXUIElement) -> NSNumber? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? NSNumber
    }

    private static func elementAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func elementArrayAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let values = value as? [Any]
        else { return [] }
        return values.compactMap { value in
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
        }
    }

    private static func setBooleanAttribute(
        _ attribute: String,
        value: Bool,
        on element: AXUIElement
    ) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            attribute as CFString,
            value as CFBoolean
        ) == .success
    }

    private static func inputApplication(for target: GestureExecutionTarget?) -> NSRunningApplication? {
        if let target {
            return NSRunningApplication(processIdentifier: target.inputProcessIdentifier)
        }
        return NSWorkspace.shared.frontmostApplication
    }

    private static func menuApplication(for target: GestureExecutionTarget?) -> NSRunningApplication? {
        if let target {
            if let processIdentifier = target.menuProcessIdentifier,
               let application = NSRunningApplication(processIdentifier: processIdentifier) {
                return application
            }
            return inputApplication(for: target)
        }
        return NSWorkspace.shared.menuBarOwningApplication
            ?? NSWorkspace.shared.frontmostApplication
    }

    private static func logicalApplication(for target: GestureExecutionTarget?) -> NSRunningApplication? {
        menuApplication(for: target) ?? inputApplication(for: target)
    }

    private static func usesLogicalHideFallback(target: GestureExecutionTarget?) -> Bool {
        LogicalWindowCloseFallback.forApplications(
            inputBundleIdentifier: target?.inputBundleIdentifier,
            logicalBundleIdentifier: target?.applicationBundleIdentifier
        ) == .hideLogicalApplication
    }

    private static func menuCapabilityKey(
        application: NSRunningApplication,
        command: String
    ) -> MenuCapabilityKey {
        MenuCapabilityKey(
            processIdentifier: application.processIdentifier,
            launchDate: application.launchDate,
            command: command
        )
    }

    private static func focusedWindow(target: GestureExecutionTarget? = nil) -> AXUIElement? {
        guard let application = inputApplication(for: target) else { return nil }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 0.3)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        ) == .success,
           let value,
           CFGetTypeID(value) == AXUIElementGetTypeID() {
            let focused = unsafeDowncast(value, to: AXUIElement.self)
            if frame(of: focused).map({ $0.width > 40 && $0.height > 40 }) == true {
                return focused
            }
        }
        if AXUIElementCopyAttributeValue(
            applicationElement,
            kAXMainWindowAttribute as CFString,
            &value
        ) == .success,
           let value,
           CFGetTypeID(value) == AXUIElementGetTypeID() {
            let main = unsafeDowncast(value, to: AXUIElement.self)
            if frame(of: main).map({ $0.width > 40 && $0.height > 40 }) == true {
                return main
            }
        }
        let windows = elementArrayAttribute(kAXWindowsAttribute, from: applicationElement)
            .filter { frame(of: $0).map { $0.width > 40 && $0.height > 40 } == true }
        if let point = target?.gestureStartPoint,
           let containingWindow = windows.first(where: { frame(of: $0)?.contains(point) == true }) {
            return containingWindow
        }
        return windows.first
    }

    private static func pointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func sizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size) else {
            return nil
        }
        return size
    }

    private static func quartzVisibleBounds(containing point: CGPoint) -> CGRect? {
        for screen in NSScreen.screens {
            guard
                let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else {
                continue
            }
            let displayBounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
            guard displayBounds.contains(point) else { continue }

            let frame = screen.frame
            let visibleFrame = screen.visibleFrame
            let leftInset = visibleFrame.minX - frame.minX
            let rightInset = frame.maxX - visibleFrame.maxX
            let topInset = frame.maxY - visibleFrame.maxY
            let bottomInset = visibleFrame.minY - frame.minY
            return CGRect(
                x: displayBounds.minX + leftInset,
                y: displayBounds.minY + topInset,
                width: displayBounds.width - leftInset - rightInset,
                height: displayBounds.height - topInset - bottomInset
            )
        }
        return nil
    }
}
