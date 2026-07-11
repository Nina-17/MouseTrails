import Foundation
import XCTest
@testable import MouseIncCore

final class ActionContractsTests: XCTestCase {
    func testLegacyRestoreWindowActionDecodesAsFullScreenToggle() throws {
        let action = try JSONDecoder().decode(WindowAction.self, from: Data("\"restore\"".utf8))

        XCTAssertEqual(action, .maximize)
        XCTAssertEqual(String(data: try JSONEncoder().encode(action), encoding: .utf8), "\"maximize\"")
        XCTAssertFalse(WindowAction.allCases.map(\.rawValue).contains("restore"))
    }

    func testKeyStrokeParserNormalizesAliasesAndRejectsUnknownTokens() {
        XCTAssertEqual(
            KeyStrokeParser.parse("Cmd+Alt+Shift+C"),
            ParsedKeyStroke(modifiers: [.command, .option, .shift], key: "c")
        )
        XCTAssertNil(KeyStrokeParser.parse("Hyper+C"))
        XCTAssertNil(KeyStrokeParser.parse("Command+NotAKey"))
        XCTAssertNil(KeyStrokeParser.parse(""))
    }

    func testActionCatalogDeclaresPermissionRequirements() {
        XCTAssertEqual(
            ActionCatalog.descriptor(for: .keyStroke).requiredPermissions,
            [.accessibility]
        )
        XCTAssertEqual(ActionCatalog.descriptor(for: .delay).requiredPermissions, [])
        XCTAssertEqual(
            Set(ActionCatalog.descriptors.map(\.kind)),
            Set(ActionDefinition.Kind.allCases)
        )
    }

    func testPermissionSnapshotEvaluatesIndependentPermissions() {
        let snapshot = PermissionSnapshot(
            states: [
                .accessibility: .granted,
                .screenRecording: .denied
            ]
        )

        XCTAssertEqual(snapshot[.accessibility], .granted)
        XCTAssertEqual(snapshot[.screenRecording], .denied)
        XCTAssertEqual(snapshot[.inputMonitoring], .notDetermined)
        XCTAssertTrue(snapshot.satisfies([.accessibility]))
        XCTAssertFalse(snapshot.satisfies([.accessibility, .screenRecording]))
    }

    func testDefaultConfigurationIsValid() {
        let result = AppConfiguration().validate()

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.issues, [])
    }

    func testValidationReportsInvalidOptionsDuplicatesAndActionValues() {
        var configuration = AppConfiguration(
            actionSequenceOptions: ActionSequenceOptions(maximumDelay: 1),
            bindings: [
                GestureBinding(
                    gesture: "UP",
                    name: "First",
                    actions: [.delay(seconds: 2)]
                ),
                GestureBinding(
                    gesture: "up",
                    name: "Second",
                    actions: [.init(type: .openURL, value: "not a url")]
                )
            ]
        )
        configuration.gestureOptions.maximumDuration = 0

        let result = configuration.validate()
        let codes = Set(result.issues.map(\.code))

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(codes.contains(.invalidGestureOption))
        XCTAssertTrue(codes.contains(.duplicateBinding))
        XCTAssertTrue(codes.contains(.invalidActionValue))
    }

    func testEmptyBindingNameIsWarningOnly() {
        let configuration = AppConfiguration(
            bindings: [
                GestureBinding(
                    gesture: "UP",
                    name: " ",
                    actions: [.init(type: .keyStroke, value: "Command+C")]
                )
            ]
        )

        let result = configuration.validate()

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.issues.map(\.severity), [.warning])
        XCTAssertEqual(result.issues.map(\.code), [.emptyBindingName])
    }
}
