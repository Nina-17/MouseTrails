import Foundation
import MouseIncCore
import XCTest
@testable import MouseIncMac

@MainActor
final class ConfigStoreTests: XCTestCase {
    func testCreatesDefaultSchemaThreeConfiguration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let configuration = try fixture.store.loadOrCreate()

        XCTAssertEqual(configuration.schemaVersion, 3)
        XCTAssertTrue(configuration.validate().isValid)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testMigratesSchemaTwoAndPreservesBackup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let schemaTwo = Data(
            #"{"schemaVersion":2,"gestureOptions":{"enabled":false},"bindings":[]}"#.utf8
        )
        try schemaTwo.write(to: fixture.fileURL)

        let configuration = try fixture.store.loadOrCreate()

        XCTAssertEqual(configuration.schemaVersion, 3)
        XCTAssertFalse(configuration.enabled)
        XCTAssertEqual(configuration.actionSequenceOptions, ActionSequenceOptions())

        let backupURL = fixture.directoryURL.appendingPathComponent("config.schema-2.backup.json")
        XCTAssertEqual(try Data(contentsOf: backupURL), schemaTwo)

        let migratedData = try Data(contentsOf: fixture.fileURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 3)
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
}

@MainActor
private struct Fixture {
    let directoryURL: URL
    let fileURL: URL
    let store: ConfigStore

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseIncMacTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("config.json")
        store = ConfigStore(fileURL: fileURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
