@preconcurrency import AppKit
@preconcurrency import ScreenCaptureKit
import CoreGraphics
import CoreImage
import CoreMedia
import MouseIncCore
import UniformTypeIdentifiers

@MainActor
final class CaptureCoordinator: NSObject {
    private var selectionController: RegionSelectionController?
    private var pinnedWindows: [PinnedImageWindowController] = []

    func perform(_ action: CaptureAction) -> Bool {
        guard selectionController == nil else {
            DiagnosticLogger.shared.log("Capture ignored because a selection is already active")
            return false
        }

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            presentError(
                title: "需要屏幕录制权限",
                message: "请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许 MouseIncMac，然后重新触发手势。"
            )
            return false
        }

        let controller = RegionSelectionController { [weak self] rect in
            guard let self else { return }
            self.selectionController = nil
            guard let rect else {
                DiagnosticLogger.shared.log("Capture selection cancelled")
                return
            }
            Task { @MainActor [weak self] in
                await self?.capture(rect: rect, action: action)
            }
        }
        selectionController = controller
        controller.begin()
        DiagnosticLogger.shared.log("Capture selection started; action=\(action.rawValue)")
        return true
    }

    private func capture(rect: CGRect, action: CaptureAction) async {
        do {
            let image = try await captureImage(in: rect)
            switch action {
            case .pinRegion:
                createPinnedWindow(image: image, sourceRect: rect)
            case .copyRegion:
                copy(image)
            case .saveRegion:
                try save(image)
            }
            DiagnosticLogger.shared.log("Capture completed; action=\(action.rawValue)")
        } catch CaptureError.cancelled {
            DiagnosticLogger.shared.log("Capture save cancelled")
        } catch {
            DiagnosticLogger.shared.log("Capture failed: \(error.localizedDescription)")
            presentError(title: "截图失败", message: error.localizedDescription)
        }
    }

    private func captureImage(in rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let ownApplication = content.applications.first {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        var segments: [CapturedSegment] = []
        for screen in NSScreen.screens {
            let intersection = rect.intersection(screen.frame)
            guard !intersection.isNull, intersection.width >= 1, intersection.height >= 1 else {
                continue
            }
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                let display = content.displays.first(where: { $0.displayID == number.uint32Value })
            else {
                continue
            }

            let filter: SCContentFilter
            if let ownApplication {
                filter = SCContentFilter(
                    display: display,
                    excludingApplications: [ownApplication],
                    exceptingWindows: []
                )
            } else {
                filter = SCContentFilter(display: display, excludingWindows: [])
            }

            let scale = CGFloat(display.width) / max(screen.frame.width, 1)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(
                x: intersection.minX - screen.frame.minX,
                y: screen.frame.maxY - intersection.maxY,
                width: intersection.width,
                height: intersection.height
            )
            configuration.width = max(1, Int((intersection.width * scale).rounded()))
            configuration.height = max(1, Int((intersection.height * scale).rounded()))
            configuration.showsCursor = false
            configuration.capturesAudio = false

            let image: CGImage
            if #available(macOS 14.0, *) {
                image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            } else {
                image = try await OneFrameStreamCapture.capture(
                    contentFilter: filter,
                    configuration: configuration
                )
            }
            segments.append(CapturedSegment(image: image, frame: intersection, scale: scale))
        }

        guard !segments.isEmpty else { throw CaptureError.noDisplay }
        if segments.count == 1, segments[0].frame.equalTo(rect) {
            return segments[0].image
        }
        return try compose(segments: segments, in: rect)
    }

    private func compose(segments: [CapturedSegment], in rect: CGRect) throws -> CGImage {
        let scale = segments.map(\.scale).max() ?? 1
        let width = max(1, Int((rect.width * scale).rounded()))
        let height = max(1, Int((rect.height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CaptureError.imageCreationFailed
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        for segment in segments {
            let destination = CGRect(
                x: (segment.frame.minX - rect.minX) * scale,
                y: (segment.frame.minY - rect.minY) * scale,
                width: segment.frame.width * scale,
                height: segment.frame.height * scale
            )
            context.draw(segment.image, in: destination)
        }
        guard let image = context.makeImage() else { throw CaptureError.imageCreationFailed }
        return image
    }

    private func createPinnedWindow(image: CGImage, sourceRect: CGRect) {
        let controller = PinnedImageWindowController(image: image, sourceRect: sourceRect)
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.pinnedWindows.removeAll { $0 === controller }
        }
        pinnedWindows.append(controller)
        controller.show()
    }

    private func copy(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
    }

    private func save(_ image: CGImage) throws {
        let panel = NSSavePanel()
        panel.title = "保存截图"
        panel.nameFieldStringValue = "MouseIncMac-截图.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { throw CaptureError.cancelled }
        guard
            let representation = NSBitmapImageRep(cgImage: image)
                .representation(using: .png, properties: [:])
        else {
            throw CaptureError.imageCreationFailed
        }
        try representation.write(to: url, options: .atomic)
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

private struct CapturedSegment {
    var image: CGImage
    var frame: CGRect
    var scale: CGFloat
}

private enum CaptureError: LocalizedError {
    case cancelled
    case noDisplay
    case imageCreationFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: return "操作已取消"
        case .noDisplay: return "框选区域未落在可捕获的显示器上"
        case .imageCreationFailed: return "无法生成截图图像"
        }
    }
}

private final class OneFrameStreamCapture: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CGImage, Error>?
    private var stream: SCStream?
    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    static func capture(
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        let receiver = OneFrameStreamCapture()
        return try await receiver.capture(
            contentFilter: contentFilter,
            configuration: configuration
        )
    }

    private func capture(
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        let stream = SCStream(filter: contentFilter, configuration: configuration, delegate: nil)
        self.stream = stream
        try stream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "com.mason.mouseincmac.capture-frame")
        )
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            stream.startCapture { [weak self] error in
                if let error {
                    self?.finish(.failure(error))
                }
            }
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard
            outputType == .screen,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else {
            finish(.failure(CaptureError.imageCreationFailed))
            return
        }
        finish(.success(cgImage))
    }

    private func finish(_ result: Result<CGImage, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let stream = self.stream
        self.stream = nil
        lock.unlock()
        stream?.stopCapture(completionHandler: nil)
        continuation.resume(with: result)
    }
}

