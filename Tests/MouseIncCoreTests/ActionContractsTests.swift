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

    func testCloseAllWindowActionIsSupported() {
        let configuration = AppConfiguration(bindings: [
            GestureBinding(
                gesture: "DOWN-LEFT",
                name: "关闭所有类似窗口",
                actions: [.init(type: .windowAction, value: WindowAction.closeAll.rawValue)]
            )
        ])

        XCTAssertTrue(configuration.validate().isValid)
        XCTAssertTrue(WindowAction.allCases.contains(.closeAll))
    }

    func testQuitApplicationWindowActionIsSupported() {
        let configuration = AppConfiguration(bindings: [
            GestureBinding(
                gesture: "LETTER_W",
                name: "退出当前应用",
                actions: [.init(type: .windowAction, value: WindowAction.quitApplication.rawValue)]
            )
        ])

        XCTAssertTrue(configuration.validate().isValid)
        XCTAssertTrue(WindowAction.allCases.contains(.quitApplication))
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
            ActionCatalog.descriptor(for: .captureAction).requiredPermissions,
            [.screenRecording]
        )
        XCTAssertEqual(
            ActionCatalog.descriptor(for: .ocrAction).requiredPermissions,
            [.screenRecording]
        )
        XCTAssertEqual(
            Set(ActionCatalog.descriptors.map(\.kind)),
            Set(ActionDefinition.Kind.allCases)
        )
    }

    func testCaptureActionsValidateKnownValues() {
        let valid = AppConfiguration(bindings: [
            GestureBinding(
                gesture: "SQUARE",
                name: "截图贴图",
                actions: [.init(type: .captureAction, value: CaptureAction.pinRegion.rawValue)]
            )
        ])
        XCTAssertTrue(valid.validate().isValid)

        let invalid = AppConfiguration(bindings: [
            GestureBinding(
                gesture: "SQUARE",
                name: "无效截图",
                actions: [.init(type: .captureAction, value: "unknown")]
            )
        ])
        XCTAssertFalse(invalid.validate().isValid)
    }

    func testOCRActionsValidateKnownValues() {
        let valid = AppConfiguration(bindings: [
            GestureBinding(
                gesture: "UP_LEFT",
                name: "离线 OCR",
                actions: [.init(type: .ocrAction, value: OCRAction.recognizeRegion.rawValue)]
            )
        ])
        XCTAssertTrue(valid.validate().isValid)

        let invalid = AppConfiguration(bindings: [
            GestureBinding(
                gesture: "UP_LEFT",
                name: "无效 OCR",
                actions: [.init(type: .ocrAction, value: "unknown")]
            )
        ])
        XCTAssertFalse(invalid.validate().isValid)
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

    func testCustomBindingMustReferenceAValidDefinition() {
        let configuration = AppConfiguration(
            bindings: [
                GestureBinding(
                    gesture: "CUSTOM_MISSING",
                    name: "缺失的自定义手势",
                    actions: [.init(type: .keyStroke, value: "Command+C")]
                )
            ]
        )

        let result = configuration.validate()

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains {
            $0.code == .invalidCustomGesture && $0.path == "bindings[0].gesture"
        })
    }

    func testCustomGestureRejectsDegenerateStoredSamples() {
        let points = Array(repeating: GestureSamplePoint(x: 0, y: 0), count: 64)
        let definition = CustomGestureDefinition(
            identifier: "CUSTOM_FLAT",
            name: "无效轨迹",
            samples: Array(repeating: points, count: 3)
        )
        let configuration = AppConfiguration(
            customGestures: [definition],
            bindings: [GestureBinding(
                gesture: definition.identifier,
                name: "无效轨迹",
                actions: [.init(type: .keyStroke, value: "Command+C")]
            )]
        )

        XCTAssertFalse(configuration.validate().isValid)
        XCTAssertTrue(configuration.validate().issues.contains {
            $0.code == .invalidCustomGesture && $0.path == "customGestures[0].samples"
        })
    }
}
