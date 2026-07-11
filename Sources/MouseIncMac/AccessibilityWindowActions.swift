import AppKit
@preconcurrency import ApplicationServices
import MouseIncCore

@MainActor
enum AccessibilityWindowActions {
    static func perform(_ action: WindowAction) -> Bool {
        switch action {
        case .center:
            return centerFrontmostWindow()
        case .maximize:
            return toggleFullScreen()
        case .restore:
            // Kept for schema-3 configuration compatibility. Full screen is a
            // native toggle, so legacy restore actions perform the same shortcut.
            return toggleFullScreen()
        case .minimize:
            return setBooleanAttribute(kAXMinimizedAttribute, value: true)
        case .close:
            return pressWindowButton(kAXCloseButtonAttribute)
        }
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
            let position = pointAttribute(kAXPositionAttribute, from: window),
            let size = sizeAttribute(kAXSizeAttribute, from: window),
            let visibleBounds = quartzVisibleBounds(containing: CGPoint(
                x: position.x + size.width / 2,
                y: position.y + size.height / 2
            ))
        else {
            return false
        }

        var target = CGPoint(
            x: visibleBounds.midX - size.width / 2,
            y: visibleBounds.midY - size.height / 2
        )
        guard let value = AXValueCreate(.cgPoint, &target) else { return false }
        return AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            value
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
