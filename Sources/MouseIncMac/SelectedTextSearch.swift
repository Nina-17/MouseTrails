import AppKit

@MainActor
enum SelectedTextSearch {
    static func perform(urlTemplate: String) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard
                let selected = NSPasteboard.general.string(forType: .string),
                !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let encoded = selected.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            else { return }
            let target = urlTemplate.replacingOccurrences(of: "{query}", with: encoded)
            guard let url = URL(string: target), url.scheme != nil else { return }
            NSWorkspace.shared.open(url)
        }
        return true
    }
}
