import Foundation
import XCTest
@testable import MouseIncCore

final class AppConfigurationTests: XCTestCase {
    func testLegacyRestoreActionMigratesToFullScreenToggle() throws {
        let data = Data(
            #"{"schemaVersion":3,"gestureOptions":{},"actionSequenceOptions":{},"bindings":[{"gesture":"UP","name":"Legacy","bundleIdentifiers":[],"actions":[{"type":"windowAction","value":"restore"}]}]}"#.utf8
        )

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(configuration.bindings[0].actions[0].value, "maximize")
        XCTAssertTrue(configuration.validate().isValid)
    }

    func testDefaultsAreSafeAndPreserveExistingBehavior() {
        let configuration = AppConfiguration()

        XCTAssertEqual(configuration.schemaVersion, AppConfiguration.currentSchemaVersion)
        XCTAssertTrue(configuration.gestureOptions.enabled)
        XCTAssertEqual(configuration.gestureOptions.startDistance, 12)
        XCTAssertEqual(configuration.gestureOptions.simplificationTolerance, 18)
        XCTAssertEqual(configuration.gestureOptions.minimumGestureLength, 40)
        XCTAssertEqual(configuration.gestureOptions.maximumDuration, 5)
        XCTAssertTrue(configuration.gestureOptions.showsTrail)
        XCTAssertTrue(configuration.gestureOptions.reportsFailures)
        XCTAssertEqual(configuration.actionSequenceOptions, ActionSequenceOptions())
        XCTAssertEqual(configuration.bindings, GestureBinding.defaults)
    }

    func testNewFormatRoundTripsAndOnlyEncodesNewShape() throws {
        let options = GestureOptions(
            enabled: false,
            startDistance: 21,
            simplificationTolerance: 9,
            minimumGestureLength: 55,
            maximumDuration: 2.5,
            showsTrail: false,
            reportsFailures: false
        )
        let configuration = AppConfiguration(gestureOptions: options, bindings: [.sampleGlobal])

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)
        XCTAssertEqual(decoded, configuration)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, AppConfiguration.currentSchemaVersion)
        XCTAssertNotNil(object["gestureOptions"])
        XCTAssertNotNil(object["actionSequenceOptions"])
        XCTAssertNotNil(object["bindings"])
        XCTAssertNil(object["enabled"])
        XCTAssertNil(object["startDistance"])
        XCTAssertNil(object["simplificationTolerance"])
        XCTAssertNil(object["minimumGestureLength"])
    }

    func testLegacyFlatFormatMigratesAndReencodesAsCurrentSchema() throws {
        let data = Data(
            #"""
            {
              "enabled": false,
              "startDistance": 17,
              "simplificationTolerance": 7,
              "minimumGestureLength": 31,
              "bindings": []
            }
            """#.utf8
        )

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: data)
        XCTAssertEqual(configuration.schemaVersion, AppConfiguration.currentSchemaVersion)
        XCTAssertFalse(configuration.enabled)
        XCTAssertEqual(configuration.startDistance, 17)
        XCTAssertEqual(configuration.simplificationTolerance, 7)
        XCTAssertEqual(configuration.minimumGestureLength, 31)
        XCTAssertEqual(configuration.maximumDuration, 5)
        XCTAssertTrue(configuration.showsTrail)
        XCTAssertTrue(configuration.reportsFailures)
        XCTAssertEqual(configuration.bindings, [])

        let migratedData = try JSONEncoder().encode(configuration)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, AppConfiguration.currentSchemaVersion)
        XCTAssertNotNil(object["gestureOptions"])
        XCTAssertNil(object["enabled"])
        XCTAssertNil(object["startDistance"])
    }

    func testMissingFieldsUseDefaultsInBothFormats() throws {
        let legacy = try JSONDecoder().decode(
            AppConfiguration.self,
            from: Data(#"{"enabled":false}"#.utf8)
        )
        XCTAssertFalse(legacy.enabled)
        XCTAssertEqual(legacy.startDistance, 12)
        XCTAssertEqual(legacy.bindings, GestureBinding.defaults)

        let current = try JSONDecoder().decode(
            AppConfiguration.self,
            from: Data(
                #"{"schemaVersion":2,"gestureOptions":{"showsTrail":false}}"#.utf8
            )
        )
        XCTAssertTrue(current.enabled)
        XCTAssertEqual(current.startDistance, 12)
        XCTAssertFalse(current.showsTrail)
        XCTAssertTrue(current.reportsFailures)
        XCTAssertEqual(current.bindings, GestureBinding.defaults)
    }

    func testSchemaTwoMigratesWithDefaultActionSequenceOptions() throws {
        let schemaTwo = Data(
            #"{"schemaVersion":2,"gestureOptions":{"enabled":false},"bindings":[]}"#.utf8
        )

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: schemaTwo)

        XCTAssertEqual(configuration.schemaVersion, AppConfiguration.currentSchemaVersion)
        XCTAssertFalse(configuration.enabled)
        XCTAssertEqual(configuration.actionSequenceOptions, ActionSequenceOptions())

        let encoded = try JSONEncoder().encode(configuration)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, AppConfiguration.currentSchemaVersion)
        XCTAssertNotNil(object["actionSequenceOptions"])
    }

    func testDelayActionAndSequenceOptionsRoundTrip() throws {
        let options = ActionSequenceOptions(
            interruptionPolicy: .ignoreNew,
            failurePolicy: .continueSequence,
            maximumDelay: 12
        )
        let binding = GestureBinding(
            gesture: "RIGHT-UP",
            name: "Delayed",
            actions: [.delay(seconds: 0.25), .init(type: .keyStroke, value: "Command+C")]
        )
        let configuration = AppConfiguration(
            actionSequenceOptions: options,
            bindings: [binding]
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded, configuration)
        XCTAssertTrue(decoded.validate().isValid)
    }

    func testApplicationRuleTakesPriorityOverGlobalRule() {
        let global = GestureBinding.sampleGlobal
        let safari = GestureBinding(
            gesture: "up",
            name: "Safari",
            bundleIdentifiers: ["com.apple.Safari"],
            actions: [.init(type: .keyStroke, value: "Command+L")]
        )
        let configuration = AppConfiguration(bindings: [global, safari])

        XCTAssertEqual(
            configuration.binding(for: "UP", bundleIdentifier: "COM.APPLE.SAFARI"),
            safari
        )
        XCTAssertEqual(
            configuration.binding(for: "up", bundleIdentifier: "com.apple.TextEdit"),
            global
        )
        XCTAssertEqual(configuration.binding(for: "down", bundleIdentifier: nil), nil)
    }

    func testFutureSchemaIsRejected() {
        let futureVersion = AppConfiguration.currentSchemaVersion + 1
        let data = Data(#"{"schemaVersion":\#(futureVersion),"gestureOptions":{}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(AppConfiguration.self, from: data)) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("Unsupported configuration schema version"))
        }
    }
}

private extension GestureBinding {
    static let sampleGlobal = GestureBinding(
        gesture: "UP",
        name: "Global",
        actions: [.init(type: .keyStroke, value: "Command+C")]
    )
}
