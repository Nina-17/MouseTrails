import Foundation
import MouseIncCore

enum ConfigStoreError: LocalizedError {
    case invalidConfiguration([ConfigurationIssue])

    var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(issues):
            let details = issues
                .filter { $0.severity == .error }
                .prefix(3)
                .map { "\($0.path): \($0.message)" }
                .joined(separator: "\n")
            return "配置校验失败：\n\(details)"
        }
    }
}

@MainActor
struct ConfigStore {
    let fileURL: URL
    private let fileManager: FileManager
    private let migrationObserver: @MainActor (Int, Int) -> Void

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        migrationObserver = { oldVersion, newVersion in
            DiagnosticLogger.shared.log(
                "Configuration migrated from schema \(oldVersion) to \(newVersion)"
            )
        }
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = baseURL
            .appendingPathComponent("MouseIncMac", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        migrationObserver: @escaping @MainActor (Int, Int) -> Void = { _, _ in }
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.migrationObserver = migrationObserver
    }

    func loadOrCreate() throws -> AppConfiguration {
        if !fileManager.fileExists(atPath: fileURL.path) {
            let defaultConfiguration = AppConfiguration()
            try save(defaultConfiguration)
            return defaultConfiguration
        }

        let data = try Data(contentsOf: fileURL)
        let storedVersion = configurationVersion(in: data)
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
        try validate(configuration)

        if storedVersion != AppConfiguration.currentSchemaVersion {
            try preservePreMigrationConfiguration(data, schemaVersion: storedVersion ?? 1)
            try save(configuration)
            migrationObserver(storedVersion ?? 1, AppConfiguration.currentSchemaVersion)
        }

        return configuration
    }

    func save(_ configuration: AppConfiguration) throws {
        try validate(configuration)
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoded(configuration)
        try data.write(to: fileURL, options: .atomic)
    }

    func export(_ configuration: AppConfiguration, to destinationURL: URL) throws {
        try validate(configuration)
        try encoded(configuration).write(to: destinationURL, options: .atomic)
    }

    func restore(from sourceURL: URL) throws -> AppConfiguration {
        let sourceData = try Data(contentsOf: sourceURL)
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: sourceData)
        try validate(configuration)

        if fileManager.fileExists(atPath: fileURL.path) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(
                "config.pre-restore-\(formatter.string(from: Date()))-\(UUID().uuidString).backup.json"
            )
            try fileManager.copyItem(at: fileURL, to: backupURL)
        }
        try save(configuration)
        return configuration
    }

    private func encoded(_ configuration: AppConfiguration) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(configuration)
    }

    private func configurationVersion(in data: Data) -> Int? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            let number = dictionary["schemaVersion"] as? NSNumber
        else {
            return nil
        }
        return number.intValue
    }

    private func preservePreMigrationConfiguration(_ data: Data, schemaVersion: Int) throws {
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("config.schema-\(schemaVersion).backup.json")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        try data.write(to: backupURL, options: .atomic)
    }

    private func validate(_ configuration: AppConfiguration) throws {
        let result = configuration.validate()
        guard result.isValid else {
            throw ConfigStoreError.invalidConfiguration(result.issues)
        }
    }
}
