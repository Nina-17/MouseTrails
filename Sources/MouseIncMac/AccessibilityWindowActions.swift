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
    case fill
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

struct WindowLayoutCalculator {
    static func regions(for action: WindowAction) -> [WindowLayoutRegion]? {
        switch action {
        case .fill: return [.fill]
        case .tileLeft: return [.left]
        case .tileRight: return [.right]
        case .tileTop: return [.top]
        case .tileBottom: return [.bottom]
        case .tileTopLeft: return [.topLeft]
        case .tileTopRight: return [.topRight]
        case .tileBottomLeft: return [.bottomLeft]
        case .tileBottomRight: return [.bottomRight]
        case .arrangeLeftRight: return [.left, .right]
        case .arrangeRightLeft: return [.right, .left]
        case .arrangeTopBottom: return [.top, .bottom]
        case .arrangeBottomTop: return [.bottom, .top]
        case .arrangeFour: return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        case .arrangeLeftAndQuarters: return [.left, .topRight, .bottomRight]
        case .arrangeRightAndQuarters: return [.right, .topLeft, .bottomLeft]
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
        case .fill:
            return bounds
        case .left:
            return CGRect(x: bounds.minX, y: bounds.minY, width: halfWidth, height: bounds.height)
        case .right:
            return CGRect(x: bounds.midX, y: bounds.minY, width: halfWidth, height: bounds.height)
        case .top:
            return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: halfHeight)
        case .bottom:
            return CGRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: halfHeight)
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
        let processIdentifier: pid_t
        let elementHash: CFHashCode
    }

    private static var savedFrames: [WindowIdentity: CGRect] = [:]

    static func perform(_ action: WindowAction) -> Bool {
        switch action {
        case .center:
            return centerFrontmostWindow()
        case .maximize:
            return toggleFullScreen()
        case .fill,
             .tileLeft, .tileRight, .tileTop, .tileBottom,
             .tileTopLeft, .tileTopRight, .tileBottomLeft, .tileBottomRight,
             .arrangeLeftRight, .arrangeRightLeft,
             .arrangeTopBottom, .arrangeBottomTop, .arrangeFour,
             .arrangeLeftAndQuarters, .arrangeRightAndQuarters:
            return applyLayout(action)
        case .restorePreviousSize:
            return restorePreviousFrame()
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

    private static func toggleFullScreen() -> Bool {
        guard NSWorkspace.shared.frontmostApplication != nil else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 3, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 3, keyDown: false)
        else { return false }
        keyDown.flags = [.maskCommand, .maskControl]
        keyUp.flags = [.maskCommand, .maskControl]
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

    private static func centerFrontmostWindow() -> Bool {
        guard
            let window = focusedWindow(),
            let currentFrame = frame(of: window),
            let visibleBounds = quartzVisibleBounds(containing: CGPoint(
                x: currentFrame.midX,
                y: currentFrame.midY
            ))
        else {
            return false
        }

        let target = CGRect(
            x: visibleBounds.midX - currentFrame.width / 2,
            y: visibleBounds.midY - currentFrame.height / 2,
            width: currentFrame.width,
            height: currentFrame.height
        )
        return applyFrames([target], to: [window])
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

        let windows: [AXUIElement]
        if targetFrames.count == 1 {
            windows = [focusedWindow]
        } else {
            guard let candidates = manageableWindows(focusedFirst: focusedWindow),
                  candidates.count >= targetFrames.count else { return false }
            windows = Array(candidates.prefix(targetFrames.count))
        }
        return applyFrames(targetFrames, to: windows)
    }

    private static func restorePreviousFrame() -> Bool {
        guard let window = focusedWindow(), let identity = identity(for: window),
              let target = savedFrames[identity] else { return false }
        guard setFrame(target, for: window) else { return false }
        savedFrames.removeValue(forKey: identity)
        return true
    }

    private static func applyFrames(_ targets: [CGRect], to windows: [AXUIElement]) -> Bool {
        guard targets.count == windows.count else { return false }
        let originals = windows.compactMap(frame(of:))
        guard originals.count == windows.count else { return false }

        var newlySaved: [WindowIdentity] = []
        for (window, original) in zip(windows, originals) {
            guard let identity = identity(for: window) else {
                newlySaved.forEach { savedFrames.removeValue(forKey: $0) }
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
                return false
            }
        }
        return true
    }

    private static func manageableWindows(focusedFirst focused: AXUIElement) -> [AXUIElement]? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                applicationElement,
                kAXWindowsAttribute as CFString,
                &value
            ) == .success,
            let allWindows = value as? [AXUIElement]
        else { return nil }

        var result = [focused]
        for window in allWindows where !CFEqual(window, focused) {
            guard isManageable(window) else { continue }
            result.append(window)
        }
        return result
    }

    private static func isManageable(_ window: AXUIElement) -> Bool {
        guard stringAttribute(kAXRoleAttribute, from: window) == kAXWindowRole else { return false }
        if let minimized = booleanAttribute(kAXMinimizedAttribute, from: window), minimized {
            return false
        }
        var positionSettable = DarwinBoolean(false)
        var sizeSettable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(
                window,
                kAXPositionAttribute as CFString,
                &positionSettable
            ) == .success,
            AXUIElementIsAttributeSettable(
                window,
                kAXSizeAttribute as CFString,
                &sizeSettable
            ) == .success
        else { return false }
        return positionSettable.boolValue && sizeSettable.boolValue
    }

    private static func identity(for window: AXUIElement) -> WindowIdentity? {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(window, &processIdentifier) == .success else { return nil }
        return WindowIdentity(
            processIdentifier: processIdentifier,
            elementHash: CFHash(window)
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
