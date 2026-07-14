import Foundation

public enum SystemPermission: String, Codable, CaseIterable, Sendable {
    case accessibility
    case screenRecording
}

public enum PermissionState: String, Codable, Sendable {
    case granted
    case denied
    case notDetermined
    case unavailable
}

public struct PermissionSnapshot: Codable, Equatable, Sendable {
    public var states: [SystemPermission: PermissionState]

    public init(states: [SystemPermission: PermissionState] = [:]) {
        self.states = states
    }

    public subscript(permission: SystemPermission) -> PermissionState {
        states[permission] ?? .notDetermined
    }

    public func satisfies(_ permissions: Set<SystemPermission>) -> Bool {
        permissions.allSatisfy { self[$0] == .granted }
    }
}
