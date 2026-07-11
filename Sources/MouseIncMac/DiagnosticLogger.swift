import Foundation

@MainActor
final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    let fileURL: URL
    private let formatter = ISO8601DateFormatter()

    private init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MouseIncMac", isDirectory: true)
        fileURL = directory.appendingPathComponent("diagnostics.log", isDirectory: false)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? data.write(to: fileURL, options: .atomic)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }
}

