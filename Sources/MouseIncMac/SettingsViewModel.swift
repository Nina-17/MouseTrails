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
        var normalizedConfiguration = configuration
        Self.replaceDefaultBindingNames(in: &normalizedConfiguration)
        draft = normalizedConfiguration
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

    func reload(_ configuration: AppConfiguration) {
        bindingIDs = configuration.bindings.map { _ in UUID() }
        var normalizedConfiguration = configuration
        Self.replaceDefaultBindingNames(in: &normalizedConfiguration)
        draft = normalizedConfiguration
        saveMessage = nil
    }

    func addBinding() {
        let action = ActionDefinition(type: .windowAction, value: WindowAction.center.rawValue)
        bindingIDs.append(UUID())
        draft.bindings.append(
            GestureBinding(
                gesture: "UP_RIGHT",
                name: Self.actionName(action),
                actions: [action]
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

    func moveBinding(from index: Int, by offset: Int) {
        let destination = index + offset
        guard
            draft.bindings.indices.contains(index),
            draft.bindings.indices.contains(destination)
        else { return }
        bindingIDs.swapAt(index, destination)
        draft.bindings.swapAt(index, destination)
    }

    func binding(at index: Int) -> GestureBinding? {
        guard draft.bindings.indices.contains(index) else { return nil }
        return draft.bindings[index]
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
        updateDefaultNameIfNeeded(at: bindingIndex)
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

    private static func replaceDefaultBindingNames(in configuration: inout AppConfiguration) {
        for index in configuration.bindings.indices
        where configuration.bindings[index].name == "新手势" {
            guard let action = configuration.bindings[index].actions.first else { continue }
            configuration.bindings[index].name = actionName(action)
        }
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
