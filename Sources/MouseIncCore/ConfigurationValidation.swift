import Foundation

public enum ConfigurationIssueSeverity: String, Codable, Sendable {
    case warning
    case error
}

public enum ConfigurationIssueCode: String, Codable, Sendable {
    case invalidGestureOption
    case invalidActionSequenceOption
    case emptyGesture
    case emptyBindingName
    case emptyActionSequence
    case duplicateBinding
    case invalidBundleIdentifier
    case invalidActionValue
}

public struct ConfigurationIssue: Codable, Equatable, Sendable {
    public var severity: ConfigurationIssueSeverity
    public var code: ConfigurationIssueCode
    public var path: String
    public var message: String

    public init(
        severity: ConfigurationIssueSeverity,
        code: ConfigurationIssueCode,
        path: String,
        message: String
    ) {
        self.severity = severity
        self.code = code
        self.path = path
        self.message = message
    }
}

public struct ConfigurationValidationResult: Equatable, Sendable {
    public var issues: [ConfigurationIssue]

    public init(issues: [ConfigurationIssue]) {
        self.issues = issues
    }

    public var isValid: Bool {
        !issues.contains { $0.severity == .error }
    }
}

public extension AppConfiguration {
    func validate() -> ConfigurationValidationResult {
        var issues: [ConfigurationIssue] = []
        validateGestureOptions(into: &issues)
        validateActionSequenceOptions(into: &issues)
        validateBindings(into: &issues)
        return ConfigurationValidationResult(issues: issues)
    }

    private func validateGestureOptions(into issues: inout [ConfigurationIssue]) {
        let values: [(String, Double, ClosedRange<Double>)] = [
            ("startDistance", gestureOptions.startDistance, 0 ... 500),
            ("simplificationTolerance", gestureOptions.simplificationTolerance, 0 ... 500),
            ("minimumGestureLength", gestureOptions.minimumGestureLength, 1 ... 10_000),
            ("maximumDuration", gestureOptions.maximumDuration, 0.1 ... 60)
        ]
        for (name, value, range) in values where !value.isFinite || !range.contains(value) {
            issues.append(
                ConfigurationIssue(
                    severity: .error,
                    code: .invalidGestureOption,
                    path: "gestureOptions.\(name)",
                    message: "\(name) 必须位于 \(range.lowerBound)...\(range.upperBound) 之间"
                )
            )
        }
    }

    private func validateActionSequenceOptions(into issues: inout [ConfigurationIssue]) {
        let value = actionSequenceOptions.maximumDelay
        if !value.isFinite || !(0 ... 3_600).contains(value) {
            issues.append(
                ConfigurationIssue(
                    severity: .error,
                    code: .invalidActionSequenceOption,
                    path: "actionSequenceOptions.maximumDelay",
                    message: "maximumDelay 必须位于 0...3600 之间"
                )
            )
        }
    }

    private func validateBindings(into issues: inout [ConfigurationIssue]) {
        var seenScopes: Set<String> = []

        for (bindingIndex, binding) in bindings.enumerated() {
            let bindingPath = "bindings[\(bindingIndex)]"
            let gesture = binding.gesture.trimmingCharacters(in: .whitespacesAndNewlines)
            if gesture.isEmpty {
                issues.append(
                    ConfigurationIssue(
                        severity: .error,
                        code: .emptyGesture,
                        path: "\(bindingPath).gesture",
                        message: "手势标识不能为空"
                    )
                )
            }

            if binding.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(
                    ConfigurationIssue(
                        severity: .warning,
                        code: .emptyBindingName,
                        path: "\(bindingPath).name",
                        message: "建议为绑定填写可读名称"
                    )
                )
            }

            if binding.actions.isEmpty {
                issues.append(
                    ConfigurationIssue(
                        severity: .error,
                        code: .emptyActionSequence,
                        path: "\(bindingPath).actions",
                        message: "动作序列不能为空"
                    )
                )
            }

            let scopes = binding.bundleIdentifiers.isEmpty ? ["*"] : binding.bundleIdentifiers
            for (scopeIndex, rawScope) in scopes.enumerated() {
                let scope = rawScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if scope.isEmpty {
                    issues.append(
                        ConfigurationIssue(
                            severity: .error,
                            code: .invalidBundleIdentifier,
                            path: "\(bindingPath).bundleIdentifiers[\(scopeIndex)]",
                            message: "Bundle ID 不能为空"
                        )
                    )
                    continue
                }
                let key = "\(gesture.uppercased())|\(scope)"
                if !gesture.isEmpty, !seenScopes.insert(key).inserted {
                    issues.append(
                        ConfigurationIssue(
                            severity: .error,
                            code: .duplicateBinding,
                            path: bindingPath,
                            message: "同一手势和应用范围存在重复绑定"
                        )
                    )
                }
            }

            for (actionIndex, action) in binding.actions.enumerated() {
                validate(
                    action,
                    path: "\(bindingPath).actions[\(actionIndex)]",
                    into: &issues
                )
            }
        }
    }

    private func validate(
        _ action: ActionDefinition,
        path: String,
        into issues: inout [ConfigurationIssue]
    ) {
        let value = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String?

        switch action.type {
        case .keyStroke:
            message = KeyStrokeParser.parse(value) == nil ? "快捷键格式无效" : nil
        case .openURL:
            if value.isEmpty || URL(string: value)?.scheme?.isEmpty != false {
                message = "URL 必须包含有效 scheme"
            } else {
                message = nil
            }
        case .launchApplication:
            message = value.isEmpty ? "应用 Bundle ID 或路径不能为空" : nil
        case .delay:
            if let seconds = TimeInterval(value),
               seconds.isFinite,
               seconds >= 0,
               seconds <= actionSequenceOptions.maximumDelay {
                message = nil
            } else {
                message = "延时必须是 0...\(actionSequenceOptions.maximumDelay) 秒之间的数值"
            }
        }

        if let message {
            issues.append(
                ConfigurationIssue(
                    severity: .error,
                    code: .invalidActionValue,
                    path: "\(path).value",
                    message: message
                )
            )
        }
    }
}
