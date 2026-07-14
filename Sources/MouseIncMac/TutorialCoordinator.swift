import AppKit
import MouseIncCore
import SwiftUI

enum TutorialPage: Int, CaseIterable, Identifiable {
    case welcome
    case defaultGestures
    case windowGestures
    case pinnedImage
    case ocr
    case finish

    var id: Self { self }

    var title: String {
        switch self {
        case .welcome: return "欢迎使用 MouseTrails"
        case .defaultGestures: return "常用默认手势"
        case .windowGestures: return "窗口默认手势"
        case .pinnedImage: return "贴图"
        case .ocr: return "离线 OCR"
        case .finish: return "准备完成"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "先了解绘制方式和必要权限"
        case .defaultGestures: return "复制、粘贴、前进、后退和搜索"
        case .windowGestures: return "安全练习窗口与应用操作"
        case .pinnedImage: return "用顺时针方框截取并悬浮图像"
        case .ocr: return "用逆时针方框识别并复制文字"
        case .finish: return "以后可随时从通用设置重新查看"
        }
    }

    var gestureIdentifiers: [String] {
        switch self {
        case .defaultGestures:
            return ["UP", "DOWN", "LEFT", "RIGHT", "LETTER_S"]
        case .windowGestures:
            return ["DOWN-RIGHT", "UP_RIGHT", "DOWN_LEFT", "DOWN-LEFT", "UP-LEFT"]
        case .pinnedImage:
            return ["SQUARE_CLOCKWISE"]
        case .ocr:
            return ["SQUARE_COUNTERCLOCKWISE"]
        case .welcome, .finish:
            return []
        }
    }
}

@MainActor
final class TutorialCoordinator: NSWindowController, ObservableObject, NSWindowDelegate {
    private enum DefaultsKey {
        static let completedVersion = "tutorial.completedVersion"
    }

    static let currentTutorialVersion = 1

    @Published private(set) var page: TutorialPage = .welcome
    @Published private(set) var selectedIdentifier: String?
    @Published private(set) var practicedIdentifiers: Set<String> = []
    @Published private(set) var feedback: String?
    @Published private(set) var isPresenting = false
    @Published private(set) var successEventID: UUID?

    var onClose: (@MainActor () -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var shouldPresentOnLaunch: Bool {
        defaults.integer(forKey: DefaultsKey.completedVersion) < Self.currentTutorialVersion
    }

    func begin() {
        page = .welcome
        selectedIdentifier = nil
        practicedIdentifiers = []
        feedback = nil
        successEventID = nil
        isPresenting = true
    }

    func show(
        configuration: AppConfiguration,
        permissionAuthorizationCoordinator: PermissionAuthorizationCoordinator
    ) {
        begin()
        let rootView = TutorialView(
            coordinator: self,
            configuration: configuration,
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

    func selectGesture(_ identifier: String) {
        guard page.gestureIdentifiers.contains(identifier) else { return }
        selectedIdentifier = identifier
        feedback = practicedIdentifiers.contains(identifier)
            ? "已完成这项练习，可以再次绘制"
            : "按住右键并绘制目标轨迹"
    }

    func next() {
        guard let index = TutorialPage.allCases.firstIndex(of: page),
              index < TutorialPage.allCases.count - 1 else { return }
        move(to: TutorialPage.allCases[index + 1])
    }

    func previous() {
        guard let index = TutorialPage.allCases.firstIndex(of: page), index > 0 else { return }
        move(to: TutorialPage.allCases[index - 1])
    }

    @discardableResult
    func handleRecognizedGesture(_ identifier: String?) -> Bool {
        guard isPresenting else { return false }
        guard let selectedIdentifier else {
            feedback = "教程打开期间已暂停执行手势动作"
            return true
        }
        guard let identifier else {
            feedback = "没有识别出轨迹，请放大动作后再试一次 \(Self.displayName(for: selectedIdentifier))"
            return true
        }

        if selectedIdentifier.caseInsensitiveCompare(identifier) == .orderedSame {
            practicedIdentifiers.insert(selectedIdentifier)
            feedback = "识别成功：\(Self.displayName(for: selectedIdentifier))"
            successEventID = UUID()
        } else {
            feedback = "识别为 \(Self.displayName(for: identifier))，请再试一次 \(Self.displayName(for: selectedIdentifier))"
        }
        return true
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
        defaults.set(Self.currentTutorialVersion, forKey: DefaultsKey.completedVersion)
        finishPresentation()
    }

    private func finishPresentation() {
        isPresenting = false
        selectedIdentifier = nil
        feedback = nil
        onClose?()
    }

    static func displayName(for identifier: String) -> String {
        switch identifier.uppercased() {
        case "UP": return "上"
        case "DOWN": return "下"
        case "LEFT": return "左"
        case "RIGHT": return "右"
        case "UP_LEFT": return "左上直线"
        case "UP_RIGHT": return "右上直线"
        case "DOWN_LEFT": return "左下直线"
        case "DOWN_RIGHT": return "右下直线"
        case "UP-LEFT": return "上 → 左"
        case "DOWN-RIGHT": return "下 → 右"
        case "DOWN-LEFT": return "下 → 左"
        case "LETTER_S": return "字母 S"
        case "SQUARE_CLOCKWISE": return "顺时针方框"
        case "SQUARE_COUNTERCLOCKWISE": return "逆时针方框"
        default: return identifier
        }
    }

    private func move(to page: TutorialPage) {
        self.page = page
        selectedIdentifier = page.gestureIdentifiers.first
        feedback = selectedIdentifier == nil ? nil : "选择卡片并按住右键绘制"
    }
}

private struct TutorialView: View {
    @ObservedObject var coordinator: TutorialCoordinator
    let configuration: AppConfiguration
    @ObservedObject var permissionAuthorizationCoordinator: PermissionAuthorizationCoordinator

    private let columns = [GridItem(.adaptive(minimum: 135, maximum: 175), spacing: 14)]

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
        case .welcome:
            welcomePage
        case .defaultGestures:
            lessonPage(
                introduction: "这些手势覆盖日常编辑、浏览和搜索。点击一张卡片，再在任意位置按住右键绘制；教程只检查识别结果，不会执行动作。"
            )
        case .windowGestures:
            lessonPage(
                introduction: "窗口类动作在教程中会被安全拦截，因此可以放心练习“退出应用”和“关闭所有窗口”。"
            )
        case .pinnedImage:
            featurePage(
                description: "顺时针画出方框后，MouseTrails 会直接按轨迹包围范围生成贴图，无需二次点击截图。",
                details: [
                    "左键拖动贴图；单击可折叠或恢复",
                    "展开状态右键关闭，折叠状态右键另存为 PNG",
                    "光标在贴图上时滚动可调透明度；展开并选中后按 Command+C 复制"
                ]
            )
        case .ocr:
            featurePage(
                description: "逆时针画出方框后，MouseTrails 会直接识别轨迹包围范围内的文字。",
                details: [
                    "识别由 macOS Vision 在本地完成，不上传图像或文字",
                    "结果自动复制到剪贴板",
                    "完成后通过系统通知显示文字摘要"
                ]
            )
        case .finish:
            finishPage
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 70))
                .foregroundStyle(.tint)
            Text("按住鼠标右键并移动即可绘制手势；触控板请使用能够持续按住的辅助点按方式。松开后 MouseTrails 才会识别轨迹。")
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 650)

