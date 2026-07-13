import AppKit
import MouseIncCore

@MainActor
final class EdgeScrollController {
    private enum MediaKey: Int {
        case volumeUp = 0
        case volumeDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
    }

    func adjust(_ edge: ScreenEdge, by direction: CGFloat, step _: Double) -> Bool {
        let increase = direction < 0
        let key: MediaKey
        switch edge {
        case .left: key = increase ? .brightnessUp : .brightnessDown
        case .right: key = increase ? .volumeUp : .volumeDown
        case .top, .bottom: return false
        }
        return postMediaKey(key)
    }

    private func postMediaKey(_ key: MediaKey) -> Bool {
        // systemDefined subtype 8 is the same media-key event sent by macOS
        // function keys.  This lets the OS choose the active display/output.
        let keyCode = key.rawValue
        let downData = (keyCode << 16) | (0xA << 8)
        let upData = (keyCode << 16) | (0xB << 8)
        guard
            let down = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: downData, data2: -1
            )?.cgEvent,
            let up = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: upData, data2: -1
            )?.cgEvent
        else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
