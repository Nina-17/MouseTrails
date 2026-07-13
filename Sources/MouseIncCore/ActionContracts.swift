import Foundation

public enum KeyStrokeModifier: String, Codable, CaseIterable, Sendable {
    case command
    case control
    case option
    case shift
}

public enum WindowAction: String, Codable, CaseIterable, Sendable {
    case center
    case maximize
    case minimize
    case close

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if value == "restore" {
            self = .maximize
        } else if let action = Self(rawValue: value) {
            self = action
        } else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unsupported window action \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum CaptureAction: String, Codable, CaseIterable, Sendable {
    case pinRegion
    case copyRegion
    case saveRegion
}

public struct ParsedKeyStroke: Equatable, Sendable {
    public var modifiers: Set<KeyStrokeModifier>
    public var key: String

    public init(modifiers: Set<KeyStrokeModifier>, key: String) {
        self.modifiers = modifiers
        self.key = key
    }
}

public enum KeyStrokeParser {
    public static let supportedKeys: Set<String> = Set(
        Array("abcdefghijklmnopqrstuvwxyz").map(String.init) +
            Array("0123456789").map(String.init) +
            [
                "=", "-", "]", "[", ";", "\\", ",", "/", ".",
                "tab", "space", "delete", "backspace", "escape", "esc",
                "return", "enter", "left", "right", "down", "up"
            ]
    )

    public static func parse(_ value: String) -> ParsedKeyStroke? {
        let tokens = value.split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard let key = tokens.last, supportedKeys.contains(key) else { return nil }

        var modifiers: Set<KeyStrokeModifier> = []
        for token in tokens.dropLast() {
            let modifier: KeyStrokeModifier
            switch token {
            case "command", "cmd": modifier = .command
            case "control", "ctrl": modifier = .control
            case "option", "alt": modifier = .option
            case "shift": modifier = .shift
            default: return nil
            }
            modifiers.insert(modifier)
        }
        return ParsedKeyStroke(modifiers: modifiers, key: key)
    }
}

public struct ActionDescriptor: Equatable, Sendable {
    public var kind: ActionDefinition.Kind
    public var displayName: String
    public var valueDescription: String
    public var requiredPermissions: Set<SystemPermission>

    public init(
        kind: ActionDefinition.Kind,
        displayName: String,
        valueDescription: String,
        requiredPermissions: Set<SystemPermission> = []
    ) {
        self.kind = kind
        self.displayName = displayName
        self.valueDescription = valueDescription
        self.requiredPermissions = requiredPermissions
    }
}

public enum ActionCatalog {
    public static var descriptors: [ActionDescriptor] {
        ActionDefinition.Kind.allCases.map(descriptor(for:))
    }

    public static func descriptor(for kind: ActionDefinition.Kind) -> ActionDescriptor {
        // Keep this exhaustive so adding a Kind requires defining its user-facing
        // contract before it can appear in settings or imported configurations.
        switch kind {
        case .keyStroke:
            ActionDescriptor(
                kind: .keyStroke,
                displayName: "键盘快捷键",
                valueDescription: "例如 Command+C",
                requiredPermissions: [.accessibility]
            )
        case .openURL:
            ActionDescriptor(
                kind: .openURL,
                displayName: "打开 URL",
                valueDescription: "包含 scheme 的完整 URL"
            )
        case .launchApplication:
            ActionDescriptor(
                kind: .launchApplication,
                displayName: "启动应用",
                valueDescription: "Bundle ID 或应用绝对路径"
            )
        case .delay:
            ActionDescriptor(
                kind: .delay,
                displayName: "延时",
                valueDescription: "秒数"
            )
        case .windowAction:
            ActionDescriptor(
                kind: .windowAction,
                displayName: "窗口操作",
                valueDescription: "例如 center",
                requiredPermissions: [.accessibility]
            )
        case .captureAction:
            ActionDescriptor(
                kind: .captureAction,
                displayName: "截图与贴图",
                valueDescription: "按手势范围贴图、复制或保存",
                requiredPermissions: [.screenRecording]
            )
        }
    }
}

public extension AppConfiguration {
    var requiredPermissions: Set<SystemPermission> {
        bindings.reduce(into: Set<SystemPermission>()) { permissions, binding in
            for action in binding.actions {
                permissions.formUnion(ActionCatalog.descriptor(for: action.type).requiredPermissions)
            }
        }
    }
}
