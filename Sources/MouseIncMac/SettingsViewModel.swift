import Combine
import Foundation
import MouseIncCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var draft: AppConfiguration
    @Published private(set) var saveMessage: String?
    private(set) var bindingIDs: [UUID]
    let customGestureRecorder: CustomGestureRecordingController

    private let saveHandler: @MainActor (AppConfiguration) throws -> Void
    private let exportHandler: @MainActor (AppConfiguration, URL) throws -> Void
    private let restoreHandler: @MainActor (URL) throws -> AppConfiguration
    private var cancellables: Set<AnyCancellable> = []

    init(
        configuration: AppConfiguration,
        customGestureRecorder: CustomGestureRecordingController = CustomGestureRecordingController(),
        saveHandler: @escaping @MainActor (AppConfiguration) throws -> Void,
        exportHandler: @escaping @MainActor (AppConfiguration, URL) throws -> Void = { _, _ in },
        restoreHandler: @escaping @MainActor (URL) throws -> AppConfiguration = { _ in
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    ) {
        let normalizedConfiguration = Self.normalizingAutomaticBindingNames(in: configuration)
        draft = normalizedConfiguration
        bindingIDs = normalizedConfiguration.bindings.map { _ in UUID() }
        self.customGestureRecorder = customGestureRecorder
        self.saveHandler = saveHandler
        self.exportHandler = exportHandler
        self.restoreHandler = restoreHandler
        customGestureRecorder.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var validation: ConfigurationValidationResult {
        draft.validate()
    }

    var canSave: Bool {
        validation.isValid
    }

    var orderedBindingIDs: [UUID] {
        bindingIDs.enumerated()
            .sorted { lhs, rhs in
                let lhsKey = Self.gestureSortKey(for: draft.bindings[lhs.offset].gesture)
                let rhsKey = Self.gestureSortKey(for: draft.bindings[rhs.offset].gesture)
                if lhsKey.category != rhsKey.category { return lhsKey.category < rhsKey.category }
                if lhsKey.order != rhsKey.order { return lhsKey.order < rhsKey.order }
                if lhsKey.name != rhsKey.name { return lhsKey.name < rhsKey.name }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func reload(_ configuration: AppConfiguration) {
        if customGestureRecorder.isRecording {
            customGestureRecorder.cancel()
        }
        let normalizedConfiguration = Self.normalizingAutomaticBindingNames(in: configuration)
        bindingIDs = normalizedConfiguration.bindings.map { _ in UUID() }
        draft = normalizedConfiguration
        saveMessage = nil
    }

    func addBinding() {
        bindingIDs.append(UUID())
        draft.bindings.append(
            GestureBinding(
                gesture: "",
                name: "新手势",
                actions: []
            )
        )
    }

    func removeBinding(at index: Int) {
        guard
            draft.bindings.indices.contains(index),
            bindingIDs.indices.contains(index)
        else { return }
        let removedID = bindingIDs[index]
        let removedGesture = draft.bindings[index].gesture
        if customGestureRecorder.targetBindingID == removedID, customGestureRecorder.isRecording {
            customGestureRecorder.cancel()
        }
        bindingIDs.remove(at: index)
        draft.bindings.remove(at: index)
        if removedGesture.uppercased().hasPrefix("CUSTOM_"),
           !draft.bindings.contains(where: {
               $0.gesture.caseInsensitiveCompare(removedGesture) == .orderedSame
           }) {
            draft.customGestures.removeAll {
                $0.identifier.caseInsensitiveCompare(removedGesture) == .orderedSame
            }
        }
    }

    func binding(at index: Int) -> GestureBinding? {
        guard draft.bindings.indices.contains(index) else { return nil }
        return draft.bindings[index]
    }

    func bindingIndex(for id: UUID) -> Int? {
        bindingIDs.firstIndex(of: id)
    }

    func setGesture(_ gesture: String, for bindingIndex: Int) {
        guard draft.bindings.indices.contains(bindingIndex) else { return }
        draft.bindings[bindingIndex].gesture = gesture
    }

    func customGesture(for identifier: String) -> CustomGestureDefinition? {
        draft.customGestures.first {
            $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame
        }
    }

    func previewPoints(for identifier: String) -> [CGPoint]? {
        customGesture(for: identifier)?.previewPoints
    }

    func displayName(forCustomGesture identifier: String) -> String? {
        customGesture(for: identifier)?.name
    }

    func startCustomGestureRecording(at bindingIndex: Int) {
        guard
            draft.bindings.indices.contains(bindingIndex),
            bindingIDs.indices.contains(bindingIndex)
        else { return }

        let bindingID = bindingIDs[bindingIndex]
        let currentIdentifier = draft.bindings[bindingIndex].gesture
        let existing = customGesture(for: currentIdentifier)
        let identifier = existing?.identifier ?? "CUSTOM_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let name = existing?.name ?? "自定义轨迹 \(draft.customGestures.count + 1)"

        customGestureRecorder.start(targetBindingID: bindingID) { [weak self] samples in
            guard let self, let targetIndex = self.bindingIDs.firstIndex(of: bindingID) else {
                return .init(succeeded: false, message: "目标手势已不存在")
            }
            do {
                let otherCustomGestures = self.draft.customGestures.filter {
                    $0.identifier.caseInsensitiveCompare(identifier) != .orderedSame
                }
                let fixedIdentifiers = Set(self.draft.bindings.compactMap { binding -> String? in
                    let value = binding.gesture.trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.uppercased().hasPrefix("CUSTOM_") ? nil : value.uppercased()
                })
                let result = try CustomGestureTrainer.train(
                    identifier: identifier,
                    name: name,
                    rawSamples: samples,
                    existingCustomGestures: otherCustomGestures,
                    fixedGestureIdentifiers: fixedIdentifiers
                )
                if let index = self.draft.customGestures.firstIndex(where: {
                    $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame
                }) {
                    self.draft.customGestures[index] = result.definition
                } else {
                    self.draft.customGestures.append(result.definition)
                }
                self.draft.bindings[targetIndex].gesture = identifier
                let suffix = result.warnings.isEmpty
                    ? ""
                    : "；提示：\(result.warnings.joined(separator: "；"))"
                return .init(
                    succeeded: true,
                    message: "训练完成，相似度 \(Int(result.cohesionScore * 100))%\(suffix)"
                )
            } catch let error as CustomGestureTrainingError {
                switch error {
                case .invalidSampleCount:
                    return .init(succeeded: false, message: "需要完整录制 3 次")
                case let .invalidSample(index):
                    return .init(succeeded: false, message: "第 \(index + 1) 次轨迹过短，请重新录制")
                case let .inconsistentSamples(score):
                    return .init(
                        succeeded: false,
                        message: "三次轨迹差异过大（\(Int(score * 100))%），请重新录制"
                    )
                }
            } catch {
                return .init(succeeded: false, message: error.localizedDescription)
            }
        }
    }

    func useApplication(at url: URL, for bindingIndex: Int) -> Bool {
        guard
            draft.bindings.indices.contains(bindingIndex),
            url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
            let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
        else { return false }
        draft.bindings[bindingIndex].bundleIdentifiers = [bundleIdentifier]
        return true
    }

    func issues(for bindingIndex: Int) -> [ConfigurationIssue] {
        validation.issues.filter { $0.path.hasPrefix("bindings[\(bindingIndex)]") }
    }

    func addAction(to bindingIndex: Int) {
        guard draft.bindings.indices.contains(bindingIndex) else { return }
        let action = ActionDefinition(type: .keyStroke, value: "Command+C")
        draft.bindings[bindingIndex].actions.append(action)
    }

    func setActionType(
        _ kind: ActionDefinition.Kind,
        value: String,
        actionIndex: Int,
        bindingIndex: Int
    ) {
        guard
            draft.bindings.indices.contains(bindingIndex),
            draft.bindings[bindingIndex].actions.indices.contains(actionIndex)
        else { return }
        draft.bindings[bindingIndex].actions[actionIndex] = ActionDefinition(type: kind, value: value)
    }

    func setActionValue(
        _ value: String,
        actionIndex: Int,
        bindingIndex: Int
    ) {
        guard
            draft.bindings.indices.contains(bindingIndex),
            draft.bindings[bindingIndex].actions.indices.contains(actionIndex)
        else { return }
        draft.bindings[bindingIndex].actions[actionIndex].value = value
        updateDefaultNameIfNeeded(at: bindingIndex)
    }

    func removeAction(at actionIndex: Int, from bindingIndex: Int) {
        guard
            draft.bindings.indices.contains(bindingIndex),
            draft.bindings[bindingIndex].actions.indices.contains(actionIndex)
        else { return }
        draft.bindings[bindingIndex].actions.remove(at: actionIndex)
    }

    func save() {
        guard canSave else {
            saveMessage = "请先修复配置错误"
            return
        }
        do {
            try saveHandler(draft)
            saveMessage = "已保存并生效"
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    func export(to url: URL) {
        guard canSave else {
            saveMessage = "请先修复配置错误"
            return
        }
        do {
            try exportHandler(draft, url)
            saveMessage = "配置已导出"
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    func restore(from url: URL) {
        do {
            reload(try restoreHandler(url))
            saveMessage = "配置已恢复并生效"
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func updateDefaultNameIfNeeded(at bindingIndex: Int) {
        guard
            draft.bindings.indices.contains(bindingIndex),
            Self.isAutomaticallyGeneratedName(draft.bindings[bindingIndex].name),
            let action = draft.bindings[bindingIndex].actions.first
        else { return }
        draft.bindings[bindingIndex].name = Self.actionName(action)
    }

    private static func isAutomaticallyGeneratedName(_ name: String) -> Bool {
        if name == "新手势" || name.hasPrefix("快捷键 ") { return true }
        var names: Set<String> = [
            "打开 URL", "启动应用", "延时", "窗口操作", "系统视图与空间",
            "截图与贴图", "离线 OCR", "搜索选中文字"
        ]
        names.formUnion(WindowAction.allCases.map {
            actionName(.init(type: .windowAction, value: $0.rawValue))
        })
        names.formUnion(SystemViewAction.allCases.map {
            actionName(.init(type: .systemViewAction, value: $0.rawValue))
        })
        names.formUnion(CaptureAction.allCases.map {
            actionName(.init(type: .captureAction, value: $0.rawValue))
        })
        return names.contains(name)
    }

    private static func normalizingAutomaticBindingNames(
        in source: AppConfiguration
    ) -> AppConfiguration {
        var configuration = source
        for index in configuration.bindings.indices {
            guard
                configuration.bindings[index].name != "新手势",
                isAutomaticallyGeneratedName(configuration.bindings[index].name),
                let action = configuration.bindings[index].actions.first
            else { continue }
            configuration.bindings[index].name = actionName(action)
        }
        return configuration
    }

    private static func gestureSortKey(for gesture: String) -> (category: Int, order: Int, name: String) {
        let identifier = gesture.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !identifier.isEmpty else { return (5, 0, "") }

        let categories: [[String]] = [
            ["UP", "DOWN", "LEFT", "RIGHT"],
            ["UP_LEFT", "UP_RIGHT", "DOWN_LEFT", "DOWN_RIGHT"],
            ["UP-LEFT", "UP-RIGHT", "DOWN-LEFT", "DOWN-RIGHT", "LEFT-UP", "LEFT-DOWN", "RIGHT-UP", "RIGHT-DOWN"],
            ["SQUARE_CLOCKWISE", "SQUARE_COUNTERCLOCKWISE", "LETTER_W"]
        ]
        for (category, identifiers) in categories.enumerated() {
            if let order = identifiers.firstIndex(of: identifier) {
                return (category, order, identifier)
            }
        }
        return (4, 0, identifier)
    }

    private static func actionName(_ action: ActionDefinition) -> String {
        switch action.type {
        case .keyStroke: return "快捷键 \(action.value)"
        case .openURL: return "打开 URL"
        case .launchApplication: return "启动应用"
        case .delay: return "延时"
        case .windowAction:
            switch WindowAction(rawValue: action.value) {
            case .center: return "居中窗口"
            case .maximize: return "切换全屏"
            case .fill: return "填充桌面"
            case .restorePreviousSize: return "恢复窗口大小"
            case .tileLeft: return "左半屏"
            case .tileRight: return "右半屏"
            case .tileTop: return "上半屏"
            case .tileBottom: return "下半屏"
            case .tileTopLeft: return "左上四分之一"
            case .tileTopRight: return "右上四分之一"
            case .tileBottomLeft: return "左下四分之一"
            case .tileBottomRight: return "右下四分之一"
            case .minimize: return "最小化窗口"
            case .close: return "关闭窗口"
            case .closeAll: return "关闭所有类似窗口"
            case .quitApplication: return "退出当前应用"
            case nil: return "窗口操作"
            }
        case .systemViewAction:
            switch SystemViewAction(rawValue: action.value) {
            case .missionControl: return "打开调度中心"
            case .appExpose: return "显示当前 App 窗口"
            case .showDesktop: return "显示桌面"
            case .previousSpace: return "上一个空间"
            case .nextSpace: return "下一个空间"
            case .launchpad: return "打开应用视图"
            case nil: return "系统视图与空间"
            }
        case .captureAction:
            switch CaptureAction(rawValue: action.value) {
            case .pinRegion: return "生成贴图"
            case .copyRegion: return "复制截图"
            case .saveRegion: return "保存截图"
            case nil: return "截图与贴图"
            }
        case .ocrAction: return "离线 OCR"
        case .searchSelectedText: return "搜索选中文字"
        }
    }
}
