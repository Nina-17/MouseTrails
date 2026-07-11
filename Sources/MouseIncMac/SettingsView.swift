import MouseIncCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                gestureSection
                sequenceSection
                bindingsSection
                validationSection
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text(model.saveMessage ?? "Schema 3 配置")
                    .foregroundStyle(model.canSave ? Color.secondary : Color.red)
                Spacer()
                Button("保存") { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.canSave)
            }
            .padding()
        }
        .frame(minWidth: 720, minHeight: 620)
    }

    private var gestureSection: some View {
        Section("手势") {
            Toggle("启用鼠标与触控板手势", isOn: $model.draft.gestureOptions.enabled)
            Toggle("显示轨迹", isOn: $model.draft.gestureOptions.showsTrail)
            Toggle("报告识别失败", isOn: $model.draft.gestureOptions.reportsFailures)
            numberField("启动距离", value: $model.draft.gestureOptions.startDistance)
            numberField("简化容差", value: $model.draft.gestureOptions.simplificationTolerance)
            numberField("最小手势长度", value: $model.draft.gestureOptions.minimumGestureLength)
            numberField("最长持续时间", value: $model.draft.gestureOptions.maximumDuration)
        }
    }

    private var sequenceSection: some View {
        Section("动作序列") {
            Picker("新手势到来时", selection: $model.draft.actionSequenceOptions.interruptionPolicy) {
                Text("取消上一序列").tag(ActionSequenceOptions.InterruptionPolicy.cancelPrevious)
                Text("忽略新手势").tag(ActionSequenceOptions.InterruptionPolicy.ignoreNew)
            }
            Picker("动作失败时", selection: $model.draft.actionSequenceOptions.failurePolicy) {
                Text("停止序列").tag(ActionSequenceOptions.FailurePolicy.stop)
                Text("继续执行").tag(ActionSequenceOptions.FailurePolicy.continueSequence)
            }
            numberField("最大延时（秒）", value: $model.draft.actionSequenceOptions.maximumDelay)
        }
    }

    private var bindingsSection: some View {
        Section("手势绑定") {
            ForEach(model.draft.bindings.indices, id: \.self) { bindingIndex in
                bindingEditor(at: bindingIndex)
            }
            Button {
                model.addBinding()
            } label: {
                Label("添加手势绑定", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private func bindingEditor(at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("名称", text: $model.draft.bindings[index].name)
                TextField("手势，如 UP_RIGHT 或 DOWN-RIGHT", text: $model.draft.bindings[index].gesture)
                Button(role: .destructive) { model.removeBinding(at: index) } label: {
                    Image(systemName: "trash")
                }
            }
            TextField("Bundle ID（逗号分隔；留空表示全局）", text: bundleIDsBinding(at: index))

            ForEach(model.draft.bindings[index].actions.indices, id: \.self) { actionIndex in
                HStack {
                    Picker("", selection: actionTypeBinding(binding: index, action: actionIndex)) {
                        ForEach(ActionCatalog.descriptors, id: \.kind) { descriptor in
                            Text(descriptor.displayName).tag(descriptor.kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    actionValueEditor(binding: index, action: actionIndex)
                    Button(role: .destructive) {
                        model.removeAction(at: actionIndex, from: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                }
            }
            Button("添加动作") { model.addAction(to: index) }
                .buttonStyle(.link)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func actionValueEditor(binding: Int, action: Int) -> some View {
        if model.draft.bindings[binding].actions[action].type == .windowAction {
            Picker("窗口动作", selection: $model.draft.bindings[binding].actions[action].value) {
                ForEach(WindowAction.allCases, id: \.self) { value in
                    Text(value.rawValue == "center" ? "居中窗口" : value.rawValue).tag(value.rawValue)
                }
            }
            .labelsHidden()
        } else {
            let kind = model.draft.bindings[binding].actions[action].type
            TextField(ActionCatalog.descriptor(for: kind).valueDescription,
                      text: $model.draft.bindings[binding].actions[action].value)
        }
    }

    private var validationSection: some View {
        Section("配置检查") {
            if model.validation.issues.isEmpty {
                Label("配置有效", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(Array(model.validation.issues.enumerated()), id: \.offset) { _, issue in
                    Text("\(issue.path)：\(issue.message)")
                        .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                }
            }
        }
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number)
    }

    private func bundleIDsBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { model.draft.bindings[index].bundleIdentifiers.joined(separator: ", ") },
            set: { value in
                model.draft.bindings[index].bundleIdentifiers = value
                    .split(separator: ",", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        )
    }

    private func actionTypeBinding(binding: Int, action: Int) -> Binding<ActionDefinition.Kind> {
        Binding(
            get: { model.draft.bindings[binding].actions[action].type },
            set: { kind in
                model.draft.bindings[binding].actions[action].type = kind
                model.draft.bindings[binding].actions[action].value = defaultValue(for: kind)
            }
        )
    }

    private func defaultValue(for kind: ActionDefinition.Kind) -> String {
        switch kind {
        case .keyStroke: "Command+C"
        case .openURL: "https://"
        case .launchApplication: "com.apple.finder"
        case .delay: "0.2"
        case .windowAction: WindowAction.center.rawValue
        }
    }
}
