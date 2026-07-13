import AppKit

@MainActor
enum FocusedApplicationPath {
    static func open() -> Bool {
        guard let url = NSWorkspace.shared.frontmostApplication?.bundleURL else {
            return false
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }
}
