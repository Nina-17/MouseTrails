@preconcurrency import AppKit
@preconcurrency import ScreenCaptureKit
import CoreGraphics
import CoreImage
import CoreMedia
import MouseIncCore
import UniformTypeIdentifiers
@preconcurrency import Vision

@MainActor
final class CaptureCoordinator: NSObject {
    private var pinnedWindows: [PinnedImageWindowController] = []
    private weak var selectedPinnedWindow: PinnedImageWindowController?
    private let notificationCoordinator = UserNotificationCoordinator()

    func perform(_ action: CaptureAction, gestureBounds: CGRect?) -> Bool {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            presentError(
                title: "需要屏幕录制权限",
                message: "请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许 MouseIncMac，然后重新触发手势。"
            )
            return false
        }

        guard let gestureBounds, gestureBounds.width >= 4, gestureBounds.height >= 4 else {
            presentError(
                title: "手势范围不足",
                message: "截图动作需要由包含有效宽度和高度的手势触发。"
            )
            return false
        }
        Task { @MainActor [weak self] in
            await self?.capture(rect: gestureBounds, action: action)
        }
        DiagnosticLogger.shared.log("Capture started from gesture bounds; action=\(action.rawValue)")
        return true
    }

    func performOCR(_ action: OCRAction, gestureBounds: CGRect?) -> Bool {
        guard action == .recognizeRegion else { return false }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            presentError(
                title: "需要屏幕录制权限",
                message: "请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许 MouseIncMac，然后重新触发手势。"
            )
            return false
        }
        guard let gestureBounds, gestureBounds.width >= 4, gestureBounds.height >= 4 else {
            presentError(
                title: "手势范围不足",
                message: "OCR 动作需要由包含有效宽度和高度的手势触发。"
            )
            return false
        }
        Task { @MainActor [weak self] in
            await self?.recognizeText(rect: gestureBounds)
        }
        DiagnosticLogger.shared.log("OCR started from gesture bounds")
        return true
    }

    func copySelectedPinnedImage(for keyStroke: ParsedKeyStroke) -> Bool {
        guard
            keyStroke.key == "c",
            keyStroke.modifiers == [.command]
        else {
            return false
        }
        return selectedPinnedWindow?.copyImageIfExpanded() ?? false
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

    private func recognizeText(rect: CGRect) async {
        do {
            let image = try await captureImage(in: rect)
            try await recognizeAndCopy(image)
        } catch {
            DiagnosticLogger.shared.log("OCR failed: \(error.localizedDescription)")
            presentError(title: "文字识别失败", message: error.localizedDescription)
        }
    }

    private func recognizeAndCopy(_ image: CGImage) async throws {
        let text = try await OCRTextRecognizer.recognize(image)
        if text.isEmpty {
            notificationCoordinator.postOCRResult(text: "")
        } else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            notificationCoordinator.postOCRResult(text: text)
        }
        DiagnosticLogger.shared.log(
            "OCR completed; hasText=\(!text.isEmpty); copied=\(!text.isEmpty)"
        )
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
            if self.selectedPinnedWindow === controller {
                self.selectedPinnedWindow = nil
            }
        }
        controller.onSelected = { [weak self, weak controller] in
            self?.selectedPinnedWindow = controller
        }
        pinnedWindows.append(controller)
        selectedPinnedWindow = controller
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

private struct OCRImage: @unchecked Sendable {
    var value: CGImage
}

