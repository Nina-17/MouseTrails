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

    static func perform(_ action: WindowAction) -> Bool {
        switch action {
        case .center, .fill, .tileLeft, .tileRight, .tileTop, .tileBottom:
            return performNativeWindowMenuCommand(action)
        case .maximize:
            return performNativeFullScreenMenuCommand()
        case .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight:
            return performNativeWindowMenuCommand(action) || applyLayout(action)
        case .restorePreviousSize:
            if canRestoreSavedFrame() {
                return restorePreviousFrame()
            }
            return performNativeWindowMenuCommand(action)
        case .minimize:
            return setBooleanAttribute(kAXMinimizedAttribute, value: true)
        case .close:
            return pressWindowButton(kAXCloseButtonAttribute)
        case .closeAll:
            return sendCloseAllShortcut()
        case .quitApplication:
            return quitFrontmostApplication()
        }
    }

    private static func performNativeWindowMenuCommand(_ action: WindowAction) -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let command = NativeWindowMenuCommand.forAction(action) else { return false }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let menuBar = elementAttribute(kAXMenuBarAttribute, from: applicationElement),
              let windowMenu = findWindowMenu(in: menuBar),
              let menuItem = findMenuItem(matching: command, in: windowMenu, depth: 0)
        else {
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
        let knownTitles = ["Window", "窗口", "視窗", "ウインドウ", "윈도우"]
        return elementArrayAttribute(kAXChildrenAttribute, from: menuBar).first { element in
            guard let title = stringAttribute(kAXTitleAttribute, from: element) else { return false }
            return knownTitles.contains(title)
        }
    }

    private static func performNativeFullScreenMenuCommand() -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication else { return false }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
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

    private static func quitFrontmostApplication() -> Bool {
        NSWorkspace.shared.frontmostApplication?.terminate() ?? false
    }

    private static func sendCloseAllShortcut() -> Bool {
        guard let application = NSWorkspace.shared.frontmostApplication else { return false }
        if CloseAllWindowStrategy.forBundleIdentifier(application.bundleIdentifier) == .terminateApplication {
            return application.terminate()
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
        return true
    }

    private static func setBooleanAttribute(_ attribute: String, value: Bool) -> Bool {
        guard let window = focusedWindow() else { return false }
        return AXUIElementSetAttributeValue(
            window,
            attribute as CFString,
            value as CFBoolean
        ) == .success
    }

    private static func pressWindowButton(_ attribute: String) -> Bool {
        guard let window = focusedWindow() else { return false }
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

    private static func applyLayout(_ action: WindowAction) -> Bool {
        guard
            let focusedWindow = focusedWindow(),
            let focusedFrame = frame(of: focusedWindow),
            let visibleBounds = quartzVisibleBounds(containing: CGPoint(
                x: focusedFrame.midX,
                y: focusedFrame.midY
            )),
            let targetFrames = WindowLayoutCalculator.frames(for: action, in: visibleBounds)
        else { return false }

        guard targetFrames.count == 1 else { return false }
        return applyFrames(targetFrames, to: [focusedWindow])
    }

    private static func restorePreviousFrame() -> Bool {
        guard let window = focusedWindow(), let identity = identity(for: window),
              let target = savedFrames[identity] else { return false }
        guard setFrame(target, for: window) else { return false }
        savedFrames.removeValue(forKey: identity)
        return true
    }

    private static func canRestoreSavedFrame() -> Bool {
        guard let window = focusedWindow(), let identity = identity(for: window) else { return false }
        return savedFrames[identity] != nil
    }

    private static func applyFrames(_ targets: [CGRect], to windows: [AXUIElement]) -> Bool {
        guard targets.count == windows.count else { return false }
        let originals = windows.compactMap(frame(of:))
        guard originals.count == windows.count else { return false }
        let minimizedStates = windows.map {
            booleanAttribute(kAXMinimizedAttribute, from: $0) ?? false
        }

        for (index, window) in windows.enumerated() where minimizedStates[index] {
            guard setBooleanAttribute(kAXMinimizedAttribute, value: false, on: window) else {
                restoreMinimizedStates(minimizedStates, windows: windows, through: index)
                return false
            }
        }

        var newlySaved: [WindowIdentity] = []
        for (window, original) in zip(windows, originals) {
            guard let identity = identity(for: window) else {
                newlySaved.forEach { savedFrames.removeValue(forKey: $0) }
                restoreMinimizedStates(minimizedStates, windows: windows)
                return false
            }
            if savedFrames[identity] == nil {
                savedFrames[identity] = original
                newlySaved.append(identity)
            }
        }

        for (index, pair) in zip(windows, targets).enumerated() {
            guard setFrame(pair.1, for: pair.0) else {
                for rollbackIndex in 0 ... index {
                    _ = setFrame(originals[rollbackIndex], for: windows[rollbackIndex])
                }
                newlySaved.forEach { savedFrames.removeValue(forKey: $0) }
                restoreMinimizedStates(minimizedStates, windows: windows)
                return false
            }
        }
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
        var size = frame.size
        var position = frame.origin
        guard
            let sizeValue = AXValueCreate(.cgSize, &size),
            let positionValue = AXValueCreate(.cgPoint, &position),
            AXUIElementSetAttributeValue(
                window,
                kAXSizeAttribute as CFString,
                sizeValue
            ) == .success,
            AXUIElementSetAttributeValue(
                window,
                kAXPositionAttribute as CFString,
                positionValue
            ) == .success
        else { return false }
        return true
    }

    private static func restoreMinimizedStates(
        _ states: [Bool],
        windows: [AXUIElement],
        through lastIndex: Int? = nil
    ) {
        let upperBound = min(lastIndex ?? (windows.count - 1), windows.count - 1)
        guard upperBound >= 0 else { return }
        for index in 0 ... upperBound where states[index] {
            _ = setBooleanAttribute(kAXMinimizedAttribute, value: true, on: windows[index])
        }
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

    private static func focusedWindow() -> AXUIElement? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                applicationElement,
                kAXFocusedWindowAttribute as CFString,
                &value
            ) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
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
