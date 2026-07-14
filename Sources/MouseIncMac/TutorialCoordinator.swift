import AppKit
import MouseIncCore
import SwiftUI

enum TutorialGestureDecision: Equatable {
    case notHandled
    case consume
    case execute
}

enum TutorialPage: Int, CaseIterable, Identifiable {
    case welcome
    case editing
    case browsing
    case windows
    case pinnedImage
    case ocr
    case finish

    var id: Self { self }

    var title: String {
        switch self {
        case .welcome: return "欢迎使用 MouseTrails"
        case .editing: return "复制与粘贴"
        case .browsing: return "浏览与搜索"
        case .windows: return "窗口操作"
        case .pinnedImage: return "贴图"
        case .ocr: return "离线 OCR"
        case .finish: return "体验完成"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "授权后，通过真实任务熟悉 MouseTrails"
        case .editing: return "用手势完成一次真实的复制与粘贴"
        case .browsing: return "在示例页面中前进、后退并实际搜索"
        case .windows: return "只操作教程创建的临时窗口"
        case .pinnedImage: return "生成贴图并亲手完成全部常用操作"
        case .ocr: return "圈选文字、识别并复制真实结果"
        case .finish: return "MouseTrails 已准备就绪"
        }
    }
}

private enum TutorialStep: Equatable {
    case welcome
    case copy
    case paste
    case back
    case forward
    case search
    case closeWindow
    case enterFullScreen
    case exitFullScreen
    case minimize
    case closeAll
    case createPin
    case dragPin
    case collapsePin
    case savePin
    case expandPin
    case adjustPinOpacity
    case copyPin
    case closePin
    case recognizeText
    case finish

    var gestureIdentifier: String? {
        switch self {
        case .copy: return "UP"
        case .paste: return "DOWN"
        case .back: return "LEFT"
        case .forward: return "RIGHT"
        case .search: return "LETTER_S"
        case .closeWindow: return "DOWN-RIGHT"
        case .enterFullScreen, .exitFullScreen: return "UP_RIGHT"
        case .minimize: return "DOWN_LEFT"
        case .closeAll: return "DOWN-LEFT"
        case .createPin: return "SQUARE_CLOCKWISE"
        case .recognizeText: return "SQUARE_COUNTERCLOCKWISE"
        default: return nil
        }
    }
}

enum PinnedImageInteractionEvent: Equatable {
    case created
    case moved
    case collapsed
    case savedAs
    case expanded
    case opacityAdjusted
    case copied
    case closed
}

enum PinnedImageTutorialStep: String, CaseIterable, Hashable {
    case drag
    case collapse
    case saveAs
    case expand
    case opacity
    case copy
    case close

    var title: String {
        switch self {
        case .drag: return "拖动贴图"
        case .collapse: return "左键折叠"
        case .saveAs: return "折叠状态右键另存为"
        case .expand: return "左键恢复"
        case .opacity: return "悬停滚动调整透明度"
        case .copy: return "展开状态按 Command+C 复制"
        case .close: return "展开状态右键关闭"
        }
    }
}

@MainActor
final class TutorialCoordinator: NSWindowController, ObservableObject, NSWindowDelegate {
    private enum DefaultsKey {
        static let completedVersion = "tutorial.completedVersion"
    }

    static let currentTutorialVersion = 3
    static let editingSentence = "“人充满劳绩，但诗意地栖居在这块大地之上。” —— 荷尔德林《人，诗意的栖居》"
    static let searchPhrase = "MouseTrails macOS 手势工具"
    static let ocrSample = "MouseTrails 教程识别成功"

    @Published private(set) var page: TutorialPage = .welcome
    @Published private(set) var feedback: String?
    @Published private(set) var isPresenting = false
    @Published private(set) var successEventID: UUID?
    @Published private(set) var pasteText = ""
    @Published private(set) var browserPageIndex = 1
    @Published private(set) var recognizedText: String?
    @Published private(set) var completedGestureCount = 0
    @Published private(set) var copySelectionToken = UUID()
    @Published private(set) var pasteFocusToken = UUID()
    @Published private(set) var searchSelectionToken = UUID()
    @Published private(set) var completedPinnedImageSteps: Set<PinnedImageTutorialStep> = []

