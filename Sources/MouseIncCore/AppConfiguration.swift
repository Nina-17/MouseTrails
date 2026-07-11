import Foundation

public struct AppConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public var gestureOptions: GestureOptions
    public var actionSequenceOptions: ActionSequenceOptions
    public var bindings: [GestureBinding]

    public init(
        enabled: Bool = true,
        startDistance: Double = 12,
        simplificationTolerance: Double = 18,
        minimumGestureLength: Double = 40,
        maximumDuration: TimeInterval = 5,
        showsTrail: Bool = true,
        reportsFailures: Bool = true,
        actionSequenceOptions: ActionSequenceOptions = ActionSequenceOptions(),
        bindings: [GestureBinding] = GestureBinding.defaults
    ) {
        schemaVersion = Self.currentSchemaVersion
        gestureOptions = GestureOptions(
            enabled: enabled,
            startDistance: startDistance,
            simplificationTolerance: simplificationTolerance,
            minimumGestureLength: minimumGestureLength,
            maximumDuration: maximumDuration,
            showsTrail: showsTrail,
            reportsFailures: reportsFailures
        )
        self.actionSequenceOptions = actionSequenceOptions
        self.bindings = bindings
    }

    public init(
        gestureOptions: GestureOptions,
        actionSequenceOptions: ActionSequenceOptions = ActionSequenceOptions(),
        bindings: [GestureBinding] = GestureBinding.defaults
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.gestureOptions = gestureOptions
        self.actionSequenceOptions = actionSequenceOptions
        self.bindings = bindings
    }

    // These forwarding properties preserve the original public API while callers
    // migrate to the grouped gestureOptions model.
    public var enabled: Bool {
        get { gestureOptions.enabled }
        set { gestureOptions.enabled = newValue }
    }

    public var startDistance: Double {
        get { gestureOptions.startDistance }
        set { gestureOptions.startDistance = newValue }
    }

    public var simplificationTolerance: Double {
        get { gestureOptions.simplificationTolerance }
        set { gestureOptions.simplificationTolerance = newValue }
    }

    public var minimumGestureLength: Double {
        get { gestureOptions.minimumGestureLength }
        set { gestureOptions.minimumGestureLength = newValue }
    }

    public var maximumDuration: TimeInterval {
        get { gestureOptions.maximumDuration }
        set { gestureOptions.maximumDuration = newValue }
    }

    public var showsTrail: Bool {
        get { gestureOptions.showsTrail }
        set { gestureOptions.showsTrail = newValue }
    }

    public var reportsFailures: Bool {
        get { gestureOptions.reportsFailures }
        set { gestureOptions.reportsFailures = newValue }
    }

    public func binding(for gesture: String, bundleIdentifier: String?) -> GestureBinding? {
        let candidates = bindings.filter { $0.gesture.caseInsensitiveCompare(gesture) == .orderedSame }

        if let bundleIdentifier,
           let applicationBinding = candidates.first(where: {
               $0.bundleIdentifiers.contains { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
           }) {
            return applicationBinding
        }

        return candidates.first(where: { $0.bundleIdentifiers.isEmpty })
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case gestureOptions
        case actionSequenceOptions
        case bindings

        // Legacy schema (implicit version 1).
        case enabled
        case startDistance
        case simplificationTolerance
        case minimumGestureLength
        case maximumDuration
        case showsTrail
        case reportsFailures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard storedVersion <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported configuration schema version \(storedVersion); " +
                    "this build supports up to version \(Self.currentSchemaVersion)."
            )
        }

        schemaVersion = Self.currentSchemaVersion
        if let options = try container.decodeIfPresent(GestureOptions.self, forKey: .gestureOptions) {
            gestureOptions = options
        } else {
            let defaults = GestureOptions()
            gestureOptions = GestureOptions(
                enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled,
                startDistance: try container.decodeIfPresent(Double.self, forKey: .startDistance) ?? defaults.startDistance,
                simplificationTolerance: try container.decodeIfPresent(
                    Double.self,
                    forKey: .simplificationTolerance
                ) ?? defaults.simplificationTolerance,
                minimumGestureLength: try container.decodeIfPresent(
                    Double.self,
                    forKey: .minimumGestureLength
                ) ?? defaults.minimumGestureLength,
                maximumDuration: try container.decodeIfPresent(
                    TimeInterval.self,
                    forKey: .maximumDuration
                ) ?? defaults.maximumDuration,
                showsTrail: try container.decodeIfPresent(Bool.self, forKey: .showsTrail) ?? defaults.showsTrail,
                reportsFailures: try container.decodeIfPresent(
                    Bool.self,
                    forKey: .reportsFailures
                ) ?? defaults.reportsFailures
            )
        }
        actionSequenceOptions = try container.decodeIfPresent(
            ActionSequenceOptions.self,
            forKey: .actionSequenceOptions
        ) ?? ActionSequenceOptions()
        bindings = try container.decodeIfPresent([GestureBinding].self, forKey: .bindings)
            ?? GestureBinding.defaults
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(gestureOptions, forKey: .gestureOptions)
        try container.encode(actionSequenceOptions, forKey: .actionSequenceOptions)
        try container.encode(bindings, forKey: .bindings)
    }
}

