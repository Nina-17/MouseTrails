import AppKit
import MouseIncCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsViewModel
    private let navigation = SettingsNavigation()
    private let launchAtLogin: LaunchAtLoginController
    private let permissionAuthorizationCoordinator: PermissionAuthorizationCoordinator
    private let closeHandler: @MainActor () -> Void

    init(
        configuration: AppConfiguration,
        customGestureRecorder: CustomGestureRecordingController,
        saveHandler: @escaping @MainActor (AppConfiguration) throws -> Void,
        exportHandler: @escaping @MainActor (AppConfiguration, URL) throws -> Void,
        restoreHandler: @escaping @MainActor (URL) throws -> AppConfiguration,
        launchAtLogin: LaunchAtLoginController,
        updateCoordinator: UpdateCoordinator,
        permissionAuthorizationCoordinator: PermissionAuthorizationCoordinator,
        closeHandler: @escaping @MainActor () -> Void = {}
    ) {
        self.closeHandler = closeHandler
        self.launchAtLogin = launchAtLogin
        self.permissionAuthorizationCoordinator = permissionAuthorizationCoordinator
        model = SettingsViewModel(
            configuration: configuration,
            customGestureRecorder: customGestureRecorder,
            saveHandler: saveHandler,
            exportHandler: exportHandler,
            restoreHandler: restoreHandler
        )
        let hostingController = NSHostingController(
            rootView: SettingsView(
                model: model,
                navigation: navigation,
                launchAtLogin: launchAtLogin,
                updateCoordinator: updateCoordinator,
                permissionAuthorizationCoordinator: permissionAuthorizationCoordinator
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MouseTrails 设置"
        window.setContentSize(NSSize(width: 1040, height: 740))
        window.contentMinSize = NSSize(width: 820, height: 620)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(configuration: AppConfiguration, page: SettingsPage? = nil) {
        if let page {
            navigation.selectedPage = page
        }
        model.reload(configuration)
        launchAtLogin.refresh()
        permissionAuthorizationCoordinator.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if model.customGestureRecorder.isRecording {
            model.customGestureRecorder.cancel()
        }
        closeHandler()
    }
}