    var onClose: (@MainActor () -> Void)?
    var dismissPinnedImage: (@MainActor (UUID) -> Void)?

    private let defaults: UserDefaults
    private let injectedTutorialConfiguration: AppConfiguration?
    private let allowsHeadlessInteraction: Bool
    private var tutorialConfiguration = AppConfiguration()
    private var step: TutorialStep = .welcome
    private var transitionTask: Task<Void, Never>?
    private var demoControllers: [TutorialDemoWindowController] = []
    private var tutorialPinnedImageID: UUID?
    private var isCleaningUp = false
    private var waitingForSearchReturn = false
    private var pasteboardChangeBeforeAction = 0

    init(
        defaults: UserDefaults = .standard,
        tutorialConfiguration: AppConfiguration? = nil,
        allowsHeadlessInteraction: Bool = false
    ) {
        self.defaults = defaults
        injectedTutorialConfiguration = tutorialConfiguration
        self.allowsHeadlessInteraction = allowsHeadlessInteraction
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        transitionTask?.cancel()
    }

    var shouldPresentOnLaunch: Bool {
        defaults.integer(forKey: DefaultsKey.completedVersion) < Self.currentTutorialVersion
    }

    var configurationForCurrentContext: AppConfiguration? {
        guard isPresenting, !waitingForSearchReturn else { return nil }
        if allowsHeadlessInteraction { return tutorialConfiguration }
        guard
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier,
              let keyWindow = NSApplication.shared.keyWindow,
              ownsTutorialWindow(keyWindow) else { return nil }
        return tutorialConfiguration
    }

    var expectedGestureIdentifier: String? { step.gestureIdentifier }

    func begin() {
        transitionTask?.cancel()
        cleanupTransientWindows()
        tutorialConfiguration = makeTutorialConfiguration()
        page = .welcome
        step = .welcome
        feedback = nil
        successEventID = nil
        pasteText = ""
        browserPageIndex = 1
        recognizedText = nil
        completedGestureCount = 0
        completedPinnedImageSteps = []
        waitingForSearchReturn = false
        isPresenting = true
    }

