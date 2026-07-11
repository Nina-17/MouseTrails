import Foundation

enum DiagnosticEvent: String {
    case actionSequenceStarted = "action.sequence.started"
    case actionSequenceIgnored = "action.sequence.ignored"
    case actionSequenceCancelled = "action.sequence.cancelled"
    case actionSequenceFinished = "action.sequence.finished"
    case actionFailed = "action.failed"
    case permissionSnapshot = "permission.snapshot"
}

@MainActor
final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    let fileURL: URL
    private let fileManager: FileManager
    private let formatter = ISO8601DateFormatter()

    private init() {
        fileManager = .default
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/MouseIncMac", isDirectory: true)
        fileURL = directory.appendingPathComponent("diagnostics.log", isDirectory: false)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        write(line)
    }

    /// Structured diagnostics only accept operational metadata. Callers must
    /// never pass key contents, clipboard text, URLs, paths, or image data.
    func log(event: DiagnosticEvent, metadata: [String: String] = [:]) {
        let fields = metadata
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(sanitize(key))=\(sanitize(value))"
            }
            .joined(separator: " ")
        let suffix = fields.isEmpty ? "" : " \(fields)"
        let line = "[\(formatter.string(from: Date()))] event=\(event.rawValue)\(suffix)\n"
        write(line)
    }

    private func sanitize(_ value: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\t", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return String(singleLine.prefix(120))
    }

    private func write(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }

        if !fileManager.fileExists(atPath: fileURL.path) {
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
