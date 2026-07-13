import MouseIncCore
import XCTest
@testable import MouseIncMac

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testAddsWindowCenterBinding() {
        let model = SettingsViewModel(configuration: AppConfiguration()) { _ in }

        model.addBinding()

        let binding = model.draft.bindings.last
        XCTAssertEqual(binding?.gesture, "UP_RIGHT")
        XCTAssertEqual(binding?.name, "居中窗口")
        XCTAssertEqual(binding?.actions, [.init(type: .windowAction, value: "center")])
    }

    func testExistingDefaultNameUsesFirstActionNameButCustomNameIsPreserved() {
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

        XCTAssertEqual(model.draft.bindings[0].name, "生成贴图")
        XCTAssertEqual(model.draft.bindings[1].name, "我的操作")
    }

    func testAddingFirstActionReplacesDefaultName() {
        var configuration = AppConfiguration(bindings: [
            GestureBinding(
                gesture: "UP",
                name: "新手势",
                actions: []
            )
        ])
        configuration.enabled = true
        let model = SettingsViewModel(configuration: configuration) { _ in }
        model.addAction(to: 0)

        XCTAssertEqual(model.draft.bindings[0].name, "快捷键 Command+C")
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

    func testMovesBindingAndReportsScopedIssues() {
        let model = SettingsViewModel(configuration: AppConfiguration()) { _ in }
        let originalSecondGesture = model.draft.bindings[1].gesture

        model.moveBinding(from: 1, by: -1)
        model.draft.bindings[0].gesture = ""

        XCTAssertEqual(model.draft.bindings[0].gesture, "")
        XCTAssertEqual(originalSecondGesture, "DOWN")
        XCTAssertTrue(model.issues(for: 0).contains { $0.code == .emptyGesture })
        XCTAssertTrue(model.issues(for: 1).isEmpty)
    }

    func testBindingIdentitiesStayAlignedAfterRemovalAndMove() {
        let model = SettingsViewModel(configuration: AppConfiguration()) { _ in }
        let firstID = model.bindingIDs[0]
        let secondID = model.bindingIDs[1]

        model.removeBinding(at: 0)
        XCTAssertEqual(model.bindingIDs.first, secondID)
        XCTAssertEqual(model.bindingIDs.count, model.draft.bindings.count)

        model.moveBinding(from: 0, by: 1)
        XCTAssertNotEqual(model.bindingIDs.first, secondID)
        XCTAssertFalse(model.bindingIDs.contains(firstID))
        XCTAssertEqual(model.bindingIDs.count, model.draft.bindings.count)
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
