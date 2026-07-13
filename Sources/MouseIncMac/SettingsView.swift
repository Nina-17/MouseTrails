import MouseIncCore
import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                gestureSection
                sequenceSection
                edgeScrollSection
                bindingsSection
                permissionSection
                pinnedImageHelpSection
                configurationFilesSection
                validationSection
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Text(model.saveMessage ?? "Schema \(AppConfiguration.currentSchemaVersion) 配置")
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
            Picker("轨迹颜色", selection: $model.draft.gestureOptions.trailColor) {
                ForEach(GestureTrailColor.allCases, id: \.self) { color in
                    Text(trailColorName(color)).tag(color)
                }
            }
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

    private func trailColorName(_ color: GestureTrailColor) -> String {
        switch color {
        case .orange: return "橙色"
        case .blue: return "蓝色"
        case .green: return "绿色"
        case .pink: return "粉色"
        case .purple: return "紫色"
        }
    }

    private var edgeScrollSection: some View {
        Section("边缘滚轮（简化版）") {
            Toggle("启用左亮度、右音量", isOn: $model.draft.edgeScrollOptions.enabled)
            numberField("边缘宽度（点）", value: $model.draft.edgeScrollOptions.inset)
            numberField("每次调节比例", value: $model.draft.edgeScrollOptions.step)
            numberField("冷却时间（秒）", value: $model.draft.edgeScrollOptions.cooldown)
            Text("左边缘滚动调亮度，右边缘滚动调系统输出音量；上、下边缘不处理。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bindingsSection: some View {
        Section("手势绑定") {
            ForEach(Array(model.bindingIDs.enumerated()), id: \.element) { bindingIndex, _ in
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
        if let binding = model.binding(at: index) {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
                GesturePreview(identifier: binding.gesture)
                    .frame(width: 90, height: 64)
                TextField("名称", text: bindingText(at: index, keyPath: \.name))
                Menu {
                    Section("单方向") {
                        gestureChoices(cardinalGestureChoices, bindingIndex: index)
                    }
                    Section("复杂模板") {
                        gestureChoices(templateGestureChoices, bindingIndex: index)
                    }
                    Section("常用折线") {
                        gestureChoices(polylineGestureChoices, bindingIndex: index)
                    }
                } label: {
                    Label(displayName(for: binding.gesture), systemImage: "scribble.variable")
                }
                .frame(minWidth: 130)
                TextField("手势标识", text: bindingText(at: index, keyPath: \.gesture))
                    .frame(minWidth: 120)
                Button { model.moveBinding(from: index, by: -1) } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(index == 0)
                Button { model.moveBinding(from: index, by: 1) } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(index == model.draft.bindings.count - 1)
                Button(role: .destructive) { model.removeBinding(at: index) } label: {
                    Image(systemName: "trash")
                }
            }
            HStack {
                TextField("Bundle ID（逗号分隔；留空表示全局）", text: bundleIDsBinding(at: index))
                Button("选择应用…") { chooseApplication(for: index) }
            }

            ForEach(binding.actions.indices, id: \.self) { actionIndex in
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
            ForEach(Array(model.issues(for: index).enumerated()), id: \.offset) { _, issue in
                Label(issue.message, systemImage: issue.severity == .error
                      ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
            }
          }
          .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func actionValueEditor(binding: Int, action: Int) -> some View {
        if actionKind(binding: binding, action: action) == .windowAction {
            Picker("窗口动作", selection: actionValueBinding(binding: binding, action: action)) {
                ForEach(WindowAction.allCases, id: \.self) { value in
                    Text(windowActionName(value)).tag(value.rawValue)
                }
            }
            .labelsHidden()
        } else if actionKind(binding: binding, action: action) == .captureAction {
            Picker("截图动作", selection: actionValueBinding(binding: binding, action: action)) {
                ForEach(CaptureAction.allCases, id: \.self) { value in
                    Text(captureActionName(value)).tag(value.rawValue)
                }
            }
            .labelsHidden()
        } else if actionKind(binding: binding, action: action) == .ocrAction {
            Picker("OCR 动作", selection: actionValueBinding(binding: binding, action: action)) {
                ForEach(OCRAction.allCases, id: \.self) { value in
                    Text(ocrActionName(value)).tag(value.rawValue)
                }
            }
            .labelsHidden()
        } else if actionKind(binding: binding, action: action) == .searchSelectedText {
            TextField("搜索 URL 模板", text: actionValueBinding(binding: binding, action: action))
        } else {
            let kind = actionKind(binding: binding, action: action)
            TextField(ActionCatalog.descriptor(for: kind).valueDescription,
                      text: actionValueBinding(binding: binding, action: action))
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

    private var permissionSection: some View {
        let snapshot = PermissionCoordinator.snapshot
        return Section("权限") {
            permissionRow("辅助功能", state: snapshot[.accessibility], required: true)
            permissionRow(
                "屏幕录制",
                state: snapshot[.screenRecording],
                required: model.draft.requiredPermissions.contains(.screenRecording)
            )
            permissionRow("输入监控", state: snapshot[.inputMonitoring], required: false)
            Text("截图、贴图与 OCR 首次使用时才请求屏幕录制权限；拒绝不会影响手势和窗口动作。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var configurationFilesSection: some View {
        Section("导出与恢复") {
            HStack {
                Button("导出配置…") { exportConfiguration() }
                    .disabled(!model.canSave)
                Button("从备份恢复…") { restoreConfiguration() }
            }
            Text("恢复前会先在配置目录保存当前文件的时间戳备份。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pinnedImageHelpSection: some View {
        Section("贴图操作") {
            Text("左键拖动；单击折叠或恢复；展开时右键关闭")
            Text("光标停在贴图上时，滚轮或触控板双指滑动可调整透明度（20%–100%）")
            Text("展开并选中贴图后，Command+C 可复制图像或在 Finder 中粘贴 PNG；缩小状态右键可另存为 PNG")
        }
    }

    private func permissionRow(_ name: String, state: PermissionState, required: Bool) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(permissionStateName(state, required: required))
                .foregroundStyle(state == .granted ? Color.green : (required ? Color.red : Color.secondary))
        }
    }

    private func permissionStateName(_ state: PermissionState, required: Bool) -> String {
        if !required, state != .granted { return "当前未使用" }
        switch state {
        case .granted: return "已授权"
        case .denied: return "未授权"
        case .notDetermined: return "未请求"
        case .unavailable: return "不可用"
        }
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number)
    }

    private func bundleIDsBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard model.draft.bindings.indices.contains(index) else { return "" }
                return model.draft.bindings[index].bundleIdentifiers.joined(separator: ", ")
            },
            set: { value in
                guard model.draft.bindings.indices.contains(index) else { return }
                model.draft.bindings[index].bundleIdentifiers = value
                    .split(separator: ",", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        )
    }

    private func bindingText(
        at index: Int,
        keyPath: WritableKeyPath<GestureBinding, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard model.draft.bindings.indices.contains(index) else { return "" }
                return model.draft.bindings[index][keyPath: keyPath]
            },
            set: { value in
                guard model.draft.bindings.indices.contains(index) else { return }
                model.draft.bindings[index][keyPath: keyPath] = value
            }
        )
    }

    private func actionKind(binding: Int, action: Int) -> ActionDefinition.Kind {
        guard
            model.draft.bindings.indices.contains(binding),
            model.draft.bindings[binding].actions.indices.contains(action)
        else { return .keyStroke }
        return model.draft.bindings[binding].actions[action].type
    }

    private func actionValueBinding(binding: Int, action: Int) -> Binding<String> {
        Binding(
            get: {
                guard
                    model.draft.bindings.indices.contains(binding),
                    model.draft.bindings[binding].actions.indices.contains(action)
                else { return "" }
                return model.draft.bindings[binding].actions[action].value
            },
            set: { value in
                guard
                    model.draft.bindings.indices.contains(binding),
                    model.draft.bindings[binding].actions.indices.contains(action)
                else { return }
                model.draft.bindings[binding].actions[action].value = value
            }
        )
    }

    private func actionTypeBinding(binding: Int, action: Int) -> Binding<ActionDefinition.Kind> {
        Binding(
            get: {
                guard
                    model.draft.bindings.indices.contains(binding),
                    model.draft.bindings[binding].actions.indices.contains(action)
                else { return .keyStroke }
                return model.draft.bindings[binding].actions[action].type
            },
            set: { kind in
                guard
                    model.draft.bindings.indices.contains(binding),
                    model.draft.bindings[binding].actions.indices.contains(action)
                else { return }
                model.draft.bindings[binding].actions[action].type = kind
                model.draft.bindings[binding].actions[action].value = defaultValue(for: kind)
            }
        )
    }

    private func chooseApplication(for bindingIndex: Int) {
        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.prompt = "使用此应用"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !model.useApplication(at: url, for: bindingIndex) {
            let alert = NSAlert()
            alert.messageText = "无法读取应用标识"
            alert.informativeText = "请选择包含 Bundle Identifier 的 macOS 应用。"
            alert.runModal()
        }
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.title = "导出 MouseIncMac 配置"
        panel.nameFieldStringValue = "MouseIncMac-config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(to: url)
    }

    private func restoreConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "选择 MouseIncMac 配置备份"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "恢复此配置？"
        alert.informativeText = "现有配置会先自动备份，然后替换为选中的配置。"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.restore(from: url)
    }

    private func windowActionName(_ action: WindowAction) -> String {
        switch action {
        case .center: return "居中窗口"
        case .maximize: return "切换全屏（独立空间）"
        case .minimize: return "最小化窗口"
        case .close: return "关闭窗口"
        }
    }

    @ViewBuilder
    private func gestureChoices(_ choices: [(String, String)], bindingIndex: Int) -> some View {
        ForEach(choices, id: \.0) { identifier, name in
            Button(name) { model.setGesture(identifier, for: bindingIndex) }
        }
    }

    private var cardinalGestureChoices: [(String, String)] {
        [
            ("UP", "上"), ("DOWN", "下"), ("LEFT", "左"), ("RIGHT", "右"),
            ("UP_LEFT", "左上"), ("UP_RIGHT", "右上"),
            ("DOWN_LEFT", "左下"), ("DOWN_RIGHT", "右下")
        ]
    }

    private var templateGestureChoices: [(String, String)] {
        [
            ("SQUARE_CLOCKWISE", "顺时针方框"),
            ("SQUARE_COUNTERCLOCKWISE", "逆时针方框"),
            ("LETTER_S", "字母 S"),
            ("LETTER_W", "字母 W")
        ]
    }

    private var polylineGestureChoices: [(String, String)] {
        [
            ("DOWN-RIGHT", "下 → 右"),
            ("UP-RIGHT", "上 → 右"),
            ("LEFT-DOWN", "左 → 下"),
            ("RIGHT-DOWN", "右 → 下")
        ]
    }

    private func displayName(for identifier: String) -> String {
        (cardinalGestureChoices + templateGestureChoices + polylineGestureChoices)
            .first { $0.0 == identifier }?.1 ?? identifier
    }

    private func defaultValue(for kind: ActionDefinition.Kind) -> String {
        switch kind {
        case .keyStroke: "Command+C"
        case .openURL: "https://"
        case .launchApplication: "com.apple.finder"
        case .delay: "0.2"
        case .windowAction: WindowAction.center.rawValue
        case .captureAction: CaptureAction.pinRegion.rawValue
        case .ocrAction: OCRAction.recognizeRegion.rawValue
        case .searchSelectedText: SearchSelectedTextAction.defaultURLTemplate
        }
    }

    private func captureActionName(_ action: CaptureAction) -> String {
        switch action {
        case .pinRegion: return "按手势范围生成贴图"
        case .copyRegion: return "按手势范围复制"
        case .saveRegion: return "按手势范围保存"
        }
    }

    private func ocrActionName(_ action: OCRAction) -> String {
        switch action {
        case .recognizeRegion: return "识别、复制并通知"
        }
    }
}
