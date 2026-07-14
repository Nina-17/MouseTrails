import Foundation
import MouseIncCore

struct InstalledAppCopy: Equatable {
    let url: URL
    let version: AppVersion
}

enum InstalledAppLocator {
    static let bundleIdentifier = "com.mason.mouseincmac"

    static func newerCopy(
        than current: InstalledAppCopy,
        candidates: [InstalledAppCopy]
    ) -> InstalledAppCopy? {
        candidates
            .filter { $0.url.standardizedFileURL != current.url.standardizedFileURL }
            .filter { $0.version > current.version }
            .max { $0.version < $1.version }
    }

    static func newerInstalledCopy(
        than currentBundleURL: URL = Bundle.main.bundleURL,
        currentVersionString: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0",
        fileManager: FileManager = .default
    ) -> InstalledAppCopy? {
        guard let currentVersion = AppVersion(currentVersionString) else { return nil }
        let current = InstalledAppCopy(url: currentBundleURL, version: currentVersion)
        let candidates = commonInstallLocations.compactMap { url -> InstalledAppCopy? in
            guard fileManager.fileExists(atPath: url.path),
                  let bundle = Bundle(url: url),
                  bundle.bundleIdentifier == bundleIdentifier,
                  let rawVersion = bundle.object(
                      forInfoDictionaryKey: "CFBundleShortVersionString"
                  ) as? String,
                  let version = AppVersion(rawVersion) else {
                return nil
            }
            return InstalledAppCopy(url: url, version: version)
        }
        return newerCopy(than: current, candidates: candidates)
    }

    private static var commonInstallLocations: [URL] {
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/MouseTrails.app")
        return [
            homeApplications,
            URL(fileURLWithPath: "/Applications/MouseTrails.app")
        ]
    }
}
