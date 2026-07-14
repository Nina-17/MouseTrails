import Foundation

public struct AppVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    private enum Identifier: Equatable, Sendable {
        case number(Int)
        case text(String)
    }

    public let major: Int
    public let minor: Int
    public let patch: Int
    private let prerelease: [Identifier]

    public init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }

        let withoutBuildMetadata = value.split(
            separator: "+",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )[0]
        let parts = withoutBuildMetadata.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 3).contains(core.count) else { return nil }

        var numbers = core.compactMap { Int($0) }
        guard numbers.count == core.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        while numbers.count < 3 { numbers.append(0) }

        var parsedPrerelease: [Identifier] = []
        if parts.count == 2 {
            let identifiers = parts[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty, identifiers.allSatisfy({ !$0.isEmpty }) else { return nil }
            for identifier in identifiers {
                let text = String(identifier)
                guard text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
                if let number = Int(text) {
                    parsedPrerelease.append(.number(number))
                } else {
                    parsedPrerelease.append(.text(text.lowercased()))
                }
            }
        }

        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
        prerelease = parsedPrerelease
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prerelease.isEmpty else { return core }
        return core + "-" + prerelease.map {
            switch $0 {
            case let .number(value): String(value)
            case let .text(value): value
            }
        }.joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        if lhsCore != rhsCore {
            return lhsCore.lexicographicallyPrecedes(rhsCore)
        }

        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (left, right) {
            case let (.number(lhsValue), .number(rhsValue)):
                return lhsValue < rhsValue
            case (.number, .text):
                return true
            case (.text, .number):
                return false
            case let (.text(lhsValue), .text(rhsValue)):
                return lhsValue < rhsValue
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
