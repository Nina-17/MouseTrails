import AppKit
import MouseIncCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsViewModel
    private let closeHandler: @MainActor () -> Void

    init(
        configuration: AppConfiguration,
        saveHandler: @escaping @MainActor (AppConfiguration) throws -> Void,
        exportHandler: @escaping @MainActor (AppConfiguration, URL) throws -> Void,
        restoreHandler: @escaping @MainActor (URL) throws -> AppConfiguration,
        closeHandler: @escaping @MainActor () -> Void = {}
    ) {
        self.closeHandler = closeHandler
        model = SettingsViewModel(
            configuration: configuration,
            saveHandler: saveHandler,
            exportHandler: exportHandler,
            restoreHandler: restoreHandler
        )
        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MouseIncMac 设置"
        window.setContentSize(NSSize(width: 1040, height: 740))
        window.minSize = NSSize(width: 920, height: 680)
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

    func show(configuration: AppConfiguration) {
        model.reload(configuration)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        closeHandler()
    }
}
