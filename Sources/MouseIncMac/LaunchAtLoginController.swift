import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String?

    var onStateChange: (@MainActor (Bool) -> Void)?

    init() {
        refresh()
    }

    func refresh() {
        let enabled = SMAppService.mainApp.status == .enabled
        isEnabled = enabled
        onStateChange?(enabled)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}