    func show(permissionAuthorizationCoordinator: PermissionAuthorizationCoordinator) {
        begin()
        let rootView = TutorialView(
            coordinator: self,
            permissionAuthorizationCoordinator: permissionAuthorizationCoordinator
        )
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
            window.title = "MouseTrails 使用教程"
            window.setContentSize(NSSize(width: 920, height: 680))
            window.contentMinSize = NSSize(width: 780, height: 600)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        } else {
            window?.contentViewController = NSHostingController(rootView: rootView)
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func nextFromWelcome() {
        move(to: .editing)
    }

    func skipCurrentScene() {
        switch page {
        case .welcome: move(to: .editing)
        case .editing: move(to: .browsing)
        case .browsing: move(to: .windows)
        case .windows: move(to: .pinnedImage)
        case .pinnedImage: move(to: .ocr)
        case .ocr: move(to: .finish)
        case .finish: break
        }
    }

    func previousScene() {
        switch page {
        case .welcome: break
        case .editing: move(to: .welcome)
        case .browsing: move(to: .editing)
        case .windows: move(to: .browsing)
        case .pinnedImage: move(to: .windows)
        case .ocr: move(to: .pinnedImage)
        case .finish: move(to: .ocr)
        }
    }

    func updatePastedText(_ value: String) {
        pasteText = value
        guard step == .paste, value == Self.editingSentence else { return }
        emitSuccess("粘贴成功")
        scheduleMove(to: .browsing)
    }

    @discardableResult
    func handleRecognizedGesture(_ identifier: String?) -> TutorialGestureDecision {
        guard isPresenting else { return .notHandled }
        guard configurationForCurrentContext != nil else { return .notHandled }
        guard let expected = step.gestureIdentifier else {
            feedback = "当前任务请直接操作界面"
            return .consume
        }
        guard let identifier else {
            feedback = "没有识别出轨迹，请放大动作后再试"
            return .consume
        }
        guard identifier.caseInsensitiveCompare(expected) == .orderedSame else {
            feedback = "识别为 \(Self.displayName(for: identifier))，当前需要 \(Self.displayName(for: expected))"
            return .consume
        }

        switch step {
        case .copy:
            pasteboardChangeBeforeAction = NSPasteboard.general.changeCount
            verifyCopyAfterExecution()
            return .execute
        case .paste:
            return .execute
        case .back:
            browserPageIndex = 0
            emitSuccess("已返回上一页")
            scheduleStep(.forward)
            return .consume
        case .forward:
            browserPageIndex = 1
            emitSuccess("已前进到下一页")
            scheduleStep(.search)
            return .consume
        case .search:
            waitingForSearchReturn = true
            feedback = "正在默认浏览器中搜索；查看结果后返回 MouseTrails"
            completedGestureCount += 1
            successEventID = UUID()
            return .execute
        case .closeWindow:
            demoControllers.first?.closeByGesture()
            return .consume
        case .enterFullScreen, .exitFullScreen:
            demoControllers.first?.toggleFullScreenByGesture()
            return .consume
        case .minimize:
            demoControllers.first?.minimizeByGesture()
            return .consume
        case .closeAll:
            demoControllers.forEach { $0.closeByGesture() }
            return .consume
        case .createPin, .recognizeText:
            return .execute
        default:
            return .consume
        }
    }

    func applicationDidBecomeActive() {
        guard waitingForSearchReturn else { return }
        waitingForSearchReturn = false
        emitSuccess("已完成真实搜索")
        scheduleMove(to: .windows)
    }

    func handlePinnedImageInteraction(id: UUID, event: PinnedImageInteractionEvent) {
        guard isPresenting, !isCleaningUp else { return }
        switch event {
        case .created where step == .createPin:
            tutorialPinnedImageID = id
            step = .dragPin
            emitSuccess("贴图已生成，请把它拖到旁边")
        case .moved where id == tutorialPinnedImageID && step == .dragPin:
            completedPinnedImageSteps.insert(.drag)
            step = .collapsePin
            feedback = "拖动成功。现在左键单击贴图，将它折叠"
        case .collapsed where id == tutorialPinnedImageID && step == .collapsePin:
            completedPinnedImageSteps.insert(.collapse)
            step = .savePin
            feedback = "贴图已折叠。现在右键贴图，选择位置完成另存为"
        case .savedAs where id == tutorialPinnedImageID && step == .savePin:
            completedPinnedImageSteps.insert(.saveAs)
            step = .expandPin
            feedback = "另存为完成。现在左键单击贴图，将它恢复"
        case .expanded where id == tutorialPinnedImageID && step == .expandPin:
            completedPinnedImageSteps.insert(.expand)
            step = .adjustPinOpacity
            feedback = "贴图已恢复。将光标放在贴图上滚动，调整透明度"
        case .opacityAdjusted where id == tutorialPinnedImageID && step == .adjustPinOpacity:
            completedPinnedImageSteps.insert(.opacity)
            step = .copyPin
            feedback = "透明度已改变。保持贴图展开并按 Command+C 复制"
        case .copied where id == tutorialPinnedImageID && step == .copyPin:
            completedPinnedImageSteps.insert(.copy)
            step = .closePin
            feedback = "图片已复制。最后在展开状态右键关闭贴图"
        case .closed where id == tutorialPinnedImageID:
            tutorialPinnedImageID = nil
            if step == .closePin {
                completedPinnedImageSteps.insert(.close)
                emitSuccess("贴图练习完成")
                scheduleMove(to: .ocr)
            } else {
                step = .createPin
                completedPinnedImageSteps = []
                feedback = "贴图提前关闭了，请重新用顺时针方框生成贴图"
                window?.makeKeyAndOrderFront(nil)
            }
        default:
            break
        }
    }

    func handleOCRResult(_ result: Result<String, Error>) {
        guard isPresenting, step == .recognizeText else { return }
        switch result {
        case let .success(text):
            guard !text.isEmpty else {
                feedback = "没有识别到文字，请重新圈选示例文字"
                return
            }
            recognizedText = text
            let copied = NSPasteboard.general.string(forType: .string) == text
            emitSuccess(copied ? "OCR 完成，结果已复制" : "OCR 完成")
            scheduleMove(to: .finish, delay: .milliseconds(1_000))
        case let .failure(error):
            feedback = "OCR 失败：\(error.localizedDescription)"
        }
    }

    func finish() {
        defaults.set(Self.currentTutorialVersion, forKey: DefaultsKey.completedVersion)
        closeTutorial()
    }

    func skip() {
        defaults.set(Self.currentTutorialVersion, forKey: DefaultsKey.completedVersion)
        closeTutorial()
    }

    func closeTutorial() {
        if let window {
            window.close()
        } else {
            finishPresentation()
        }
    }

    func windowWillClose(_ notification: Notification) {
        finishPresentation()
    }

    static func displayName(for identifier: String) -> String {
        switch identifier.uppercased() {
        case "UP": return "向上直线"
        case "DOWN": return "向下直线"
        case "LEFT": return "向左直线"
        case "RIGHT": return "向右直线"
        case "UP_RIGHT": return "右上直线"
        case "DOWN_LEFT": return "左下直线"
        case "DOWN-RIGHT": return "下 → 右"
        case "DOWN-LEFT": return "下 → 左"
        case "LETTER_S": return "字母 S"
        case "SQUARE_CLOCKWISE": return "顺时针方框"
        case "SQUARE_COUNTERCLOCKWISE": return "逆时针方框"
        default: return identifier
        }
    }

    private func makeTutorialConfiguration() -> AppConfiguration {
        var configuration: AppConfiguration
        if let injectedTutorialConfiguration {
            configuration = injectedTutorialConfiguration
        } else if let url = Bundle.main.url(forResource: "default-config", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            configuration = decoded
        } else {
            configuration = AppConfiguration()
        }
        configuration.gestureOptions.enabled = true
        configuration.edgeScrollOptions.enabled = false
        configuration.bindings.removeAll { binding in
            binding.actions.contains {
                $0.type == .windowAction && $0.value == WindowAction.quitApplication.rawValue
            }
        }
        return configuration
    }

    private func ownsTutorialWindow(_ candidate: NSWindow) -> Bool {
        if candidate === window { return true }
        return demoControllers.contains { $0.window === candidate }
    }

    private func verifyCopyAfterExecution() {
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, step == .copy else { return }
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount != pasteboardChangeBeforeAction,
                  pasteboard.string(forType: .string) == Self.editingSentence else {
                feedback = "复制没有写入剪贴板，请再试一次"
                return
            }
            emitSuccess("复制成功，接下来把句子粘贴回来")
            scheduleStep(.paste)
        }
    }