@MainActor
private final class RegionSelectionController {
    typealias Completion = (CGRect?) -> Void

    private let completion: Completion
    private var panel: CaptureSelectionPanel?
    private var didFinish = false

    init(completion: @escaping Completion) {
        self.completion = completion
    }

    func begin() {
        guard let union = NSScreen.screens.map(\.frame).reduce(nil, { partial, frame in
            partial.map { $0.union(frame) } ?? frame
        }) else {
            finish(nil)
            return
        }

        let panel = CaptureSelectionPanel(
            contentRect: union,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = CaptureSelectionView(frame: CGRect(origin: .zero, size: union.size))
        view.onComplete = { [weak self] localRect in
            guard let self, let panel = self.panel else { return }
            let origin = panel.convertPoint(toScreen: localRect.origin)
            self.finish(CGRect(origin: origin, size: localRect.size))
        }
        view.onCancel = { [weak self] in self?.finish(nil) }
        panel.onCancel = { [weak self] in self?.finish(nil) }
        panel.contentView = view
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        self.panel = panel
        NSCursor.crosshair.push()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
    }

    private func finish(_ rect: CGRect?) {
        guard !didFinish else { return }
        didFinish = true
        NSCursor.pop()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        completion(rect)
    }
}

private final class CaptureSelectionPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private final class CaptureSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let shade = NSBezierPath(rect: bounds)
        if let selectionRect, selectionRect.width > 0, selectionRect.height > 0 {
            shade.appendRect(selectionRect)
        }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        shade.fill()

        if let selectionRect {
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width >= 4, rect.height >= 4 else {
            onCancel?()
            return
        }
        onComplete?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }
}

@MainActor
private final class PinnedImageWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(image: CGImage, sourceRect: CGRect) {
        let maximumWidth: CGFloat = 800
        let scale = min(1, maximumWidth / max(sourceRect.width, 1))
        let size = CGSize(
            width: max(120, sourceRect.width * scale),
            height: max(80, sourceRect.height * scale)
        )
        let origin = CGPoint(
            x: sourceRect.midX - size.width / 2,
            y: sourceRect.midY - size.height / 2
        )
        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.isMovableByWindowBackground = true
        panel.contentAspectRatio = size
        panel.minSize = CGSize(width: 120, height: 80)
        panel.isReleasedWhenClosed = false
        panel.contentView = PinnedImageView(image: NSImage(cgImage: image, size: size))
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

private final class PinnedImageView: NSImageView {
    init(image: NSImage) {
        super.init(frame: .zero)
        self.image = image
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
        menu = makeContextMenu()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "复制贴图", action: #selector(copyImage), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        let saveItem = NSMenuItem(title: "保存贴图…", action: #selector(saveImage), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)
        menu.addItem(.separator())
        let closeItem = NSMenuItem(title: "关闭贴图", action: #selector(closeWindow), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        return menu
    }

    @objc private func copyImage() {
        guard let image else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    @objc private func saveImage() {
        guard
            let image,
            let data = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data),
            let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        let panel = NSSavePanel()
        panel.title = "保存贴图"
        panel.nameFieldStringValue = "MouseIncMac-贴图.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url, options: .atomic)
    }

    @objc private func closeWindow() {
        window?.close()
    }
}
