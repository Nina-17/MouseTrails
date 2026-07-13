import MouseIncCore
import XCTest
@testable import MouseIncMac

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testAddsEmptyBinding() {
        let model = SettingsViewModel(configuration: AppConfiguration()) { _ in }

        model.addBinding()

        let binding = model.draft.bindings.last
        XCTAssertEqual(binding?.gesture, "")
        XCTAssertEqual(binding?.name, "新手势")
        XCTAssertEqual(binding?.actions, [])
    }

    func testExistingDefaultNameAndCustomNameArePreserved() {
        var configuration = AppConfiguration(bindings: [
            GestureBinding(
                gesture: "LEFT",
                name: "新手势",
                actions: [.init(type: .captureAction, value: CaptureAction.pinRegion.rawValue)]
            ),
            GestureBinding(
                gesture: "RIGHT",
                name: "我的操作",
                actions: [.init(type: .ocrAction, value: OCRAction.recognizeRegion.rawValue)]
            )
        ])
        configuration.enabled = true

        let model = SettingsViewModel(configuration: configuration) { _ in }

        XCTAssertEqual(model.draft.bindings[0].name, "新手势")
        XCTAssertEqual(model.draft.bindings[1].name, "我的操作")
    }

    func testChangingActionTypeKeepsDefaultNameUntilActionValueChanges() {
        var configuration = AppConfiguration(bindings: [
            GestureBinding(
                gesture: "UP",
                name: "新手势",
                actions: [.init(type: .windowAction, value: WindowAction.center.rawValue)]
            )
        ])
        configuration.enabled = true
        let model = SettingsViewModel(configuration: configuration) { _ in }
        model.setActionType(
            .captureAction,
            value: CaptureAction.pinRegion.rawValue,
            actionIndex: 0,
            bindingIndex: 0
        )

        XCTAssertEqual(model.draft.bindings[0].name, "新手势")

        model.setActionValue(
            CaptureAction.saveRegion.rawValue,
            actionIndex: 0,
            bindingIndex: 0
        )

        XCTAssertEqual(model.draft.bindings[0].name, "保存截图")
    }

    func testChangingActionValueReplacesDefaultName() {
        let model = SettingsViewModel(configuration: AppConfiguration(bindings: [
            GestureBinding(
                gesture: "UP",
                name: "新手势",
                actions: [.init(type: .keyStroke, value: "Command+C")]
            )
        ])) { _ in }

        model.setActionValue("Command+V", actionIndex: 0, bindingIndex: 0)

        XCTAssertEqual(model.draft.bindings[0].name, "快捷键 Command+V")
    }

    func testInvalidDraftDoesNotSave() {
        var saveCount = 0
        let model = SettingsViewModel(configuration: AppConfiguration()) { _ in
            saveCount += 1
        }
        model.draft.bindings[0].gesture = ""

        model.save()

        XCTAssertFalse(model.canSave)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(model.saveMessage, "请先修复配置错误")
    }

    func testValidDraftSaves() {
        var savedConfiguration: AppConfiguration?
        let model = SettingsViewModel(configuration: AppConfiguration()) { configuration in
            savedConfiguration = configuration
        }
        model.draft.showsTrail = false

        model.save()

        XCTAssertEqual(savedConfiguration?.showsTrail, false)
        XCTAssertEqual(model.saveMessage, "已保存并生效")
    }

    func testReportsScopedIssuesWithoutChangingBindingOrder() {
        let model = SettingsViewModel(configuration: AppConfiguration()) { _ in }
        let originalSecondGesture = model.draft.bindings[1].gesture

        model.draft.bindings[1].gesture = ""

        XCTAssertEqual(model.draft.bindings[1].gesture, "")
        XCTAssertEqual(originalSecondGesture, "DOWN")
        XCTAssertTrue(model.issues(for: 1).contains { $0.code == .emptyGesture })
        XCTAssertTrue(model.issues(for: 0).isEmpty)
    }

    func testOrdersBindingsByGestureCategoryWithoutChangingConfigurationOrder() {
        let model = SettingsViewModel(configuration: AppConfiguration(bindings: [
            GestureBinding(gesture: "LETTER_W", name: "模板", actions: [.init(type: .keyStroke, value: "Command+C")]),
            GestureBinding(gesture: "DOWN-RIGHT", name: "折线", actions: [.init(type: .keyStroke, value: "Command+C")]),
            GestureBinding(gesture: "UP_RIGHT", name: "对角线", actions: [.init(type: .keyStroke, value: "Command+C")]),
            GestureBinding(gesture: "UP", name: "直线", actions: [.init(type: .keyStroke, value: "Command+C")]),
            GestureBinding(gesture: "", name: "未配置", actions: [])
        ])) { _ in }

        let orderedGestures = model.orderedBindingIDs.compactMap { id in
            model.bindingIndex(for: id).flatMap { model.binding(at: $0)?.gesture }
        }

        XCTAssertEqual(orderedGestures, ["UP", "UP_RIGHT", "DOWN-RIGHT", "LETTER_W", ""])
        XCTAssertEqual(model.draft.bindings.map(\.gesture), ["LETTER_W", "DOWN-RIGHT", "UP_RIGHT", "UP", ""])
    }

    func testGestureCanBeSelectedForNewBinding() {
        let model = SettingsViewModel(configuration: AppConfiguration()) { _ in }
        model.addBinding()
        let index = model.draft.bindings.count - 1

        model.setGesture("LETTER_C", for: index)

        XCTAssertEqual(model.draft.bindings[index].gesture, "LETTER_C")
    }

    func testExportAndRestoreHandlersUpdateStatusAndDraft() {
        var exported: AppConfiguration?
        var replacement = AppConfiguration()
        replacement.enabled = false
        let model = SettingsViewModel(
            configuration: AppConfiguration(),
            saveHandler: { _ in },
            exportHandler: { configuration, _ in exported = configuration },
            restoreHandler: { _ in replacement }
        )
        let url = URL(fileURLWithPath: "/tmp/config.json")

        model.export(to: url)
        XCTAssertEqual(exported, model.draft)
        XCTAssertEqual(model.saveMessage, "配置已导出")

        model.restore(from: url)
        XCTAssertFalse(model.draft.enabled)
        XCTAssertEqual(model.saveMessage, "配置已恢复并生效")
    }

    func testApplicationPickerRejectsNonApplicationURL() {
        let model = SettingsViewModel(configuration: AppConfiguration()) { _ in }

        XCTAssertFalse(model.useApplication(at: URL(fileURLWithPath: "/tmp/file.txt"), for: 0))
        XCTAssertTrue(model.draft.bindings[0].bundleIdentifiers.isEmpty)
    }

    func testApplicationPickerReadsBundleIdentifier() throws {
        let model = SettingsViewModel(configuration: AppConfiguration()) { _ in }
        let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: finderURL.path))

        XCTAssertTrue(model.useApplication(at: finderURL, for: 0))
        XCTAssertEqual(model.draft.bindings[0].bundleIdentifiers, ["com.apple.finder"])
    }
}
