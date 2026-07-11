import Foundation
import MouseIncCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var draft: AppConfiguration
    @Published private(set) var saveMessage: String?

    private let saveHandler: @MainActor (AppConfiguration) throws -> Void

    init(
        configuration: AppConfiguration,
        saveHandler: @escaping @MainActor (AppConfiguration) throws -> Void
    ) {
        draft = configuration
        self.saveHandler = saveHandler
    }

    var validation: ConfigurationValidationResult {
        draft.validate()
    }

    var canSave: Bool {
        validation.isValid
    }

    func reload(_ configuration: AppConfiguration) {
        draft = configuration
        saveMessage = nil
    }

    func addBinding() {
        draft.bindings.append(
            GestureBinding(
                gesture: "UP_RIGHT",
                name: "新手势",
                actions: [.init(type: .windowAction, value: WindowAction.center.rawValue)]
            )
        )
    }

    func removeBinding(at index: Int) {
        guard draft.bindings.indices.contains(index) else { return }
        draft.bindings.remove(at: index)
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
