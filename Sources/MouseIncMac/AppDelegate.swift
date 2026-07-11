import AppKit
import MouseIncCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private var configuration = AppConfiguration()
    private var statusItem: NSStatusItem?
    private var enabledItem: NSMenuItem?
    private var permissionItem: NSMenuItem?
    private var monitorItem: NSMenuItem?
    private var lastGestureItem: NSMenuItem?
    private var monitor: GestureMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLogger.shared.log(
            "Application launched; accessibility=\(AccessibilityPermission.isGranted), " +
            "postEvent=\(AccessibilityPermission.isPostEventGranted)"
        )
        loadConfiguration()
        configureStatusItem()

        let overlay = GestureOverlay()
        let executor = ActionExecutor()
        let monitor = GestureMonitor(
            configuration: { [weak self] in self?.configuration ?? AppConfiguration() },
            overlay: overlay,
            executor: executor
        )
        monitor.onGesture = { [weak self] result in
            self?.lastGestureItem?.title = "最近手势：\(result)"
        }
        self.monitor = monitor

        if AccessibilityPermission.isReady {
            startMonitor()
        } else {
            AccessibilityPermission.request()
            updatePermissionMenus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "cursorarrow.motionlines",
                accessibilityDescription: "MouseIncMac"
            )
            button.toolTip = "MouseIncMac"
        }

        let menu = NSMenu()

        let enabledItem = NSMenuItem(
            title: "启用鼠标与触控板手势",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = configuration.enabled ? .on : .off
        menu.addItem(enabledItem)

        let trackpadUsageItem = NSMenuItem(
            title: "触控板：辅助点击并按住后拖动；短点击仍为右键",
            action: nil,
            keyEquivalent: ""
        )
        trackpadUsageItem.isEnabled = false
        menu.addItem(trackpadUsageItem)

        let openTrackpadSettingsItem = NSMenuItem(
            title: "打开触控板设置…",
            action: #selector(openTrackpadSettings),
            keyEquivalent: ""
        )
        openTrackpadSettingsItem.target = self
        menu.addItem(openTrackpadSettingsItem)

        let permissionItem = NSMenuItem(
            title: "辅助功能权限：检查中…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        let monitorItem = NSMenuItem(title: "监听状态：未启动", action: nil, keyEquivalent: "")
        monitorItem.isEnabled = false
        menu.addItem(monitorItem)

        menu.addItem(.separator())

        let lastGestureItem = NSMenuItem(title: "最近手势：无", action: nil, keyEquivalent: "")
        lastGestureItem.isEnabled = false
        menu.addItem(lastGestureItem)

        let openConfigItem = NSMenuItem(
            title: "打开配置文件",
            action: #selector(openConfiguration),
            keyEquivalent: ""
        )
        openConfigItem.target = self
        menu.addItem(openConfigItem)

        let reloadItem = NSMenuItem(
            title: "重新加载配置",
            action: #selector(reloadConfiguration),
            keyEquivalent: ""
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        let diagnosticsItem = NSMenuItem(
            title: "打开诊断日志",
            action: #selector(openDiagnostics),
            keyEquivalent: ""
        )
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 MouseIncMac",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.enabledItem = enabledItem
        self.permissionItem = permissionItem
        self.monitorItem = monitorItem
        self.lastGestureItem = lastGestureItem
        updatePermissionMenus()
    }

    private func loadConfiguration() {
        do {
            configuration = try configStore.loadOrCreate()
        } catch {
            configuration = AppConfiguration()
            presentError(title: "无法读取配置", message: error.localizedDescription)
        }
    }

    private func startMonitor() {
        guard AccessibilityPermission.isGranted else {
            updatePermissionMenus()
            return
        }

        guard let result = monitor?.start() else { return }
        switch result {
        case .started:
            DiagnosticLogger.shared.log("Monitor start result: started")
            updatePermissionMenus()
        case .eventTapCreationFailed:
            DiagnosticLogger.shared.log("Monitor start result: event tap creation failed")
            presentError(
                title: "无法启动鼠标监听",
                message: "请确认已授予“辅助功能”权限，然后退出并重新打开应用。"
            )
            updatePermissionMenus()
        }
    }

    private func updatePermissionMenus() {
        permissionItem?.title = AccessibilityPermission.isGranted
            ? "辅助功能权限：已授权"
            : "辅助功能权限：需要授权…"
        monitorItem?.title = monitor?.isRunning == true ? "监听状态：已启动" : "监听状态：未启动"
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        configuration.enabled.toggle()
        sender.state = configuration.enabled ? .on : .off
        do {
            try configStore.save(configuration)
        } catch {
            presentError(title: "无法保存配置", message: error.localizedDescription)
        }
    }

    @objc private func openAccessibilitySettings() {
        if AccessibilityPermission.isGranted {
            startMonitor()
            return
        }
        AccessibilityPermission.request()
        AccessibilityPermission.openSystemSettings()
        updatePermissionMenus()
    }

    @objc private func openTrackpadSettings() {
        guard
            let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"),
            NSWorkspace.shared.open(url)
        else {
            presentError(
                title: "无法打开触控板设置",
                message: "请手动前往“系统设置 → 触控板”。"
            )
            return
        }
    }

    @objc private func openConfiguration() {
        do {
            _ = try configStore.loadOrCreate()
            NSWorkspace.shared.open(configStore.fileURL)
        } catch {
            presentError(title: "无法打开配置", message: error.localizedDescription)
        }
    }

    @objc private func reloadConfiguration() {
        loadConfiguration()
        enabledItem?.state = configuration.enabled ? .on : .off
        lastGestureItem?.title = "最近手势：配置已重载"
        if AccessibilityPermission.isGranted {
            startMonitor()
        }
    }

    @objc private func openDiagnostics() {
        NSWorkspace.shared.open(DiagnosticLogger.shared.fileURL)
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
