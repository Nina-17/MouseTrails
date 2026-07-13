import Foundation
import MouseIncCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var draft: AppConfiguration
    @Published private(set) var saveMessage: String?
    private(set) var bindingIDs: [UUID]

    private let saveHandler: @MainActor (AppConfiguration) throws -> Void
    private let exportHandler: @MainActor (AppConfiguration, URL) throws -> Void
    private let restoreHandler: @MainActor (URL) throws -> AppConfiguration

    init(
        configuration: AppConfiguration,
        saveHandler: @escaping @MainActor (AppConfiguration) throws -> Void,
        exportHandler: @escaping @MainActor (AppConfiguration, URL) throws -> Void = { _, _ in },
        restoreHandler: @escaping @MainActor (URL) throws -> AppConfiguration = { _ in
            throw CocoaError(.fileReadUnsupportedScheme)
        }
    ) {
        draft = configuration
        bindingIDs = configuration.bindings.map { _ in UUID() }
        self.saveHandler = saveHandler
        self.exportHandler = exportHandler
        self.restoreHandler = restoreHandler
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
        bindingIDs = configuration.bindings.map { _ in UUID() }
        draft = configuration
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
        bindingIDs.remove(at: index)
        draft.bindings.remove(at: index)
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
            draft.bindings[bindingIndex].name == "新手势",
            let action = draft.bindings[bindingIndex].actions.first
        else { return }
        draft.bindings[bindingIndex].name = Self.actionName(action)
    }

    private static func gestureSortKey(for gesture: String) -> (category: Int, order: Int, name: String) {
        let identifier = gesture.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !identifier.isEmpty else { return (5, 0, "") }

        let categories: [[String]] = [
            ["UP", "DOWN", "LEFT", "RIGHT"],
            ["UP_LEFT", "UP_RIGHT", "DOWN_LEFT", "DOWN_RIGHT"],
            ["UP-LEFT", "UP-RIGHT", "DOWN-LEFT", "DOWN-RIGHT", "LEFT-UP", "LEFT-DOWN", "RIGHT-UP", "RIGHT-DOWN"],
            ["SQUARE_CLOCKWISE", "SQUARE_COUNTERCLOCKWISE", "LETTER_S", "LETTER_W"]
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
            case .minimize: return "最小化窗口"
            case .close: return "关闭窗口"
            case .closeAll: return "关闭所有类似窗口"
            case nil: return "窗口操作"
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
