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
        XCTAssertEqual(binding?.actions, [.init(type: .windowAction, value: "center")])
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
}
