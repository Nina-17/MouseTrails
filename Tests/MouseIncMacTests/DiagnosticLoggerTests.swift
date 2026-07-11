import Foundation
import XCTest
@testable import MouseIncMac

@MainActor
final class DiagnosticLoggerTests: XCTestCase {
    func testStructuredEventIsSingleLineAndSanitized() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseIncLoggerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("diagnostics.log")
        let logger = DiagnosticLogger(fileURL: fileURL)

        logger.log(
            event: .actionSequenceIgnored,
            metadata: ["reason": "line one\nline two"]
        )

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(content.split(separator: "\n").count, 1)
        XCTAssertTrue(content.contains("event=action.sequence.ignored"))
        XCTAssertTrue(content.contains("reason=line_one_line_two"))
        XCTAssertFalse(content.contains("line one"))
    }
}
