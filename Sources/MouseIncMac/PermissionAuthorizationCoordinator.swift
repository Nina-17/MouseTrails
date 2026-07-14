import AppKit
import MouseIncCore
import SwiftUI

@MainActor
final class PermissionAuthorizationCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var snapshot: PermissionSnapshot
    @Published private(set) var selectedPermission: SystemPermission = .accessibility

    var onSnapshotChange: (@MainActor (PermissionSnapshot) -> Void)?

    private var assistantPanel: NSPanel?
    private var refreshTask: Task<Void, Never>?

    override init() {
        snapshot = PermissionCoordinator.snapshot
        super.init()
    }

    func beginAuthorization(for permission: SystemPermission) {
        selectedPermission = permission
        refresh()
        showAssistantPanel()
        _ = PermissionCoordinator.openSystemSettings(for: permission)
        bringAssistantForward()
        startRefreshing()
        DiagnosticLogger.shared.log(
            "Permission authorization opened; permission=\(permission.rawValue)"
        )
    }

    func refresh() {
        let updated = PermissionCoordinator.snapshot
        guard updated != snapshot else { return }
        snapshot = updated
        onSnapshotChange?(updated)
        if updated[selectedPermission] == .granted {
            DiagnosticLogger.shared.log(
                "Permission granted; permission=\(selectedPermission.rawValue)"
            )
        }
    }

    func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([applicationURL])
    }

    func closeAssistant() {
        assistantPanel?.close()
    }

    func windowWillClose(_ notification: Notification) {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private var applicationURL: URL {
        if let runningURL = NSRunningApplication.current.bundleURL,
           runningURL.pathExtension.lowercased() == "app" {
            return runningURL
        }
        return Bundle.main.bundleURL
    }

    private func showAssistantPanel() {
        let rootView = PermissionDragAssistantView(
            coordinator: self,
            applicationURL: applicationURL
        )
        if let assistantPanel {
            assistantPanel.title = "授权 MouseTrails — \(PermissionCoordinator.displayName(for: selectedPermission))"
            assistantPanel.contentViewController = NSHostingController(rootView: rootView)
            assistantPanel.orderFrontRegardless()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "授权 MouseTrails — \(PermissionCoordinator.displayName(for: selectedPermission))"
        panel.contentViewController = NSHostingController(rootView: rootView)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        positionAssistantPanel(panel)
        panel.delegate = self
        assistantPanel = panel
        panel.orderFrontRegardless()
    }

    private func bringAssistantForward() {
        assistantPanel?.orderFrontRegardless()
        Task { [weak self] in
            // System Settings activates asynchronously. Re-order once after its
            // activation so the drag source stays visible beside the permission list.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.assistantPanel?.orderFrontRegardless()
        }
    }

    private func positionAssistantPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.minX + 24,
            y: visibleFrame.midY - panel.frame.height / 2
        ))
    }

    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            for _ in 0 ..< 180 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                refresh()
                if snapshot[selectedPermission] == .granted {
                    return
                }
            }
        }
    }
}

private struct PermissionDragAssistantView: View {
    @ObservedObject var coordinator: PermissionAuthorizationCoordinator
    let applicationURL: URL

    var body: some View {
        VStack(spacing: 16) {
            if coordinator.snapshot[coordinator.selectedPermission] == .granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                Text("已授予\(permissionName)权限")
                    .font(.headline)
                Button("完成") { coordinator.closeAssistant() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Text("将 MouseTrails 拖到系统设置的\(permissionName)列表")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Image(nsImage: applicationIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 82, height: 82)
                    .shadow(radius: 5, y: 2)
                    .onDrag {
                        NSItemProvider(object: applicationURL as NSURL)
                    } preview: {
                        Image(nsImage: applicationIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    }
                    .help("按住并拖动 MouseTrails.app")

                Text("如果列表中已有 MouseTrails，打开右侧开关；开关已开但仍未授权时，关开一次，仍无效则移除后重新拖入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack {
                    Button("在 Finder 中显示") { coordinator.revealApplication() }
                    Button("重新检测") { coordinator.refresh() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 380, height: 300)
    }

    private var permissionName: String {
        PermissionCoordinator.displayName(for: coordinator.selectedPermission)
    }

    private var applicationIcon: NSImage {
        NSWorkspace.shared.icon(forFile: applicationURL.path)
    }
}