    private func emitSuccess(_ message: String) {
        feedback = message
        successEventID = UUID()
        completedGestureCount += 1
    }

    private func scheduleStep(_ nextStep: TutorialStep, delay: Duration = .milliseconds(700)) {
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            step = nextStep
            prepareCurrentStep()
        }
    }

    private func scheduleMove(to page: TutorialPage, delay: Duration = .milliseconds(700)) {
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.move(to: page)
        }
    }

    private func move(to page: TutorialPage) {
        transitionTask?.cancel()
        if self.page == .windows { cleanupDemoWindows() }
        if self.page == .pinnedImage { cleanupTutorialPinnedImage() }
        waitingForSearchReturn = false
        self.page = page
        switch page {
        case .welcome: step = .welcome
        case .editing: step = .copy
        case .browsing: step = .back
        case .windows: step = .closeWindow
        case .pinnedImage: step = .createPin
        case .ocr: step = .recognizeText
        case .finish: step = .finish
        }
        feedback = nil
        if page == .pinnedImage { completedPinnedImageSteps = [] }
        prepareCurrentStep()
    }

    private func prepareCurrentStep() {
        window?.makeKeyAndOrderFront(nil)
        switch step {
        case .copy:
            copySelectionToken = UUID()
            feedback = "句子已选中。按住右键画一条向上直线来复制"
        case .paste:
            pasteText = ""
            pasteFocusToken = UUID()
            feedback = "输入框已聚焦。画一条向下直线来粘贴"
        case .back:
            browserPageIndex = 1
            feedback = "当前在第二页。画一条向左直线返回上一页"
        case .forward:
            feedback = "画一条向右直线回到下一页"
        case .search:
            searchSelectionToken = UUID()
            feedback = "搜索词已选中。画出字母 S，在默认浏览器中搜索"
        case .closeWindow:
            if !allowsHeadlessInteraction { showSingleDemo(kind: .close) }
            feedback = "在弹出的演示窗口中画“下 → 右”，将它关闭"
        case .enterFullScreen:
            if !allowsHeadlessInteraction { showSingleDemo(kind: .fullScreen) }
            feedback = "在演示窗口中画右上直线，进入全屏"
        case .exitFullScreen:
            feedback = "再画一次右上直线，退出全屏"
        case .minimize:
            if !allowsHeadlessInteraction { showSingleDemo(kind: .minimize) }
            feedback = "在演示窗口中画左下直线，将它最小化"
        case .closeAll:
            if !allowsHeadlessInteraction { showCloseAllDemoWindows() }
            feedback = "画“下 → 左”，同时关闭三个演示窗口"
        case .createPin:
            feedback = "用顺时针方框圈住示例卡片，生成真实贴图"
        case .recognizeText:
            recognizedText = nil
            feedback = "用逆时针方框圈住示例文字"
        default:
            break
        }
    }

    private func showSingleDemo(kind: TutorialDemoKind) {
        cleanupDemoWindows()
        let controller = TutorialDemoWindowController(kind: kind)
        controller.onClose = { [weak self, weak controller] triggered in
            guard let self, let controller else { return }
            demoControllers.removeAll { $0 === controller }
            guard triggered, step == .closeWindow else { return }
            window?.makeKeyAndOrderFront(nil)
            emitSuccess("演示窗口已关闭")
            scheduleStep(.enterFullScreen)
        }
        controller.onEnterFullScreen = { [weak self] triggered in
            guard let self, triggered, step == .enterFullScreen else { return }
            step = .exitFullScreen
            controller.model.instruction = "全屏成功。再画一次右上直线恢复"
            emitSuccess("已进入全屏")
        }
        controller.onExitFullScreen = { [weak self, weak controller] triggered in
            guard let self, let controller, triggered, step == .exitFullScreen else { return }
            emitSuccess("已退出全屏")
            controller.closeSilently()
            demoControllers.removeAll { $0 === controller }
            scheduleStep(.minimize)
        }
        controller.onMiniaturize = { [weak self, weak controller] triggered in
            guard let self, let controller, triggered, step == .minimize else { return }
            emitSuccess("演示窗口已最小化")
            Task { [weak self, weak controller] in
                try? await Task.sleep(for: .milliseconds(650))
                guard let self, let controller else { return }
                controller.closeSilently()
                demoControllers.removeAll { $0 === controller }
                scheduleStep(.closeAll)
            }
        }
        demoControllers = [controller]
        controller.show()
    }

    private func showCloseAllDemoWindows() {
        cleanupDemoWindows()
        var controllers: [TutorialDemoWindowController] = []
        for index in 1 ... 3 {
            let controller = TutorialDemoWindowController(kind: .closeAll(index))
            controller.onClose = { [weak self, weak controller] triggered in
                guard let self, let controller else { return }
                demoControllers.removeAll { $0 === controller }
                guard triggered, step == .closeAll, demoControllers.isEmpty else { return }
                window?.makeKeyAndOrderFront(nil)
                emitSuccess("三个演示窗口已全部关闭")
                scheduleMove(to: .pinnedImage)
            }
            controllers.append(controller)
        }
        demoControllers = controllers
        for (index, controller) in controllers.enumerated() {
            controller.show(offset: CGFloat(index) * 34)
        }
        controllers.last?.window?.makeKeyAndOrderFront(nil)
    }

    private func cleanupDemoWindows() {
        let controllers = demoControllers
        demoControllers.removeAll()
        controllers.forEach { $0.closeSilently() }
    }

    private func cleanupTutorialPinnedImage() {
        guard let id = tutorialPinnedImageID else { return }
        tutorialPinnedImageID = nil
        isCleaningUp = true
        dismissPinnedImage?(id)
        isCleaningUp = false
    }

    private func cleanupTransientWindows() {
        cleanupDemoWindows()
        cleanupTutorialPinnedImage()
    }

    private func finishPresentation() {
        transitionTask?.cancel()
        cleanupTransientWindows()
        isPresenting = false
        waitingForSearchReturn = false
        feedback = nil
        onClose?()
    }
}

