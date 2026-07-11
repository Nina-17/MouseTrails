import Foundation
import MouseIncCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var draft: AppConfiguration
    @Published private(set) var saveMessage: String?
    private(set) var bindingIDs: [UUID]

    private let saveHandler: @MainActor (AppConfiguration) throws -> Void

    init(
        configuration: AppConfiguration,
        saveHandler: @escaping @MainActor (AppConfiguration) throws -> Void
    ) {
        draft = configuration
        bindingIDs = configuration.bindings.map { _ in UUID() }
        self.saveHandler = saveHandler
    }

    var validation: ConfigurationValidationResult {
        draft.validate()
    }

    var canSave: Bool {
        validation.isValid
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
                gesture: "UP_RIGHT",
                name: "新手势",
                actions: [.init(type: .windowAction, value: WindowAction.center.rawValue)]
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
        draft.bindings[bindingIndex].actions.append(
            .init(type: .keyStroke, value: "Command+C")
        )
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
}
