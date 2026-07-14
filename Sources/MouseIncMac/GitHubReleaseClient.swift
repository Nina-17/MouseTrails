import CryptoKit
import Foundation
import MouseIncCore

struct GitHubReleaseAsset: Decodable, Equatable, Sendable {
    var name: String
    var downloadURL: URL
    var size: Int
    var digest: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
        case size
        case digest
    }
}

struct GitHubRelease: Decodable, Equatable, Sendable {
    var tagName: String
    var name: String?
    var notes: String?
    var pageURL: URL
    var assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case notes = "body"
        case pageURL = "html_url"
        case assets
    }

    var version: AppVersion? {
        AppVersion(tagName)
    }

    var preferredDMGAsset: GitHubReleaseAsset? {
        guard let version else {
            return assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        }
        let preferredName = "MouseTrails-\(version).dmg"
        return assets.first { $0.name.caseInsensitiveCompare(preferredName) == .orderedSame }
            ?? assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
}

enum GitHubReleaseError: LocalizedError, Equatable {
    case noPublishedRelease
    case invalidResponse
    case httpStatus(Int)
    case invalidDownloadURL
    case downloadTooLarge
    case downloadSizeMismatch
    case checksumMismatch
    case invalidAssetName

    var errorDescription: String? {
        switch self {
        case .noPublishedRelease:
            return "GitHub 仓库尚无正式 Release"
        case .invalidResponse:
            return "GitHub 返回了无效响应"
        case let .httpStatus(code):
            return "GitHub 请求失败（HTTP \(code)）"
        case .invalidDownloadURL:
            return "Release 下载地址不安全"
        case .downloadTooLarge:
            return "Release 文件超过 512 MB 安全上限"
        case .downloadSizeMismatch:
            return "Release 文件大小与 GitHub 记录不一致"
        case .checksumMismatch:
            return "Release 文件 SHA-256 校验失败"
        case .invalidAssetName:
            return "Release 文件名无效"
        }
    }
}

actor GitHubReleaseClient {
    static let repository = "Nina-17/MouseTrails"
    static let maximumAssetSize = 512 * 1_024 * 1_024

    private let session: URLSession
    private let latestReleaseURL: URL

    init(
        session: URLSession = .shared,
        latestReleaseURL: URL = URL(
            string: "https://api.github.com/repos/\(repository)/releases/latest"
        )!
    ) {
        self.session = session
        self.latestReleaseURL = latestReleaseURL
    }

    func latestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MouseTrails", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubReleaseError.invalidResponse
        }
        if response.statusCode == 404 {
            throw GitHubReleaseError.noPublishedRelease
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw GitHubReleaseError.httpStatus(response.statusCode)
        }
        return try Self.decodeRelease(data)
    }

    func download(_ asset: GitHubReleaseAsset, to directory: URL) async throws -> URL {
        guard asset.downloadURL.scheme == "https", asset.downloadURL.host == "github.com" else {
            throw GitHubReleaseError.invalidDownloadURL
        }
        guard asset.size >= 0, asset.size <= Self.maximumAssetSize else {
            throw GitHubReleaseError.downloadTooLarge
        }
        guard asset.name == URL(fileURLWithPath: asset.name).lastPathComponent,
              asset.name.lowercased().hasSuffix(".dmg") else {
            throw GitHubReleaseError.invalidAssetName
        }

        var request = URLRequest(url: asset.downloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("MouseTrails", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubReleaseError.invalidResponse
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw GitHubReleaseError.httpStatus(response.statusCode)
        }

        let destination = directory.appendingPathComponent(asset.name, isDirectory: false)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(
            ".\(asset.name).\(UUID().uuidString).partial",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.moveItem(at: temporaryURL, to: staging)

        try Self.validateDownloadedFile(at: staging, asset: asset)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        return destination
    }

    nonisolated static func validateDownloadedFile(
        at fileURL: URL,
        asset: GitHubReleaseAsset
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attributes[.size] as? NSNumber {
            if size.intValue > maximumAssetSize {
                throw GitHubReleaseError.downloadTooLarge
            }
            if asset.size > 0, size.intValue != asset.size {
                throw GitHubReleaseError.downloadSizeMismatch
            }
        }
        if let digest = asset.digest?.lowercased(), digest.hasPrefix("sha256:") {
            let expected = String(digest.dropFirst("sha256:".count))
            guard try sha256(of: fileURL) == expected else {
                throw GitHubReleaseError.checksumMismatch
            }
        }
    }

    private nonisolated static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func decodeRelease(_ data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}