            VStack(spacing: 12) {
                HStack {
                    Label("辅助功能权限", systemImage: "hand.raised.fill")
                    Spacer()
                    permissionStatus
                }
                if permissionAuthorizationCoordinator.snapshot[.accessibility] != .granted {
                    Button("打开辅助功能授权") {
                        permissionAuthorizationCoordinator.beginAuthorization(for: .accessibility)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("教程练习需要辅助功能权限。双指滚动、捏合缩放、Mission Control 等 macOS 原生触控板手势不会被拦截。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var permissionStatus: some View {
        let granted = permissionAuthorizationCoordinator.snapshot[.accessibility] == .granted
        return Label(granted ? "已授权" : "未授权", systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(granted ? Color.green : Color.red)
    }

    private func lessonPage(introduction: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(introduction)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(coordinator.page.gestureIdentifiers, id: \.self) { identifier in
                    gestureCard(identifier)
                }
            }
            practiceFeedback
        }
    }

    private func featurePage(description: String, details: [String]) -> some View {
        VStack(spacing: 22) {
            Text(description)
                .font(.title3)
                .multilineTextAlignment(.center)
            if let identifier = coordinator.page.gestureIdentifiers.first {
                gestureCard(identifier)
                    .frame(maxWidth: 230)
            }
            practiceFeedback
            VStack(alignment: .leading, spacing: 12) {
                ForEach(details, id: \.self) { detail in
                    Label(detail, systemImage: "checkmark.circle")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            Text("教程练习只验证方框方向，不会真的截图、生成贴图或执行 OCR。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func gestureCard(_ identifier: String) -> some View {
        let selected = coordinator.selectedIdentifier == identifier
        let practiced = coordinator.practicedIdentifiers.contains(identifier)
        return Button {
            coordinator.selectGesture(identifier)
        } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    GesturePreview(identifier: identifier)
                        .frame(height: 82)
                    if practiced {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .padding(5)
                    }
                }
                Text(TutorialCoordinator.displayName(for: identifier))
                    .font(.headline)
                Text(actionName(for: identifier))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var practiceFeedback: some View {
        HStack(spacing: 10) {
            Image(systemName: feedbackIsSuccess ? "checkmark.circle.fill" : "hand.draw")
                .foregroundStyle(feedbackIsSuccess ? Color.green : Color.accentColor)
            Text(coordinator.feedback ?? "选择一个手势开始练习")
                .font(.headline)
            Spacer()
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var feedbackIsSuccess: Bool {
        coordinator.feedback?.hasPrefix("识别成功") == true
    }

    private var finishPage: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 76))
                .foregroundStyle(.green)
            Text("MouseTrails 已经可以开始使用")
                .font(.largeTitle.weight(.bold))
            Text("教程期间共练习了 \(coordinator.practicedIdentifiers.count) 个手势。以后可在“设置 → 通用 → 使用教程”随时重新打开。")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 330)
    }

    private var navigationBar: some View {
        HStack {
            if coordinator.page != .finish {
                Button("跳过教程") { coordinator.skip() }
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("上一步") { coordinator.previous() }
                .disabled(coordinator.page == .welcome)
            if coordinator.page == .finish {
                Button("完成") { coordinator.finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("下一步") { coordinator.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    private func actionName(for identifier: String) -> String {
        configuration.binding(for: identifier, bundleIdentifier: nil)?.name ?? "未绑定"
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
                    let thumb = context.resolve(
                        Text("👍")
                            .font(.system(size: 72))
                    )
                    context.draw(
                        thumb,
                        at: CGPoint(x: center.x, y: center.y - 24 * easeOut(progress))
                    )
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
