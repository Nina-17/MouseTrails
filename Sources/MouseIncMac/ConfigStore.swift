import Foundation
import MouseIncCore

@MainActor
struct ConfigStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = baseURL
            .appendingPathComponent("MouseIncMac", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
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

        if storedVersion != AppConfiguration.currentSchemaVersion {
            try preservePreMigrationConfiguration(data, schemaVersion: storedVersion ?? 1)
            try save(configuration)
            DiagnosticLogger.shared.log(
                "Configuration migrated from schema \(storedVersion ?? 1) " +
                    "to \(AppConfiguration.currentSchemaVersion)"
            )
        }

        return configuration
    }

    func save(_ configuration: AppConfiguration) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
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
}
