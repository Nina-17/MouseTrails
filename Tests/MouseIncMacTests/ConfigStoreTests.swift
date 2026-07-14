import Foundation
import MouseIncCore
import XCTest
@testable import MouseIncMac

@MainActor
final class ConfigStoreTests: XCTestCase {
    func testCreatesDefaultConfiguration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let configuration = try fixture.store.loadOrCreate()

        XCTAssertEqual(configuration.schemaVersion, AppConfiguration.currentSchemaVersion)
        XCTAssertTrue(configuration.validate().isValid)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testCreatesConfigurationFromBundledDefault() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundledDefaultURL = repositoryRoot
            .appendingPathComponent("Resources")
            .appendingPathComponent("default-config.json")
        let fixture = try Fixture(bundledDefaultConfigurationURL: bundledDefaultURL)
        defer { fixture.remove() }

        let configuration = try fixture.store.loadOrCreate()
        let expected = try JSONDecoder().decode(
            AppConfiguration.self,
            from: Data(contentsOf: bundledDefaultURL)
        )

        XCTAssertEqual(configuration, expected)
        XCTAssertEqual(configuration.bindings.count, 10)
        XCTAssertFalse(configuration.bindings.contains {
            $0.gesture.caseInsensitiveCompare("LETTER_S") == .orderedSame
        })
        XCTAssertFalse(configuration.bindings.contains { binding in
            binding.actions.contains {
                $0.type == .windowAction && $0.value == WindowAction.quitApplication.rawValue
            }
        })
        XCTAssertTrue(configuration.customGestures.isEmpty)
        XCTAssertTrue(configuration.edgeScrollOptions.enabled)
        XCTAssertEqual(configuration.gestureOptions.trailColor.green, 0.9399358630180359)
    }

    func testRemovesLegacyBuiltInSBindingWhenLoading() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var legacy = AppConfiguration()
        legacy.bindings.append(GestureBinding(
            gesture: "LETTER_S",
            name: "旧内置搜索",
            actions: [.init(type: .searchSelectedText, value: "https://example.com?q={query}")]
        ))
        try JSONEncoder().encode(legacy).write(to: fixture.fileURL)

        let loaded = try fixture.store.loadOrCreate()

        XCTAssertFalse(loaded.bindings.contains {
            $0.gesture.caseInsensitiveCompare("LETTER_S") == .orderedSame
        })
        XCTAssertEqual(
            try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: fixture.fileURL)),
            loaded
        )
    }

    func testRemovesRetiredBuiltInWBindingWhenLoading() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var legacy = AppConfiguration()
        legacy.bindings.append(GestureBinding(
            gesture: "LETTER_W",
            name: "旧内置 W",
            actions: [.init(type: .keyStroke, value: "Command+W")]
        ))
        try JSONEncoder().encode(legacy).write(to: fixture.fileURL)

        let loaded = try fixture.store.loadOrCreate()

        XCTAssertFalse(loaded.bindings.contains {
            $0.gesture.caseInsensitiveCompare("LETTER_W") == .orderedSame
        })
        XCTAssertEqual(
            try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: fixture.fileURL)),
            loaded
        )
    }

    func testMigratesSchemaTwoAndPreservesBackup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let schemaTwo = Data(
            #"{"schemaVersion":2,"gestureOptions":{"enabled":false},"bindings":[]}"#.utf8
        )
        try schemaTwo.write(to: fixture.fileURL)

        let configuration = try fixture.store.loadOrCreate()

        XCTAssertEqual(configuration.schemaVersion, AppConfiguration.currentSchemaVersion)
        XCTAssertFalse(configuration.enabled)
        XCTAssertEqual(configuration.actionSequenceOptions, ActionSequenceOptions())

        let backupURL = fixture.directoryURL.appendingPathComponent("config.schema-2.backup.json")
        XCTAssertEqual(try Data(contentsOf: backupURL), schemaTwo)

        let migratedData = try Data(contentsOf: fixture.fileURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, AppConfiguration.currentSchemaVersion)
        XCTAssertNotNil(object["actionSequenceOptions"])
    }

    func testRejectsInvalidConfigurationWithoutOverwritingFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let invalid = Data(
            #"{"schemaVersion":3,"gestureOptions":{},"actionSequenceOptions":{},"bindings":[{"gesture":"UP","name":"Broken","bundleIdentifiers":[],"actions":[]}]}"#.utf8
        )
        try invalid.write(to: fixture.fileURL)

        XCTAssertThrowsError(try fixture.store.loadOrCreate()) { error in
            guard case ConfigStoreError.invalidConfiguration = error else {
                return XCTFail("Expected invalidConfiguration, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), invalid)
    }

    func testExportsAndRestoresValidatedConfigurationWithBackup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.store.loadOrCreate()
        let exportURL = fixture.directoryURL.appendingPathComponent("export.json")
        var replacement = original
        replacement.showsTrail = false
        try fixture.store.export(replacement, to: exportURL)

        let restored = try fixture.store.restore(from: exportURL)

        XCTAssertFalse(restored.showsTrail)
        XCTAssertEqual(try fixture.store.loadOrCreate(), replacement)
        let backups = try FileManager.default.contentsOfDirectory(
            at: fixture.directoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("config.pre-restore-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: backups[0])), original)
    }

    func testInvalidRestoreDoesNotCreateBackupOrChangeConfiguration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.store.loadOrCreate()
        let invalidURL = fixture.directoryURL.appendingPathComponent("invalid.json")
        try Data("not-json".utf8).write(to: invalidURL)

        XCTAssertThrowsError(try fixture.store.restore(from: invalidURL))
        XCTAssertEqual(try fixture.store.loadOrCreate(), original)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.directoryURL.path)
        XCTAssertFalse(names.contains { $0.hasPrefix("config.pre-restore-") })
    }
}

@MainActor
private struct Fixture {
    let directoryURL: URL
    let fileURL: URL
    let store: ConfigStore

    init(bundledDefaultConfigurationURL: URL? = nil) throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseIncMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("config.json")
        store = ConfigStore(
            fileURL: fileURL,
            bundledDefaultConfigurationURL: bundledDefaultConfigurationURL
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