public struct ActionSequenceOptions: Codable, Equatable, Sendable {
    public enum InterruptionPolicy: String, Codable, Sendable {
        case cancelPrevious
        case ignoreNew
    }

    public enum FailurePolicy: String, Codable, Sendable {
        case stop
        case continueSequence
    }

    public var interruptionPolicy: InterruptionPolicy
    public var failurePolicy: FailurePolicy
    public var maximumDelay: TimeInterval

    public init(
        interruptionPolicy: InterruptionPolicy = .cancelPrevious,
        failurePolicy: FailurePolicy = .stop,
        maximumDelay: TimeInterval = 60
    ) {
        self.interruptionPolicy = interruptionPolicy
        self.failurePolicy = failurePolicy
        self.maximumDelay = maximumDelay
    }

    private enum CodingKeys: String, CodingKey {
        case interruptionPolicy
        case failurePolicy
        case maximumDelay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ActionSequenceOptions()
        interruptionPolicy = try container.decodeIfPresent(
            InterruptionPolicy.self,
            forKey: .interruptionPolicy
        ) ?? defaults.interruptionPolicy
        failurePolicy = try container.decodeIfPresent(
            FailurePolicy.self,
            forKey: .failurePolicy
        ) ?? defaults.failurePolicy
        maximumDelay = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .maximumDelay
        ) ?? defaults.maximumDelay
    }
}

public struct GestureOptions: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var startDistance: Double
    public var simplificationTolerance: Double
    public var minimumGestureLength: Double
    public var maximumDuration: TimeInterval
    public var showsTrail: Bool
    public var reportsFailures: Bool

    public init(
        enabled: Bool = true,
        startDistance: Double = 12,
        simplificationTolerance: Double = 18,
        minimumGestureLength: Double = 40,
        maximumDuration: TimeInterval = 5,
        showsTrail: Bool = true,
        reportsFailures: Bool = true
    ) {
        self.enabled = enabled
        self.startDistance = startDistance
        self.simplificationTolerance = simplificationTolerance
        self.minimumGestureLength = minimumGestureLength
        self.maximumDuration = maximumDuration
        self.showsTrail = showsTrail
        self.reportsFailures = reportsFailures
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case startDistance
        case simplificationTolerance
        case minimumGestureLength
        case maximumDuration
        case showsTrail
        case reportsFailures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GestureOptions()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        startDistance = try container.decodeIfPresent(Double.self, forKey: .startDistance) ?? defaults.startDistance
        simplificationTolerance = try container.decodeIfPresent(
            Double.self,
            forKey: .simplificationTolerance
        ) ?? defaults.simplificationTolerance
        minimumGestureLength = try container.decodeIfPresent(
            Double.self,
            forKey: .minimumGestureLength
        ) ?? defaults.minimumGestureLength
        maximumDuration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .maximumDuration
        ) ?? defaults.maximumDuration
        showsTrail = try container.decodeIfPresent(Bool.self, forKey: .showsTrail) ?? defaults.showsTrail
        reportsFailures = try container.decodeIfPresent(
            Bool.self,
            forKey: .reportsFailures
        ) ?? defaults.reportsFailures
    }
}

public struct GestureBinding: Codable, Equatable, Sendable {
    public var gesture: String
    public var name: String
    public var bundleIdentifiers: [String]
    public var actions: [ActionDefinition]

    public init(
        gesture: String,
        name: String,
        bundleIdentifiers: [String] = [],
        actions: [ActionDefinition]
    ) {
        self.gesture = gesture
        self.name = name
        self.bundleIdentifiers = bundleIdentifiers
        self.actions = actions
    }

    public static let defaults: [GestureBinding] = [
        GestureBinding(
            gesture: "UP",
            name: "复制",
            actions: [ActionDefinition(type: .keyStroke, value: "Command+C")]
        ),
        GestureBinding(
            gesture: "DOWN",
            name: "粘贴",
            actions: [ActionDefinition(type: .keyStroke, value: "Command+V")]
        ),
        GestureBinding(
            gesture: "LEFT",
            name: "后退",
            actions: [ActionDefinition(type: .keyStroke, value: "Command+[")]
        ),
        GestureBinding(
            gesture: "RIGHT",
            name: "前进",
            actions: [ActionDefinition(type: .keyStroke, value: "Command+]")]
        ),
        GestureBinding(
            gesture: "DOWN-RIGHT",
            name: "关闭窗口或标签",
            actions: [ActionDefinition(type: .keyStroke, value: "Command+W")]
        )
    ]
}

public struct ActionDefinition: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case keyStroke
        case openURL
        case launchApplication
        case delay
    }

    public var type: Kind
    public var value: String

    public init(type: Kind, value: String) {
        self.type = type
        self.value = value
    }

    public static func delay(seconds: TimeInterval) -> ActionDefinition {
        ActionDefinition(type: .delay, value: String(seconds))
    }
}
