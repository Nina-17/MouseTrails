import Combine
import Foundation
import Sparkle

/// Bridges the app's SwiftUI/AppKit controls to Sparkle's standard updater.
/// Sparkle owns update scheduling, download state, signature verification and
/// installation; this type deliberately keeps no parallel update preferences.
@MainActor
final class UpdateCoordinator: ObservableObject {
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            guard updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            notifyChange()
        }
    }

    @Published var automaticallyDownloadsUpdates: Bool {
        didSet {
            guard updater.automaticallyDownloadsUpdates != automaticallyDownloadsUpdates else { return }
            updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
            notifyChange()
        }
    }

    @Published private(set) var canCheckForUpdates = false

    var onStateChange: (@MainActor () -> Void)?

    let currentVersionString: String
    private let updaterController: SPUStandardUpdaterController
    private var observations: [NSKeyValueObservation] = []

    private var updater: SPUUpdater { updaterController.updater }

    init(
        currentVersionString: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
    ) {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        self.currentVersionString = currentVersionString
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        canCheckForUpdates = controller.updater.canCheckForUpdates

        observations = [
            controller.updater.observe(\SPUUpdater.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor [weak self] in
                    self?.canCheckForUpdates = updater.canCheckForUpdates
                    self?.notifyChange()
                }
            }
        ]
    }

    var isBusy: Bool { !canCheckForUpdates }

    var menuTitle: String {
        isBusy ? "正在检查更新…" : "检查更新…"
    }

    var statusText: String {
        if isBusy { return "Sparkle 正在处理更新…" }
        return "更新包会先验证签名，再由 Sparkle 安装。"
    }

    // Kept as no-ops so the app lifecycle remains explicit at the call site.
    func start() {}
    func stop() {}

    func checkForUpdates(manual: Bool) {
        guard canCheckForUpdates else { return }
        DiagnosticLogger.shared.log("Sparkle update check started; manual=\(manual)")
        updaterController.checkForUpdates(nil)
    }

    private func notifyChange() {
        onStateChange?()
    }
}
