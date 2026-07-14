import XCTest
@testable import MouseIncCore

final class AppVersionTests: XCTestCase {
    func testParsesTagsAndNormalizesMissingComponents() {
        XCTAssertEqual(AppVersion("v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(AppVersion("1.2")?.description, "1.2.0")
        XCTAssertEqual(AppVersion("V2")?.description, "2.0.0")
        XCTAssertNil(AppVersion("release-1.2.3"))
        XCTAssertNil(AppVersion("1.2.3.4"))
    }

    func testComparesNumericComponentsInsteadOfLexicalOrder() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.9.0")), try XCTUnwrap(AppVersion("1.10.0")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.10.9")), try XCTUnwrap(AppVersion("2.0.0")))
    }

    func testStableReleaseSortsAfterPrerelease() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.0.0-beta.2")), try XCTUnwrap(AppVersion("1.0.0-beta.10")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.0.0-rc.1")), try XCTUnwrap(AppVersion("1.0.0")))
    }
}
