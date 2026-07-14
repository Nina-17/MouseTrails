import AppKit
import Combine
import MouseIncCore

@MainActor
final class UpdateCoordinator: ObservableObject {
    private enum DefaultsKey {
        static let automaticallyChecks = "updates.automaticallyChecks"
        static let lastSuccessfulCheck = "updates.lastSuccessfulCheck"
    }

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            defaults.set(automaticallyChecksForUpdates, forKey: DefaultsKey.automaticallyChecks)
            scheduleAutomaticCheck()
        }
    }
    @Published private(set) var statusText = "尚未检查更新"
    @Published private(set) var isBusy = false
    @Published private(set) var isDownloading = false
    @Published private(set) var availableRelease: GitHubRelease?

    var onStateChange: (@MainActor () -> Void)?

    let currentVersionString: String
    private let currentVersion: AppVersion
    private let client: GitHubReleaseClient
    private let defaults: UserDefaults
    private var scheduledCheck: Task<Void, Never>?
    private var activeOperation: Task<Void, Never>?

    init(
        client: GitHubReleaseClient = GitHubReleaseClient(),
        defaults: UserDefaults = .standard,
        currentVersionString: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
    ) {
        self.client = client
        self.defaults = defaults
        self.currentVersionString = currentVersionString
        currentVersion = AppVersion(currentVersionString) ?? AppVersion("0.0.0")!
        if defaults.object(forKey: DefaultsKey.automaticallyChecks) == nil {
            automaticallyChecksForUpdates = true
        } else {
            automaticallyChecksForUpdates = defaults.bool(forKey: DefaultsKey.automaticallyChecks)
        }
    }

    var menuTitle: String {
        if isDownloading { return "正在下载更新…" }
        if isBusy { return "正在检查更新…" }
        if let version = availableRelease?.version {
            return "下载 MouseTrails \(version)…"
        }
        return "检查更新…"
    }

    func start() {
        scheduleAutomaticCheck()
    }

    func stop() {
        scheduledCheck?.cancel()
        activeOperation?.cancel()
    }

    func checkForUpdates(manual: Bool) {
        guard !isBusy else { return }
        if manual {
            scheduledCheck?.cancel()
            scheduledCheck = nil
        }
        isBusy = true
        isDownloading = false
        statusText = "正在检查 GitHub Releases…"
        DiagnosticLogger.shared.log("Update check started; manual=\(manual)")
        notifyChange()

        activeOperation = Task { [weak self, client] in
            do {
                let release = try await client.latestRelease()
                guard !Task.isCancelled, let self else { return }
                defaults.set(Date(), forKey: DefaultsKey.lastSuccessfulCheck)
                finishCheck(with: release, manual: manual)
            } catch is CancellationError {
                self?.finishBusyState()
            } catch GitHubReleaseError.noPublishedRelease {
                guard let self else { return }
                defaults.set(Date(), forKey: DefaultsKey.lastSuccessfulCheck)
                availableRelease = nil
                statusText = "GitHub 仓库尚无正式 Release"
                DiagnosticLogger.shared.log("Update check completed; no published release")
                finishBusyState()
                if manual {
                    presentInformation(title: "暂无可用更新", message: statusText)
                }
            } catch {
                guard let self else { return }
                statusText = "检查更新失败：\(error.localizedDescription)"
                DiagnosticLogger.shared.log("Update check failed; error=\(error.localizedDescription)")
                finishBusyState()
                if manual {
                    presentInformation(title: "无法检查更新", message: error.localizedDescription)
                }
            }
        }
    }

    private func finishCheck(with release: GitHubRelease, manual: Bool) {
        guard let latestVersion = release.version else {
            availableRelease = nil
            statusText = "Release 标签不是有效版本号：\(release.tagName)"
            finishBusyState()
            if manual {
                presentInformation(title: "无法识别更新版本", message: statusText)
            }
            return
        }

        if latestVersion > currentVersion {
            availableRelease = release
            statusText = "发现新版本 \(latestVersion)"
            DiagnosticLogger.shared.log("Update available; version=\(latestVersion)")
            finishBusyState()
            if manual { presentAvailableRelease(release) }
        } else {
            availableRelease = nil
            statusText = "已是最新版本（\(currentVersion)）"
            DiagnosticLogger.shared.log("Update check completed; current version is latest")
            finishBusyState()
            if manual {
                presentInformation(title: "MouseTrails 已是最新版本", message: statusText)
            }
        }
    }

    private func presentAvailableRelease(_ release: GitHubRelease) {
        guard let version = release.version else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "MouseTrails \(version) 可用"
        let notes = release.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let notes, !notes.isEmpty {
            alert.informativeText = String(notes.prefix(2_000))
        } else {
            alert.informativeText = "新版本已在 GitHub Releases 发布。"
        }

        if release.preferredDMGAsset != nil {
            alert.addButton(withTitle: "下载并打开")
            alert.addButton(withTitle: "稍后")
            alert.addButton(withTitle: "查看发布页")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                downloadAndOpen(release)
            case .alertThirdButtonReturn:
                NSWorkspace.shared.open(release.pageURL)
            default:
                break
            }
        } else {
            alert.informativeText += "\n\n该 Release 未包含 DMG，请在发布页查看。"
            alert.addButton(withTitle: "打开发布页")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    private func downloadAndOpen(_ release: GitHubRelease) {
        guard let asset = release.preferredDMGAsset, !isBusy else { return }
        isBusy = true
        isDownloading = true
        statusText = "正在下载 \(asset.name)…"
        notifyChange()
        activeOperation = Task { [weak self, client] in
            do {
                let downloads = try FileManager.default.url(
                    for: .downloadsDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let fileURL = try await client.download(asset, to: downloads)
                guard !Task.isCancelled, let self else { return }
                statusText = "已下载 \(asset.name)"
                DiagnosticLogger.shared.log("Update downloaded and verified; asset=\(asset.name)")
                finishBusyState()
                if !NSWorkspace.shared.open(fileURL) {
                    presentInformation(
                        title: "更新已下载",
                        message: "请手动打开 \(fileURL.path)"
                    )
                } else {
                    presentInformation(
                        title: "请完成更新安装",
                        message: "安装器已打开。请将 MouseTrails.app 覆盖当前正在运行的应用：\n\(Bundle.main.bundleURL.path)\n\n若将它拖入另一个 Applications 文件夹，请随后从该新位置启动应用。"
                    )
                }
            } catch {
                guard let self else { return }
                statusText = "下载更新失败：\(error.localizedDescription)"
                DiagnosticLogger.shared.log("Update download failed; error=\(error.localizedDescription)")
                finishBusyState()
                presentInformation(title: "无法下载更新", message: error.localizedDescription)
            }
        }
    }

    private func scheduleAutomaticCheck() {
        scheduledCheck?.cancel()
        guard automaticallyChecksForUpdates else { return }
        if let lastCheck = defaults.object(forKey: DefaultsKey.lastSuccessfulCheck) as? Date,
           Date().timeIntervalSince(lastCheck) < 24 * 60 * 60 {
            return
        }
        scheduledCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.checkForUpdates(manual: false)
        }
    }

    private func finishBusyState() {
        isBusy = false
        isDownloading = false
        activeOperation = nil
        notifyChange()
    }

    private func notifyChange() {
        onStateChange?()
    }

    private func presentInformation(title: String, message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
