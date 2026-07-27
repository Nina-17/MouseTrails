import MouseIncCore
import XCTest
@testable import MouseIncMac

@MainActor
final class GestureMonitorTests: XCTestCase {
    func testExcludedApplicationMatchingIsCaseInsensitive() {
        let applications = [
            ExcludedApplication(
                bundleIdentifier: "com.example.Editor",
                displayName: "Editor"
            )
        ]

        XCTAssertTrue(
            GestureMonitor.isApplicationExcluded(
                "COM.EXAMPLE.EDITOR",
                in: applications
            )
        )
        XCTAssertFalse(
            GestureMonitor.isApplicationExcluded(
                "com.example.Browser",
                in: applications
            )
        )
        XCTAssertFalse(GestureMonitor.isApplicationExcluded(nil, in: applications))
    }
}
