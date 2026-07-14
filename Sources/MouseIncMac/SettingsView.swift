import MouseIncCore
import SwiftUI
import AppKit

struct SettingsView: View {
    private static let standardContentWidth: CGFloat = 720

    @ObservedObject var model: SettingsViewModel
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    @ObservedObject var updateCoordinator: UpdateCoordinator
    @ObservedObject var permissionAuthorizationCoordinator: PermissionAuthorizationCoordinator
    @ObservedObject var tutorialCoordinator: TutorialCoordinator
    @State private var selectedBindingID: UUID?

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $navigation.selectedPage) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationTitle("MouseTrails")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            VStack(spacing: 0) {
                pageHeader
                Divider()
                pageContent
                saveBar
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .onAppear { selectFirstBindingIfNeeded() }
        .onChange(of: model.bindingIDs) { _ in selectFirstBindingIfNeeded() }
    }

    private var pageHeader: some View {
        HStack {
            HStack(spacing: 14) {
                Image(systemName: navigation.selectedPage.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(navigation.selectedPage.title)
                        .font(.title2.weight(.semibold))
                    Text(navigation.selectedPage.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: contentColumnWidth, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch navigation.selectedPage {
        case .general:
            Form {
                gestureSection
                tutorialSection
                updateSection
                sequenceSection
            }
            .formStyle(.grouped)
        case .bindings:
            bindingsWorkspace
        case .edgeScroll:
            Form { edgeScrollSection }
                .formStyle(.grouped)
        case .permissions:
            Form { permissionSection }
                .formStyle(.grouped)
        case .data:
            Form {
                configurationFilesSection
                validationSection
            }
            .formStyle(.grouped)
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: model.canSave ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.canSave ? Color.green : Color.red)
                    Text(model.saveMessage ?? (model.canSave ? "配置有效" : "请修复配置错误"))
                        .foregroundStyle(model.canSave ? Color.secondary : Color.red)
                    Spacer()
                    Text("Schema \(AppConfiguration.currentSchemaVersion)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Button("保存并应用") { model.save() }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canSave)
                }
                .frame(maxWidth: contentColumnWidth)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var contentColumnWidth: CGFloat {
        navigation.selectedPage == .bindings ? .infinity : Self.standardContentWidth
    }

    private var gestureSection: some View {
        Section("手势") {
            Toggle("启用鼠标与触控板手势", isOn: $model.draft.gestureOptions.enabled)
            Toggle("开机自启动 MouseTrails", isOn: launchAtLoginBinding)
            if let errorMessage = launchAtLogin.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("显示轨迹", isOn: $model.draft.gestureOptions.showsTrail)
            ColorPicker("轨迹颜色", selection: trailColorBinding, supportsOpacity: true)
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

    private var tutorialSection: some View {
        Section("使用教程") {
            LabeledContent {
                Button("查看使用教程…") {
                    tutorialCoordinator.show(
                        permissionAuthorizationCoordinator: permissionAuthorizationCoordinator
                    )
                }
            } label: {
                Label("交互式手势教学", systemImage: "graduationcap")
            }
            Text("通过真实复制粘贴、浏览、窗口、贴图与 OCR 任务重新体验默认手势。教程使用临时配置，不会覆盖你的绑定。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var updateSection: some View {
        Section("软件更新") {
            Toggle(
                "自动检查更新",
                isOn: $updateCoordinator.automaticallyChecksForUpdates
            )
            LabeledContent("当前版本", value: updateCoordinator.currentVersionString)
            HStack {
                Text(updateCoordinator.statusText)
                    .foregroundStyle(.secondary)
                Spacer()
                if updateCoordinator.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("检查更新…") {
                    updateCoordinator.checkForUpdates(manual: true)
                }
                .disabled(updateCoordinator.isBusy)
            }
            Text("每 24 小时最多自动检查一次。新版本来自公开 GitHub Releases，下载后由 macOS 打开 DMG，不会静默替换应用。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var trailColorBinding: Binding<Color> {
        Binding(
            get: {
                let color = model.draft.gestureOptions.trailColor
                return Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
            },
            set: { color in
                guard let sRGB = NSColor(color).usingColorSpace(.sRGB) else { return }
                model.draft.gestureOptions.trailColor = GestureTrailColor(
                    red: sRGB.redComponent,
                    green: sRGB.greenComponent,
                    blue: sRGB.blueComponent,
                    alpha: sRGB.alphaComponent
                )
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private var edgeScrollSection: some View {
        Section("边缘滚轮") {
            Toggle("启用左亮度、右音量", isOn: $model.draft.edgeScrollOptions.enabled)
            numberField("边缘宽度（点）", value: $model.draft.edgeScrollOptions.inset)
            numberField("每次调节比例", value: $model.draft.edgeScrollOptions.step)
            numberField("冷却时间（秒）", value: $model.draft.edgeScrollOptions.cooldown)
            Text("左边缘滚动调亮度，右边缘滚动调系统输出音量；上、下边缘不处理。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bindingsWorkspace: some View {
        GeometryReader { geometry in
            if geometry.size.width < 760 {
                VStack(spacing: 0) {
                    compactBindingSelector
                    Divider()
                    bindingDetailPane
                }
            } else {
                HSplitView {
                    bindingListPane
                        .frame(minWidth: 240, idealWidth: 270, maxWidth: 320)
                    bindingDetailPane
                }
            }
        }
    }

    private var compactBindingSelector: some View {
        HStack(spacing: 10) {
            if let index = selectedBindingIndex, let binding = model.binding(at: index) {
                GesturePreview(
                    identifier: binding.gesture,
                    samplePoints: model.previewPoints(for: binding.gesture)
                )
                    .frame(width: 46, height: 34)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
            }

            Picker("当前绑定", selection: $selectedBindingID) {
                ForEach(model.orderedBindingIDs, id: \.self) { id in
                    if let index = model.bindingIndex(for: id) {
                        Text(model.binding(at: index)?.name ?? "未命名手势")
                            .tag(Optional(id))
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Text("\(model.draft.bindings.count) 个")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                model.addBinding()
                selectedBindingID = model.bindingIDs.last
            } label: {
                Image(systemName: "plus")
            }
            .help("添加手势绑定")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var bindingListPane: some View {
        VStack(spacing: 0) {
            List(selection: $selectedBindingID) {
                ForEach(model.orderedBindingIDs, id: \.self) { id in
                    if let index = model.bindingIndex(for: id) {
                        bindingListRow(at: index)
                            .tag(id)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Button {
                    model.addBinding()
                    selectedBindingID = model.bindingIDs.last
                } label: {
                    Label("添加", systemImage: "plus")
                }
                Spacer()
                Text("\(model.draft.bindings.count) 个绑定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var bindingDetailPane: some View {
        if let index = selectedBindingIndex {
            ScrollView {
                bindingEditor(at: index)
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "scribble.variable")
                    .font(.system(size: 42))
                    .foregroundStyle(.tertiary)
                Text("选择一个手势绑定")
                    .font(.title3.weight(.medium))
                Text("从列表中选择绑定，或添加一个新的手势。")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func bindingListRow(at index: Int) -> some View {
        if let binding = model.binding(at: index) {
            HStack(spacing: 10) {
                GesturePreview(
                    identifier: binding.gesture,
                    samplePoints: model.previewPoints(for: binding.gesture)
                )
                    .frame(width: 54, height: 42)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(binding.name.isEmpty ? "未命名手势" : binding.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(displayName(for: binding.gesture))
                        Text("·")
                        Text(binding.bundleIdentifiers.isEmpty ? "全局" : "指定应用")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.issues(for: index).contains(where: { $0.severity == .error }) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func bindingEditor(at index: Int) -> some View {
        if let binding = model.binding(at: index) {
          VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                GesturePreview(
                    identifier: binding.gesture,
                    samplePoints: model.previewPoints(for: binding.gesture)
                )
                    .frame(width: 112, height: 82)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 8) {
                    TextField("手势名称", text: bindingText(at: index, keyPath: \.name))
                        .font(.title3.weight(.semibold))
                    Text("\(displayName(for: binding.gesture)) · \(binding.bundleIdentifiers.isEmpty ? "全局生效" : "仅指定应用")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) { removeBinding(at: index) } label: {
                    Image(systemName: "trash")
                }
                .help("删除")
            }

            GroupBox("手势") {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Text("轨迹类型")
                    .frame(width: 90, alignment: .leading)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text("内部标识")
                        .frame(width: 90, alignment: .leading)
                    TextField("手势标识", text: bindingText(at: index, keyPath: \.gesture))
                }
                Divider()
                let isRecordingTarget = model.bindingIDs.indices.contains(index)
                    && model.customGestureRecorder.targetBindingID == model.bindingIDs[index]
                HStack(spacing: 10) {
                    Button {
                        if model.customGestureRecorder.isRecording, isRecordingTarget {
                            model.customGestureRecorder.cancel()
                        } else {
                            model.startCustomGestureRecording(at: index)
                        }
                    } label: {
                        Label(
                            model.customGestureRecorder.isRecording && isRecordingTarget
                                ? "取消录制"
                                : (model.customGesture(for: binding.gesture) == nil ? "录制自定义手势" : "重新录制"),
                            systemImage: model.customGestureRecorder.isRecording && isRecordingTarget
                                ? "xmark.circle" : "record.circle"
                        )
                    }
                    .disabled(model.customGestureRecorder.isRecording && !isRecordingTarget)
                    if isRecordingTarget, let message = model.customGestureRecorder.statusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(
                                model.customGestureRecorder.isRecording ? Color.orange : Color.secondary
                            )
                    }
                }
                Text("连续按住右键绘制同一轨迹 3 次；录制期间只采集样本，不执行现有手势。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
              }
              .padding(10)
            }

            GroupBox("应用范围") {
              HStack {
                TextField("Bundle ID（留空表示全局；多个以逗号分隔）", text: bundleIDsBinding(at: index))
                Button("选择应用…") { chooseApplication(for: index) }
              }
              .padding(10)
            }

            GroupBox("执行动作") {
              VStack(alignment: .leading, spacing: 10) {
                if binding.actions.isEmpty {
                    Label("无动作", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                ForEach(binding.actions.indices, id: \.self) { actionIndex in
                  HStack(alignment: .center, spacing: 10) {
                    Text("\(actionIndex + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Picker("", selection: actionTypeBinding(binding: index, action: actionIndex)) {
                        ForEach(ActionCatalog.descriptors, id: \.kind) { descriptor in
                            Text(descriptor.displayName).tag(descriptor.kind)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    actionValueEditor(binding: index, action: actionIndex)
                    Button(role: .destructive) {
                        model.removeAction(at: actionIndex, from: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("移除动作")
                  }
                  .padding(10)
                  .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                }
                Button { model.addAction(to: index) } label: {
                    Label("添加动作", systemImage: "plus.circle")
                }
              }
              .padding(10)
            }

            ForEach(Array(model.issues(for: index).enumerated()), id: \.offset) { _, issue in
                Label(issue.message, systemImage: issue.severity == .error
                      ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
            }
          }
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
        } else if actionKind(binding: binding, action: action) == .systemViewAction {
            Picker("系统视图与空间", selection: actionValueBinding(binding: binding, action: action)) {
                ForEach(SystemViewAction.allCases, id: \.self) { value in
                    Text(systemViewActionName(value)).tag(value.rawValue)
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
        Section {
            permissionRow(.accessibility, required: true)
            permissionRow(
                .screenRecording,
                required: model.draft.requiredPermissions.contains(.screenRecording)
            )
            Text("屏幕录制权限仅用于截图、贴图与 OCR；拒绝不会影响手势和窗口动作。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            HStack {
                Text("权限")
                Spacer()
                Button("重新检测权限") {
                    permissionAuthorizationCoordinator.refresh()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .textCase(nil)
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

    @ViewBuilder
    private func permissionRow(_ permission: SystemPermission, required: Bool) -> some View {
        let state = permissionAuthorizationCoordinator.snapshot[permission]
        let row = HStack {
            Text(PermissionCoordinator.displayName(for: permission))
            Spacer()
            Text(permissionStateName(state, required: required))
                .foregroundStyle(
                    state == .granted ? Color.green : (required ? Color.red : Color.secondary)
                )
            if state != .granted {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
        if state == .granted {
            row
        } else {
            Button {
                permissionAuthorizationCoordinator.beginAuthorization(for: permission)
            } label: {
                row
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func permissionStateName(_ state: PermissionState, required: Bool) -> String {
        if !required, state != .granted { return "未授权（可选）" }
        switch state {
        case .granted: return "已授权"
        case .denied: return "未授权"
        case .notDetermined: return "未请求"
        case .unavailable: return "不可用"
        }
    }

    private var selectedBindingIndex: Int? {
        guard let selectedBindingID else { return nil }
        return model.bindingIDs.firstIndex(of: selectedBindingID)
    }

    private func selectFirstBindingIfNeeded() {
        if let selectedBindingID, model.bindingIDs.contains(selectedBindingID) {
            return
        }
        selectedBindingID = model.orderedBindingIDs.first
    }

    private func removeBinding(at index: Int) {
        let nextID: UUID? = {
            if model.bindingIDs.indices.contains(index + 1) { return model.bindingIDs[index + 1] }
            if index > 0, model.bindingIDs.indices.contains(index - 1) { return model.bindingIDs[index - 1] }
            return nil
        }()
        model.removeBinding(at: index)
        selectedBindingID = nextID
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
                model.setActionValue(
                    value,
                    actionIndex: action,
                    bindingIndex: binding
                )
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
                model.setActionType(
                    kind,
                    value: defaultValue(for: kind),
                    actionIndex: action,
                    bindingIndex: binding
                )
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
        panel.title = "导出 MouseTrails 配置"
        panel.nameFieldStringValue = "MouseTrails-config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(to: url)
    }

    private func restoreConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "选择 MouseTrails 配置备份"
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
        case .fill: return "填充桌面（非全屏）"
        case .restorePreviousSize: return "恢复布局前大小"
        case .tileLeft: return "左半屏"
        case .tileRight: return "右半屏"
        case .tileTop: return "上半屏"
        case .tileBottom: return "下半屏"
        case .tileTopLeft: return "左上四分之一"
        case .tileTopRight: return "右上四分之一"
        case .tileBottomLeft: return "左下四分之一"
        case .tileBottomRight: return "右下四分之一"
        case .minimize: return "最小化窗口"
        case .close: return "关闭窗口"
        case .closeAll: return "关闭所有类似窗口"
        case .quitApplication: return "退出当前应用"
        }
    }

    private func systemViewActionName(_ action: SystemViewAction) -> String {
        switch action {
        case .missionControl: return "打开调度中心"
        case .appExpose: return "显示当前 App 的所有窗口"
        case .showDesktop: return "显示桌面"
        case .previousSpace: return "上一个空间"
        case .nextSpace: return "下一个空间"
        case .launchpad: return "打开应用视图（Launchpad）"
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
            ("LETTER_W", "字母 W")
        ]
    }

    private var polylineGestureChoices: [(String, String)] {
        [
            ("UP-LEFT", "上 → 左"),
            ("DOWN-RIGHT", "下 → 右"),
            ("UP-RIGHT", "上 → 右"),
            ("DOWN-LEFT", "下 → 左"),
            ("LEFT-UP", "左 → 上"),
            ("LEFT-DOWN", "左 → 下"),
            ("RIGHT-UP", "右 → 上"),
            ("RIGHT-DOWN", "右 → 下")
        ]
    }

    private func displayName(for identifier: String) -> String {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "无"
        }
        if let customName = model.displayName(forCustomGesture: identifier) {
            return customName
        }
        return (cardinalGestureChoices + templateGestureChoices + polylineGestureChoices)
            .first { $0.0 == identifier }?.1 ?? identifier
    }

    private func defaultValue(for kind: ActionDefinition.Kind) -> String {
        switch kind {
        case .keyStroke: "Command+C"
        case .openURL: "https://"
        case .launchApplication: "com.apple.finder"
        case .delay: "0.2"
        case .windowAction: WindowAction.center.rawValue
        case .systemViewAction: SystemViewAction.missionControl.rawValue
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

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selectedPage: SettingsPage = .general
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case bindings
    case edgeScroll
    case permissions
    case data

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "通用"
        case .bindings: return "手势绑定"
        case .edgeScroll: return "边缘滚动"
        case .permissions: return "权限"
        case .data: return "配置"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "手势识别、轨迹外观、动作序列和软件更新"
        case .bindings: return "管理轨迹、应用范围和执行动作"
        case .edgeScroll: return "左侧亮度与右侧音量控制"
        case .permissions: return "查看辅助功能和屏幕录制状态"
        case .data: return "导出、恢复并检查当前配置"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .bindings: return "scribble.variable"
        case .edgeScroll: return "arrow.up.and.down.and.arrow.left.and.right"
        case .permissions: return "lock.shield"
        case .data: return "externaldrive"
        }
    }
}
