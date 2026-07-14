import Foundation
import XCTest
@testable import MouseIncMac

final class GitHubReleaseClientTests: XCTestCase {
    func testDecodesReleaseAndSelectsVersionedDMG() throws {
        let data = Data(
            """
            {
              "tag_name": "v0.17.0",
              "name": "MouseTrails 0.17.0",
              "body": "Update notes",
              "html_url": "https://github.com/Nina-17/MouseTrails/releases/tag/v0.17.0",
              "assets": [
                {
                  "name": "checksums.txt",
                  "browser_download_url": "https://github.com/Nina-17/MouseTrails/releases/download/v0.17.0/checksums.txt",
                  "size": 100
                },
                {
                  "name": "MouseTrails-0.17.0.dmg",
                  "browser_download_url": "https://github.com/Nina-17/MouseTrails/releases/download/v0.17.0/MouseTrails-0.17.0.dmg",
                  "size": 1024,
                  "digest": "sha256:2151b604e3429bff440b9fbc03eb3617bc2603cda96c95b9bb05277f9ddba255"
                }
              ]
            }
            """.utf8
        )

        let release = try GitHubReleaseClient.decodeRelease(data)

        XCTAssertEqual(release.version?.description, "0.17.0")
        XCTAssertEqual(release.preferredDMGAsset?.name, "MouseTrails-0.17.0.dmg")
        XCTAssertEqual(
            release.preferredDMGAsset?.digest,
            "sha256:2151b604e3429bff440b9fbc03eb3617bc2603cda96c95b9bb05277f9ddba255"
        )
        XCTAssertEqual(release.notes, "Update notes")
    }

    func testFallsBackToOnlyDMGForNonstandardTag() throws {
        let data = Data(
            """
            {
              "tag_name": "nightly",
              "name": null,
              "body": null,
              "html_url": "https://github.com/Nina-17/MouseTrails/releases/tag/nightly",
              "assets": [
                {
                  "name": "MouseTrails-nightly.dmg",
                  "browser_download_url": "https://github.com/Nina-17/MouseTrails/releases/download/nightly/MouseTrails-nightly.dmg",
                  "size": 1024
                }
              ]
            }
            """.utf8
        )

        let release = try GitHubReleaseClient.decodeRelease(data)

        XCTAssertNil(release.version)
        XCTAssertEqual(release.preferredDMGAsset?.name, "MouseTrails-nightly.dmg")
    }

    func testValidatesDownloadedSizeAndSHA256Digest() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let data = Data("MouseTrails update".utf8)
        try data.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let asset = GitHubReleaseAsset(
            name: "MouseTrails-0.17.0.dmg",
            downloadURL: URL(string: "https://github.com/Nina-17/MouseTrails/releases/download/v0.17.0/MouseTrails-0.17.0.dmg")!,
            size: data.count,
            digest: "sha256:aea548c3324c356ebcc00cb9fbfd2e26315516d5b713cf75ac180bec2bc06a93"
        )

        XCTAssertNoThrow(try GitHubReleaseClient.validateDownloadedFile(at: fileURL, asset: asset))

        var wrongSize = asset
        wrongSize.size += 1
        XCTAssertThrowsError(try GitHubReleaseClient.validateDownloadedFile(at: fileURL, asset: wrongSize)) {
            XCTAssertEqual($0 as? GitHubReleaseError, .downloadSizeMismatch)
        }

        var wrongDigest = asset
        wrongDigest.digest = "sha256:" + String(repeating: "0", count: 64)
        XCTAssertThrowsError(try GitHubReleaseClient.validateDownloadedFile(at: fileURL, asset: wrongDigest)) {
            XCTAssertEqual($0 as? GitHubReleaseError, .checksumMismatch)
        }
    }
}
