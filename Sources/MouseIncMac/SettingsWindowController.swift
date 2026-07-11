import AppKit
import MouseIncCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let model: SettingsViewModel

    init(
        configuration: AppConfiguration,
        saveHandler: @escaping @MainActor (AppConfiguration) throws -> Void
    ) {
        model = SettingsViewModel(configuration: configuration, saveHandler: saveHandler)
        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MouseIncMac 设置"
        window.setContentSize(NSSize(width: 760, height: 700))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
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
}
