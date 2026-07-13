import AppKit
import MouseIncCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private let captureCoordinator = CaptureCoordinator()
    private var configuration = AppConfiguration()
    private var statusItem: NSStatusItem?
    private var enabledItem: NSMenuItem?
    private var permissionItem: NSMenuItem?
    private var screenRecordingPermissionItem: NSMenuItem?
    private var inputMonitoringPermissionItem: NSMenuItem?
    private var monitorItem: NSMenuItem?
    private var lastGestureItem: NSMenuItem?
    private var monitor: GestureMonitor?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let permissions = PermissionCoordinator.snapshot
        DiagnosticLogger.shared.log(
            event: .permissionSnapshot,
            metadata: [
                "accessibility": permissions[.accessibility].rawValue,
                "screenRecording": permissions[.screenRecording].rawValue,
                "inputMonitoring": permissions[.inputMonitoring].rawValue
            ]
        )
        loadConfiguration()
        configureStatusItem()
        configureVisibilityFallback()

        let overlay = GestureOverlay()
        let executor = ActionExecutor(captureActionHandler: { [weak self] action, gestureBounds in
            self?.captureCoordinator.perform(action, gestureBounds: gestureBounds) ?? false
        }, ocrActionHandler: { [weak self] action, gestureBounds in
            self?.captureCoordinator.performOCR(action, gestureBounds: gestureBounds) ?? false
        }, searchSelectedTextHandler: { value in
            SelectedTextSearch.perform(urlTemplate: value)
        }, openFocusedApplicationPathHandler: {
            FocusedApplicationPath.open()
        }, keyStrokeHandler: { [weak self] keyStroke in
            self?.captureCoordinator.copySelectedPinnedImage(for: keyStroke) ?? false
        })
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

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        openSettings()
        return true
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "cursorarrow.motionlines",
                accessibilityDescription: "MouseIncMac"
            )
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.title = "MI"
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

        let screenRecordingPermissionItem = NSMenuItem(
            title: "屏幕录制权限：未使用",
            action: #selector(requestScreenRecordingPermission),
            keyEquivalent: ""
        )
        screenRecordingPermissionItem.target = self
        menu.addItem(screenRecordingPermissionItem)

        let inputMonitoringPermissionItem = NSMenuItem(
            title: "输入监控权限：未使用",
            action: nil,
            keyEquivalent: ""
        )
        inputMonitoringPermissionItem.isEnabled = false
        menu.addItem(inputMonitoringPermissionItem)

        let monitorItem = NSMenuItem(title: "监听状态：未启动", action: nil, keyEquivalent: "")
        monitorItem.isEnabled = false
        menu.addItem(monitorItem)

        menu.addItem(.separator())

        let lastGestureItem = NSMenuItem(title: "最近手势：无", action: nil, keyEquivalent: "")
        lastGestureItem.isEnabled = false
        menu.addItem(lastGestureItem)

        let settingsItem = NSMenuItem(
            title: "打开设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

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
        statusItem.autosaveName = "MouseIncMac.StatusItem"
        statusItem.isVisible = true
        self.statusItem = statusItem
        self.enabledItem = enabledItem
        self.permissionItem = permissionItem
        self.screenRecordingPermissionItem = screenRecordingPermissionItem
        self.inputMonitoringPermissionItem = inputMonitoringPermissionItem
        self.monitorItem = monitorItem
        self.lastGestureItem = lastGestureItem
        updatePermissionMenus()
    }

    private func configureVisibilityFallback() {
        let iceIsRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.jordanbaird.Ice"
        }
        guard iceIsRunning else { return }
        NSApplication.shared.setActivationPolicy(.regular)
        DiagnosticLogger.shared.log(
            "Ice menu bar manager detected; Dock fallback enabled"
        )
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
        let permissions = PermissionCoordinator.snapshot
        permissionItem?.title = permissions[.accessibility] == .granted
            ? "辅助功能权限：已授权"
            : "辅助功能权限：需要授权…"
        screenRecordingPermissionItem?.title = permissionTitle(
            name: "屏幕录制",
            state: permissions[.screenRecording],
            currentlyRequired: configuration.requiredPermissions.contains(.screenRecording)
        )
        inputMonitoringPermissionItem?.title = permissionTitle(
            name: "输入监控",
            state: permissions[.inputMonitoring],
            currentlyRequired: false
        )
        monitorItem?.title = monitor?.isRunning == true ? "监听状态：已启动" : "监听状态：未启动"
    }

    private func permissionTitle(
        name: String,
        state: PermissionState,
        currentlyRequired: Bool
    ) -> String {
        if !currentlyRequired, state != .granted {
            return "\(name)权限：当前功能未使用"
        }
        switch state {
        case .granted:
            return "\(name)权限：已授权"
        case .denied:
            return "\(name)权限：未授权"
        case .notDetermined:
            return "\(name)权限：未请求"
        case .unavailable:
            return "\(name)权限：不可用"
        }
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

    @objc private func requestScreenRecordingPermission() {
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        updatePermissionMenus()
    }

    @objc private func openConfiguration() {
        do {
            _ = try configStore.loadOrCreate()
            NSWorkspace.shared.open(configStore.fileURL)
        } catch {
            presentError(title: "无法打开配置", message: error.localizedDescription)
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                configuration: configuration,
                saveHandler: { [weak self] configuration in
                    guard let self else { return }
                    try self.configStore.save(configuration)
                    self.configuration = configuration
                    self.enabledItem?.state = configuration.enabled ? .on : .off
                    self.lastGestureItem?.title = "最近手势：配置已保存"
                    self.updatePermissionMenus()
                },
                exportHandler: { [weak self] configuration, url in
                    guard let self else { return }
                    try self.configStore.export(configuration, to: url)
                },
                restoreHandler: { [weak self] url in
                    guard let self else { throw CocoaError(.fileNoSuchFile) }
                    let configuration = try self.configStore.restore(from: url)
                    self.configuration = configuration
                    self.enabledItem?.state = configuration.enabled ? .on : .off
                    self.lastGestureItem?.title = "最近手势：配置已恢复"
                    self.updatePermissionMenus()
                    return configuration
                }
            )
        }
        settingsWindowController?.show(configuration: configuration)
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
