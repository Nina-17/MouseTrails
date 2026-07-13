import AppKit
import CoreAudio
import IOKit.graphics
import MouseIncCore

@_silgen_name("CGDisplayIOServicePort")
private func displayServicePort(_ display: CGDirectDisplayID) -> io_service_t

@MainActor
final class EdgeScrollController {
    func adjust(_ edge: ScreenEdge, by direction: CGFloat, step: Double) -> Bool {
        switch edge {
        case .left: return adjustBrightness(by: direction, step: Float(step))
        case .right: return adjustVolume(by: direction, step: Float(step))
        case .top, .bottom: return false
        }
    }

    private func adjustBrightness(by direction: CGFloat, step: Float) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else {
            DiagnosticLogger.shared.log("Edge brightness failed: no screen at cursor")
            return false
        }
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let number else { return false }
        let framebuffer = displayServicePort(CGDirectDisplayID(number.uint32Value))
        let display = IODisplayForFramebuffer(framebuffer, 0)
        var current: Float = 0
        guard IODisplayGetFloatParameter(display, 0, kIODisplayBrightnessKey as CFString, &current) == kIOReturnSuccess else {
            DiagnosticLogger.shared.log("Edge brightness unsupported by display")
            return false
        }
        let next = min(1, max(0, current + Float(direction) * step))
        let result = IODisplaySetFloatParameter(display, 0, kIODisplayBrightnessKey as CFString, next) == kIOReturnSuccess
        if !result { DiagnosticLogger.shared.log("Edge brightness set failed") }
        return result
    }

    private func adjustVolume(by direction: CGFloat, step: Float) -> Bool {
        var device = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, 0, nil, &size, &device) == noErr else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var isSettable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr,
              isSettable.boolValue else {
            DiagnosticLogger.shared.log("Edge volume unsupported by default output")
            return false
        }
        var value: Float = 0
        size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        value = min(1, max(0, value + Float(direction) * step))
        let result = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
        if !result { DiagnosticLogger.shared.log("Edge volume set failed") }
        return result
    }
}
