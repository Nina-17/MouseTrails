import AppKit
import MouseIncCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private let captureCoordinator = CaptureCoordinator()
    private let launchAtLogin = LaunchAtLoginController()
    private let customGestureRecorder = CustomGestureRecordingController()
    private let updateCoordinator = UpdateCoordinator()
    private let permissionAuthorizationCoordinator = PermissionAuthorizationCoordinator()
    private var configuration = AppConfiguration()
    private var statusItem: NSStatusItem?
    private var enabledItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?
    private var permissionItem: NSMenuItem?
    private var lastGestureItem: NSMenuItem?
    private var updateItem: NSMenuItem?
    private var mainMenuUpdateItem: NSMenuItem?
    private var monitor: GestureMonitor?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateCoordinator.onStateChange = { [weak self] in
            self?.updateUpdateMenuItem()
        }
        permissionAuthorizationCoordinator.onSnapshotChange = { [weak self] _ in
            self?.updatePermissionMenus()
        }
        launchAtLogin.onStateChange = { [weak self] _ in
            self?.updateLaunchAtLoginMenuItem()
        }
        launchAtLogin.refresh()
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
        configureMainMenu()

        let overlay = GestureOverlay()
        captureCoordinator.setGestureOverlay(overlay)
        let executor = ActionExecutor(captureActionHandler: { [weak self] action, gestureBounds in
            self?.captureCoordinator.perform(action, gestureBounds: gestureBounds) ?? false
        }, ocrActionHandler: { [weak self] action, gestureBounds in
            self?.captureCoordinator.performOCR(action, gestureBounds: gestureBounds) ?? false
        }, searchSelectedTextHandler: { value in
            SelectedTextSearch.perform(urlTemplate: value)
        }, keyStrokeHandler: { [weak self] keyStroke in
            self?.captureCoordinator.copySelectedPinnedImage(for: keyStroke) ?? false
        })
        let monitor = GestureMonitor(
            configuration: { [weak self] in self?.configuration ?? AppConfiguration() },
            overlay: overlay,
            executor: executor,
            customGestureRecorder: customGestureRecorder
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
        updateCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        updateCoordinator.stop()
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
                accessibilityDescription: "MouseTrails"
            )
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "MouseTrails"
        }

        let menu = NSMenu()
        menu.delegate = self

        let enabledItem = NSMenuItem(
            title: "启用 MouseTrails",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = .off
        enabledItem.image = enabledStatusImage()
        menu.addItem(enabledItem)

        let launchAtLoginItem = NSMenuItem(
            title: "开机自启动 MouseTrails",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        launchAtLoginItem.state = .off
        menu.addItem(launchAtLoginItem)

        let lastGestureItem = NSMenuItem(title: "最近手势：无", action: nil, keyEquivalent: "")
        lastGestureItem.isEnabled = false
        menu.addItem(lastGestureItem)

        let permissionItem = NSMenuItem(
            title: "权限状态：检查中…",
            action: #selector(openPermissions),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

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

        let updateItem = NSMenuItem(
            title: updateCoordinator.menuTitle,
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        let settingsItem = NSMenuItem(
            title: "打开设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "退出 MouseTrails",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApplication.shared
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.autosaveName = "MouseIncMac.StatusItem"
        statusItem.isVisible = true
        self.statusItem = statusItem
        self.enabledItem = enabledItem
        self.launchAtLoginItem = launchAtLoginItem
        self.permissionItem = permissionItem
        self.lastGestureItem = lastGestureItem
        self.updateItem = updateItem
        updateLaunchAtLoginMenuItem()
        updatePermissionMenus()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "MouseTrails")
        applicationMenu.addItem(
            withTitle: "关于 MouseTrails",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        let updateItem = NSMenuItem(
            title: "检查更新…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        applicationMenu.addItem(updateItem)
        mainMenuUpdateItem = updateItem
        applicationMenu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "隐藏 MouseTrails",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = applicationMenu.addItem(
            withTitle: "隐藏其他应用",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(
            withTitle: "显示全部",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "退出 MouseTrails",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "前置所有窗口",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApplication.shared.windowsMenu = windowMenu
        NSApplication.shared.mainMenu = mainMenu
    }

    private func activateForSettings() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func restoreBackgroundActivationPolicy() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    private func enabledStatusImage() -> NSImage? {
        guard configuration.enabled else { return nil }
        return statusCheckmarkImage()
    }

    private func statusCheckmarkImage() -> NSImage? {
        NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: nil
        )
    }

    private func updateEnabledMenuItem() {
        enabledItem?.state = .off
        enabledItem?.image = enabledStatusImage()
    }

    private func updateLaunchAtLoginMenuItem() {
        launchAtLoginItem?.state = .off
        launchAtLoginItem?.image = launchAtLogin.isEnabled ? statusCheckmarkImage() : nil
    }

    private func updateUpdateMenuItem() {
        updateItem?.title = updateCoordinator.menuTitle
        updateItem?.isEnabled = !updateCoordinator.isBusy
        mainMenuUpdateItem?.title = updateCoordinator.menuTitle
        mainMenuUpdateItem?.isEnabled = !updateCoordinator.isBusy
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
        let required = configuration.requiredPermissions.union([.accessibility])
        let missing = SystemPermission.allCases.filter {
            required.contains($0) && permissions[$0] != .granted
        }
        if missing.isEmpty {
            permissionItem?.title = "✅ 权限状态：已授权"
        } else {
            let names = missing.map(permissionName).joined(separator: "、")
            permissionItem?.title = "❌ 权限状态：\(names)未授权"
        }
    }

    private func permissionName(_ permission: SystemPermission) -> String {
        switch permission {
        case .accessibility: return "辅助功能"
        case .screenRecording: return "屏幕录制"
        case .inputMonitoring: return "输入监控"
        }
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        configuration.enabled.toggle()
        updateEnabledMenuItem()
        do {
            try configStore.save(configuration)
        } catch {
            presentError(title: "无法保存配置", message: error.localizedDescription)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
        if let errorMessage = launchAtLogin.errorMessage {
            presentError(title: "无法更新登录时启动", message: errorMessage)
        }
    }

    @objc private func openPermissions() {
        showSettings(page: .permissions)
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
        showSettings(page: nil)
    }

    private func showSettings(page: SettingsPage?) {
        activateForSettings()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                configuration: configuration,
                customGestureRecorder: customGestureRecorder,
                saveHandler: { [weak self] configuration in
                    guard let self else { return }
                    try self.configStore.save(configuration)
                    self.configuration = configuration
                    self.updateEnabledMenuItem()
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
                    self.updateEnabledMenuItem()
                    self.lastGestureItem?.title = "最近手势：配置已恢复"
                    self.updatePermissionMenus()
                    return configuration
                },
                launchAtLogin: launchAtLogin,
                updateCoordinator: updateCoordinator,
                permissionAuthorizationCoordinator: permissionAuthorizationCoordinator,
                closeHandler: { [weak self] in self?.restoreBackgroundActivationPolicy() }
            )
        }
        settingsWindowController?.show(configuration: configuration, page: page)
    }

    @objc private func reloadConfiguration() {
        loadConfiguration()
        updateEnabledMenuItem()
        lastGestureItem?.title = "最近手势：配置已重载"
        if AccessibilityPermission.isGranted {
            startMonitor()
        }
    }

    @objc private func openDiagnostics() {
        NSWorkspace.shared.open(DiagnosticLogger.shared.fileURL)
    }

    @objc private func checkForUpdates() {
        updateCoordinator.checkForUpdates(manual: true)
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        launchAtLogin.refresh()
    }
}
