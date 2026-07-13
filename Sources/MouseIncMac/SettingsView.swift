import MouseIncCore
import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel
    @State private var selectedPage: SettingsPage = .general
    @State private var selectedBindingID: UUID?

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selectedPage) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .listStyle(.sidebar)
            .navigationTitle("MouseIncMac")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            VStack(spacing: 0) {
                pageHeader
                Divider()
                pageContent
                saveBar
            }
        }
        .frame(minWidth: 920, minHeight: 680)
        .onAppear { selectFirstBindingIfNeeded() }
        .onChange(of: model.bindingIDs) { _ in selectFirstBindingIfNeeded() }
    }

    private var pageHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: selectedPage.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedPage.title)
                    .font(.title2.weight(.semibold))
                Text(selectedPage.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .general:
            Form {
                gestureSection
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
        case .pinnedImage:
            Form {
                pinnedImageHelpSection
                ocrHelpSection
            }
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
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private var gestureSection: some View {
        Section("手势") {
            Toggle("启用鼠标与触控板手势", isOn: $model.draft.gestureOptions.enabled)
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

    private var bindingsWorkspace: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedBindingID) {
                    ForEach(Array(model.bindingIDs.enumerated()), id: \.element) { index, id in
                        bindingListRow(at: index)
                            .tag(id)
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
            .frame(minWidth: 240, idealWidth: 270, maxWidth: 320)

            if let index = selectedBindingIndex {
                ScrollView {
                    bindingEditor(at: index)
                        .padding(24)
                        .frame(maxWidth: 760, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 42))
                        .foregroundStyle(.tertiary)
                    Text("选择一个手势绑定")
                        .font(.title3.weight(.medium))
                    Text("从左侧选择绑定，或添加一个新的手势。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func bindingListRow(at index: Int) -> some View {
        if let binding = model.binding(at: index) {
            HStack(spacing: 10) {
                GesturePreview(identifier: binding.gesture)
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
                GesturePreview(identifier: binding.gesture)
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
                Button { model.moveBinding(from: index, by: -1) } label: {
                    Image(systemName: "arrow.up")
                }
                .help("上移")
                .disabled(index == 0)
                Button { model.moveBinding(from: index, by: 1) } label: {
                    Image(systemName: "arrow.down")
                }
                .help("下移")
                .disabled(index == model.draft.bindings.count - 1)
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

    private var ocrHelpSection: some View {
        Section("离线 OCR") {
            Label("根据手势轨迹的包围范围直接截图识别", systemImage: "viewfinder")
            Label("识别结果自动复制到剪贴板", systemImage: "doc.on.clipboard")
            Label("完成后通过系统通知显示文本摘要", systemImage: "bell")
            Text("OCR 使用 macOS 本地视觉识别，不上传截图或文字。")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var selectedBindingIndex: Int? {
        guard let selectedBindingID else { return nil }
        return model.bindingIDs.firstIndex(of: selectedBindingID)
    }

    private func selectFirstBindingIfNeeded() {
        if let selectedBindingID, model.bindingIDs.contains(selectedBindingID) {
            return
        }
        selectedBindingID = model.bindingIDs.first
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

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case bindings
    case edgeScroll
    case pinnedImage
    case permissions
    case data

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return "通用"
        case .bindings: return "手势绑定"
        case .edgeScroll: return "边缘滚动"
        case .permissions: return "权限"
        case .pinnedImage: return "贴图与 OCR"
        case .data: return "配置"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "手势识别、轨迹外观和动作序列"
        case .bindings: return "管理轨迹、应用范围和执行动作"
        case .edgeScroll: return "左侧亮度与右侧音量控制"
        case .permissions: return "查看辅助功能、屏幕录制和输入监控状态"
        case .pinnedImage: return "贴图交互与离线文字识别说明"
        case .data: return "导出、恢复并检查当前配置"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .bindings: return "scribble.variable"
        case .edgeScroll: return "arrow.up.and.down.and.arrow.left.and.right"
        case .permissions: return "lock.shield"
        case .pinnedImage: return "pin"
        case .data: return "externaldrive"
        }
    }
}