private enum TutorialDemoKind: Equatable {
    case close
    case fullScreen
    case minimize
    case closeAll(Int)
}

@MainActor
private final class TutorialDemoWindowModel: ObservableObject {
    @Published var instruction: String
    let gestureIdentifier: String

    init(instruction: String, gestureIdentifier: String) {
        self.instruction = instruction
        self.gestureIdentifier = gestureIdentifier
    }
}

@MainActor
private final class TutorialDemoWindowController: NSWindowController, NSWindowDelegate {
    let model: TutorialDemoWindowModel
    var onClose: ((Bool) -> Void)?
    var onMiniaturize: ((Bool) -> Void)?
    var onEnterFullScreen: ((Bool) -> Void)?
    var onExitFullScreen: ((Bool) -> Void)?

    private var gestureTriggered = false
    private var closesSilently = false

    init(kind: TutorialDemoKind) {
        let title: String
        let instruction: String
        let gesture: String
        switch kind {
        case .close:
            title = "演示窗口：关闭我"
            instruction = "画“下 → 右”关闭这个窗口"
            gesture = "DOWN-RIGHT"
        case .fullScreen:
            title = "演示窗口：全屏切换"
            instruction = "画右上直线进入全屏"
            gesture = "UP_RIGHT"
        case .minimize:
            title = "演示窗口：最小化我"
            instruction = "画左下直线将这个窗口最小化"
            gesture = "DOWN_LEFT"
        case let .closeAll(index):
            title = "演示窗口 \(index)"
            instruction = "画“下 → 左”同时关闭三个窗口"
            gesture = "DOWN-LEFT"
        }
        model = TutorialDemoWindowModel(instruction: instruction, gestureIdentifier: gesture)
        let rootView = TutorialDemoWindowView(model: model)
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = title
        window.setContentSize(NSSize(width: 430, height: 270))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(offset: CGFloat = 0) {
        window?.center()
        if let origin = window?.frame.origin {
            window?.setFrameOrigin(CGPoint(x: origin.x + offset, y: origin.y - offset))
        }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func closeByGesture() {
        gestureTriggered = true
        window?.performClose(nil)
    }

    func minimizeByGesture() {
        gestureTriggered = true
        window?.miniaturize(nil)
    }

    func toggleFullScreenByGesture() {
        gestureTriggered = true
        window?.toggleFullScreen(nil)
    }

    func closeSilently() {
        closesSilently = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(gestureTriggered && !closesSilently)
        gestureTriggered = false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        onMiniaturize?(gestureTriggered)
        gestureTriggered = false
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        onEnterFullScreen?(gestureTriggered)
        gestureTriggered = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        onExitFullScreen?(gestureTriggered)
        gestureTriggered = false
    }
}

private struct TutorialDemoWindowView: View {
    @ObservedObject var model: TutorialDemoWindowModel

    var body: some View {
        VStack(spacing: 18) {
            GesturePreview(identifier: model.gestureIdentifier)
                .frame(width: 150, height: 100)
            Text(model.instruction)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("这里只是教程演示，不会影响你的其他窗口")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TutorialView: View {
    @ObservedObject var coordinator: TutorialCoordinator
    @ObservedObject var permissionAuthorizationCoordinator: PermissionAuthorizationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            tutorialHeader
            Divider()
            ScrollView {
                pageContent
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
            }
            Divider()
            navigationBar
        }
        .frame(minWidth: 780, minHeight: 600)
        .overlay {
            if let successEventID = coordinator.successEventID {
                TutorialSuccessBurst(eventID: successEventID)
                    .id(successEventID)
                    .allowsHitTesting(false)
            }
        }
    }

    private var tutorialHeader: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(coordinator.page.title)
                        .font(.title2.weight(.semibold))
                    Text(coordinator.page.subtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(coordinator.page.rawValue + 1) / \(TutorialPage.allCases.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                ForEach(TutorialPage.allCases) { page in
                    Capsule()
                        .fill(page.rawValue <= coordinator.page.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 5)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch coordinator.page {
        case .welcome: welcomePage
        case .editing: editingPage
        case .browsing: browsingPage
        case .windows: windowPage
        case .pinnedImage: pinnedImagePage
        case .ocr: ocrPage
        case .finish: finishPage
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 70))
                .foregroundStyle(.tint)
            Text("按住鼠标右键并移动；触控板请使用能够持续按住的辅助点按。教程会让每个手势产生真实、可验证的结果。")
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 650)
            VStack(spacing: 12) {
                tutorialPermissionRow(.accessibility, icon: "hand.raised.fill", purpose: "手势监听与动作执行")
                Divider()
                tutorialPermissionRow(.screenRecording, icon: "rectangle.dashed.badge.record", purpose: "贴图、区域截图与 OCR")
                Text("辅助功能是练习手势所必需的；屏幕录制可以稍后授权。MouseTrails 不会拦截 macOS 原生多指手势。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 14) {
                Image(systemName: "rectangle.and.hand.point.up.left.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("经常使用触控板？")
                        .font(.headline)
                    Text("建议把触控板的按压力度调整为“轻”，以更轻松地使用 MouseTrails。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("前往设置") {
                    PermissionCoordinator.openTrackpadSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(16)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var editingPage: some View {
        taskLayout {
            if coordinator.expectedGestureIdentifier == "UP" {
                VStack(spacing: 10) {
                    TutorialTextField(
                        text: .constant(TutorialCoordinator.editingSentence),
                        isEditable: false,
                        selectionToken: coordinator.copySelectionToken
                    )
                    .frame(height: 44)
                    Text("这个手势不仅能复制文字，在 Finder 中也可以复制选中的文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                TutorialTextField(
                    text: Binding(
                        get: { coordinator.pasteText },
                        set: { coordinator.updatePastedText($0) }
                    ),
                    isEditable: true,
                    selectionToken: coordinator.pasteFocusToken
                )
                .frame(height: 44)
            }
        }
    }

    private var browsingPage: some View {
        taskLayout {
            if coordinator.expectedGestureIdentifier == "LETTER_S" {
                TutorialTextField(
                    text: .constant(TutorialCoordinator.searchPhrase),
                    isEditable: false,
                    selectionToken: coordinator.searchSelectionToken
                )
                .frame(height: 44)
            } else {
                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Spacer()
                        Text("示例浏览器 · 第 \(coordinator.browserPageIndex + 1) 页")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    Divider()
                    Text(coordinator.browserPageIndex == 0 ? "这里是上一页" : "这里是下一页")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 90)
                }
                .padding(18)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var windowPage: some View {
        taskLayout {
            VStack(spacing: 10) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                Text("请在弹出的演示窗口中完成当前任务")
                    .font(.headline)
                Text("关闭、全屏、最小化和关闭全部都只作用于教程临时窗口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pinnedImagePage: some View {
        taskLayout {
            if coordinator.expectedGestureIdentifier == "SQUARE_CLOCKWISE" {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 54))
                        .foregroundStyle(.indigo)
                    Text("把这张示例卡片变成贴图")
                        .font(.title2.weight(.bold))
                    Text("用顺时针方框沿卡片边缘圈选")
                        .foregroundStyle(.secondary)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(colors: [.indigo.opacity(0.18), .cyan.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18)
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(PinnedImageTutorialStep.allCases.enumerated()), id: \.element) { index, item in
                        HStack(spacing: 10) {
                            Image(systemName: coordinator.completedPinnedImageSteps.contains(item)
                                ? "checkmark.circle.fill"
                                : "\(index + 1).circle.fill")
                                .foregroundStyle(
                                    coordinator.completedPinnedImageSteps.contains(item)
                                        ? Color.green
                                        : Color.accentColor
                                )
                            Text(item.title)
                            Spacer()
                            if coordinator.completedPinnedImageSteps.contains(item) {
                                Text("✅")
                                    .accessibilityLabel("已完成")
                            }
                        }
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var ocrPage: some View {
        taskLayout {
            VStack(spacing: 12) {
                Text(TutorialCoordinator.ocrSample)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .padding(26)
                    .frame(maxWidth: .infinity)
                    .background(Color.yellow.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                if let recognizedText = coordinator.recognizedText {
                    Label("识别结果：\(recognizedText)", systemImage: "text.viewfinder")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var finishPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 76))
                .foregroundStyle(.green)
            Text("MouseTrails 已经可以开始使用")
                .font(.largeTitle.weight(.bold))
            Text("你完成了 \(coordinator.completedGestureCount) 次真实操作。以后可在“设置 → 通用 → 使用教程”随时重新体验。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 330)
    }

    private func taskLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 20) {
            if let identifier = coordinator.expectedGestureIdentifier {
                HStack(spacing: 22) {
                    GesturePreview(identifier: identifier)
                        .frame(width: 150, height: 105)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前只需完成这一项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(TutorialCoordinator.displayName(for: identifier))
                            .font(.title2.weight(.bold))
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            content()
            feedbackView
        }
    }

    private var feedbackView: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.draw")
                .foregroundStyle(Color.accentColor)
            Text(coordinator.feedback ?? "按照当前示例完成操作")
                .font(.headline)
            Spacer()
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tutorialPermissionRow(_ permission: SystemPermission, icon: String, purpose: String) -> some View {
        let granted = permissionAuthorizationCoordinator.snapshot[permission] == .granted
        return HStack(spacing: 12) {
            Label(PermissionCoordinator.displayName(for: permission), systemImage: icon)
                .frame(width: 120, alignment: .leading)
            Text(purpose)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Label(granted ? "已授权" : "未授权", systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.red)
                .frame(width: 82, alignment: .leading)
            if !granted {
                Button("授权") { permissionAuthorizationCoordinator.beginAuthorization(for: permission) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var navigationBar: some View {
        HStack {
            if coordinator.page != .finish {
                Button("跳过教程") { coordinator.skip() }
                    .foregroundStyle(.secondary)
                if coordinator.page != .welcome {
                    Button("跳过本场景") { coordinator.skipCurrentScene() }
                }
            }
            Spacer()
            if coordinator.page != .welcome {
                Button("上一个场景") { coordinator.previousScene() }
            }
            if coordinator.page == .welcome {
                Button("开始体验") { coordinator.nextFromWelcome() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(permissionAuthorizationCoordinator.snapshot[.accessibility] != .granted)
            } else if coordinator.page == .finish {
                Button("完成") { coordinator.finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }
}

private struct TutorialTextField: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let selectionToken: UUID

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 18, weight: .medium)
        field.alignment = .center
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.isSelectable = true
        field.isEditable = isEditable
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEditable = isEditable
        if field.stringValue != text { field.stringValue = text }
        guard context.coordinator.lastSelectionToken != selectionToken else { return }
        context.coordinator.lastSelectionToken = selectionToken
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            if self.isEditable {
                field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.count, length: 0)
            } else {
                field.selectText(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TutorialTextField
        var lastSelectionToken: UUID?

        init(parent: TutorialTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

private struct TutorialSuccessBurst: View {
    let eventID: UUID
    @State private var startedAt = Date()
    @State private var isActive = true

    private let colors: [Color] = [.pink, .orange, .yellow, .green, .cyan, .blue, .purple]

    var body: some View {
        if isActive {
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                let progress = min(max(elapsed / 1.2, 0), 1)
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for index in 0 ..< 28 {
                        let angle = Double(index) / 28 * Double.pi * 2 + Double(index % 3) * 0.17
                        let distance = 34 + 150 * easeOut(progress) * (0.72 + Double(index % 5) * 0.07)
                        let point = CGPoint(
                            x: center.x + cos(angle) * distance,
                            y: center.y + sin(angle) * distance + 90 * progress * progress
                        )
                        let diameter = 5 + Double(index % 4) * 2
                        context.opacity = max(0, 1 - progress)
                        context.fill(
                            Path(ellipseIn: CGRect(
                                x: point.x - diameter / 2,
                                y: point.y - diameter / 2,
                                width: diameter,
                                height: diameter
                            )),
                            with: .color(colors[index % colors.count])
                        )
                    }
                    context.opacity = max(0, 1 - progress * 0.85)
                    let thumb = context.resolve(Text("👍").font(.system(size: 72)))
                    context.draw(thumb, at: CGPoint(x: center.x, y: center.y - 24 * easeOut(progress)))
                }
            }
            .transition(.opacity)
            .task(id: eventID) {
                startedAt = Date()
                try? await Task.sleep(for: .milliseconds(1_250))
                isActive = false
            }
        }
    }

    private func easeOut(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
    }
}
