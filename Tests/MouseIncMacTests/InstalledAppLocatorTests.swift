import MouseIncCore
import XCTest
@testable import MouseIncMac

final class InstalledAppLocatorTests: XCTestCase {
    func testSelectsHighestVersionFromDifferentInstalledLocation() throws {
        let current = InstalledAppCopy(
            url: URL(fileURLWithPath: "/Users/test/Applications/MouseTrails.app"),
            version: try XCTUnwrap(AppVersion("0.19.1"))
        )
        let selected = InstalledAppLocator.newerCopy(
            than: current,
            candidates: [
                current,
                InstalledAppCopy(
                    url: URL(fileURLWithPath: "/Applications/MouseTrails.app"),
                    version: try XCTUnwrap(AppVersion("0.20.0"))
                ),
                InstalledAppCopy(
                    url: URL(fileURLWithPath: "/Volumes/MouseTrails/MouseTrails.app"),
                    version: try XCTUnwrap(AppVersion("0.19.2"))
                )
            ]
        )

        XCTAssertEqual(selected?.version.description, "0.20.0")
        XCTAssertEqual(selected?.url.path, "/Applications/MouseTrails.app")
    }

    func testDoesNotSelectSameOrOlderVersion() throws {
        let current = InstalledAppCopy(
            url: URL(fileURLWithPath: "/Applications/MouseTrails.app"),
            version: try XCTUnwrap(AppVersion("0.20.0"))
        )
        XCTAssertNil(
            InstalledAppLocator.newerCopy(
                than: current,
                candidates: [
                    current,
                    InstalledAppCopy(
                        url: URL(fileURLWithPath: "/Users/test/Applications/MouseTrails.app"),
                        version: try XCTUnwrap(AppVersion("0.19.1"))
                    )
                ]
            )
        )
    }
}