private enum OCRTextRecognizer {
    static func recognize(_ image: CGImage) async throws -> String {
        let sendableImage = OCRImage(value: image)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            let handler = VNImageRequestHandler(cgImage: sendableImage.value)
            try handler.perform([request])
            let observations = request.results ?? []
            let ordered = observations.sorted { lhs, rhs in
                let verticalDifference = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                if verticalDifference < 0.02 {
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return ordered.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
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

struct PinnedImageInteractionState: Equatable {
    private(set) var frame: CGRect
    private(set) var expandedFrame: CGRect
    private(set) var isCompact = false
    private(set) var opacity: CGFloat = 1
    var allowsCopy: Bool { !isCompact }

    init(frame: CGRect) {
        self.frame = frame
        expandedFrame = frame
    }

    mutating func synchronize(with frame: CGRect) {
        self.frame = frame
        if !isCompact { expandedFrame = frame }
    }

    mutating func toggleCompact(side: CGFloat = 72) {
        if isCompact {
            frame = expandedFrame
            isCompact = false
        } else {
            expandedFrame = frame
            frame = CGRect(
                x: frame.midX - side / 2,
                y: frame.maxY - side,
                width: side,
                height: side
            )
            isCompact = true
        }
    }

    mutating func moveBy(dx: CGFloat, dy: CGFloat) {
        frame.origin.x += dx
        frame.origin.y += dy
        if isCompact {
            expandedFrame.origin.x += dx
            expandedFrame.origin.y += dy
        } else {
            expandedFrame = frame
        }
    }

    mutating func adjustOpacity(by delta: CGFloat) {
        opacity = min(1, max(0.2, opacity + delta))
    }
}

private final class PinnedImagePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class PinnedImageWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    var onSelected: (() -> Void)?
    private weak var imageView: PinnedImageView?

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
        let panel = PinnedImagePanel(
            contentRect: CGRect(origin: origin, size: size),
            styleMask: [.borderless, .resizable],
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
        let imageView = PinnedImageView(image: image, frame: panel.frame)
        panel.contentView = imageView
        super.init(window: panel)
        self.imageView = imageView
        imageView.onSelected = { [weak self] in
            self?.onSelected?()
        }
        panel.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.orderFrontRegardless()
        window?.makeKey()
        if let imageView {
            window?.makeFirstResponder(imageView)
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func copyImageIfExpanded() -> Bool {
        imageView?.copyImageIfExpanded() ?? false
    }
}

private final class PinnedImageView: NSImageView {
    var onSelected: (() -> Void)?
    private let sourceImage: CGImage
    private var interactionState: PinnedImageInteractionState

    init(image: CGImage, frame: CGRect) {
        sourceImage = image
        interactionState = PinnedImageInteractionState(frame: frame)
        super.init(frame: .zero)
        self.image = NSImage(cgImage: image, size: frame.size)
        imageScaling = .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(self)
        onSelected?()
        interactionState.synchronize(with: window.frame)
        let initialMouse = NSEvent.mouseLocation
        let initialOrigin = window.frame.origin
        var didDrag = false

        while let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch nextEvent.type {
            case .leftMouseDragged:
                let currentMouse = NSEvent.mouseLocation
                let delta = CGPoint(
                    x: currentMouse.x - initialMouse.x,
                    y: currentMouse.y - initialMouse.y
                )
                if hypot(delta.x, delta.y) >= 2 { didDrag = true }
                window.setFrameOrigin(
                    CGPoint(x: initialOrigin.x + delta.x, y: initialOrigin.y + delta.y)
                )
            case .leftMouseUp:
                if didDrag {
                    let finalOrigin = window.frame.origin
                    interactionState.moveBy(
                        dx: finalOrigin.x - initialOrigin.x,
                        dy: finalOrigin.y - initialOrigin.y
                    )
                } else {
                    toggleCompact()
                }
                return
            default:
                break
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if interactionState.isCompact {
            saveImage()
        } else {
            window?.close()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        guard event.scrollingDeltaY != 0 else { return }
        let direction: CGFloat = event.scrollingDeltaY >= 0 ? 1 : -1
        interactionState.adjustOpacity(by: direction * 0.05)
        window.alphaValue = interactionState.opacity
    }

    override func keyDown(with event: NSEvent) {
        if handleCopyShortcut(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleCopyShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func toggleCompact() {
        guard let window else { return }
        interactionState.synchronize(with: window.frame)
        interactionState.toggleCompact()
        imageScaling = interactionState.isCompact ? .scaleNone : .scaleProportionallyUpOrDown
        imageAlignment = .alignCenter
        window.setFrame(interactionState.frame, display: true, animate: true)
    }

    func copyImageIfExpanded() -> Bool {
        guard interactionState.allowsCopy else { return false }
        guard let pngData = NSBitmapImageRep(cgImage: sourceImage)
            .representation(using: .png, properties: [:]) else {
            return false
        }

        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiffData = NSImage(
            cgImage: sourceImage,
            size: NSSize(width: sourceImage.width, height: sourceImage.height)
        ).tiffRepresentation {
            item.setData(tiffData, forType: .tiff)
        }

        do {
            let fileURL = try writeClipboardPNG(pngData)
            item.setString(fileURL.absoluteString, forType: .fileURL)
        } catch {
            DiagnosticLogger.shared.log("Pinned image clipboard file failed: \(error.localizedDescription)")
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    private func writeClipboardPNG(_ data: Data) throws -> URL {
        let root = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("MouseIncMac/PinnedClipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("MouseIncMac-贴图-\(UUID().uuidString).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func handleCopyShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard
            interactionState.allowsCopy,
            modifiers == .command,
            event.charactersIgnoringModifiers?.lowercased() == "c"
        else {
            return false
        }
        return copyImageIfExpanded()
    }

    private func saveImage() {
        guard let data = NSBitmapImageRep(cgImage: sourceImage)
            .representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.title = "保存贴图"
        panel.nameFieldStringValue = "MouseIncMac-贴图.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
