# MouseInc macOS 移植规格

> 本文档定义功能与技术边界；具体开发顺序、双轨分工和验收门槛见 [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)。

## 1. 目标

在不复用 Win32 二进制的前提下，原生重现 MouseInc 的主要交互和可配置动作系统。优先保证手势输入可靠、不会吞掉普通右键，并尽量兼容现有 `MouseInc.json` 的概念与命名。

支持基线：macOS 13 及以上，Apple Silicon 优先；界面使用 AppKit，后续设置页可使用 SwiftUI。

## 2. 功能映射

| Windows 功能 | macOS 实现 | 权限 | 阶段 | 风险 |
|---|---|---|---|---|
| 全局右键手势 | 主动 HID `CGEventTap` + 原始拖动事件 | 辅助功能 | P0 | 高：事件吞吐和右键回放 |
| 触控板兼容手势 | 复用同一组右键事件，不区分设备 | 辅助功能 | P1 | 中：辅助点击必须能持续按住 |
| macOS 原生触控板手势 | 不拦截滚动、缩放、旋转和系统多指手势 | 无 | P1 | 低：保持系统原行为 |
| 手势轨迹浮层 | 透明 `NSPanel` + `NSBezierPath` | 无 | P0 | 中：多显示器坐标 |
| 发送快捷键 | `CGEvent` 键盘事件 | 辅助功能 | P0 | 中：输入法和受保护应用 |
| 按应用规则 | `NSRunningApplication.bundleIdentifier` | 无 | P0 | 低 |
| 菜单栏与暂停 | `NSStatusItem` | 无 | P0 | 低 |
| JSON 配置 | 版本化 `Codable` 模型，存储于 Application Support | 无 | P0 | 低：迁移与向前兼容 |
| Alt/Option 拖动窗口 | `CGEventTap` + Accessibility | 辅助功能 | P2A | 高：跨进程窗口控制 |
| 边缘滚轮和热角 | 全局滚轮/移动事件 + 屏幕几何 | 辅助功能 | P2A | 中：多屏边界 |
| 窗口最大化/居中/置顶/关闭 | `AXUIElement`，部分动作需应用快捷键兜底 | 辅助功能 | P2A | 高：应用实现差异 |
| 剪贴板增强 | `NSPasteboard` + 双击快捷键状态机 | 辅助功能 | P2A | 中：敏感数据与变化监听 |
| 精确框选截图 | ScreenCaptureKit | 屏幕录制 | P2B | 中 |
| 贴图 | 无边框置顶窗口 | 屏幕录制 | P2B | 中 |
| 画中画 | ScreenCaptureKit 持续捕获 | 屏幕录制 | P2B | 高：性能和最小化行为 |
| OCR | Vision `VNRecognizeTextRequest` | 屏幕录制 | P2B | 低；可完全离线 |
| 高质量窗口截图 | ScreenCaptureKit | 屏幕录制 | P2B | 中：阴影和透明背景 |
| 按键回显 | `CGEventTap` + 浮层 | 输入监控/辅助功能 | P2B | 中：密码输入保护 |
| SwiftUI 设置页 | 配置编辑、手势映射与权限诊断 | 无 | P2B | 中：与配置 schema 同步 |
| 音量/静音 | CoreAudio 或系统快捷键事件 | 辅助功能 | P2A | 中 |
| 屏幕亮度 | 显示器私有/受限 API，外接屏需 DDC | 可能额外授权 | P3 | 高 |
| 启动应用/URL | `NSWorkspace` | 无 | P2A | 低 |
| 二维码与哈希 | CoreImage/CryptoKit | 无 | P2B | 低 |
| 开机启动 | `SMAppService` | 用户确认 | P3 | 低 |

## 3. P0：工程与核心基线

### 3.1 工程基线

- 以 Swift Package 分离 `MouseIncCore` 与 macOS 应用层，核心模型不依赖 AppKit。
- 保留 `MouseIncCoreCheck` 作为快速烟雾检查，同时用 XCTest 覆盖识别器、规则优先级、配置读写与迁移。
- 调试、Release 和 `.app` 打包均必须可重复构建；手势核心变更先通过自动回归。
- 配置带明确 schema 版本，旧结构在读取时迁移，不支持的未来版本明确报错。

### 3.2 输入状态机

1. 在 `kCGHIDEventTap` 处截获右键按下，记录起点、前台应用和时间。
2. 使用同一 HID 钩子的 `rightMouseDragged` 原始事件，并累计 `mouseEventDeltaX/Y` 生成轨迹；不能依赖被拦截按键后的全局光标位置。移动超过 `startDistance` 后进入手势模式并显示轨迹。
3. 右键松开时识别方向序列，在该应用的绑定中查找动作。
4. 成功匹配则执行动作；移动不足时回放一次正常右键点击。已经进入手势但未识别或未绑定时不回放，以免意外弹出上下文菜单。
5. 普通右键在 `kCGSessionEventTap` 层回放，位于自身 HID 钩子下游，避免再次捕获。

这条“不丢普通右键”路径是 P0 的验收重点。

### 3.3 识别器

- 输入为全局坐标点列。
- 先按容差做 Ramer–Douglas–Peucker 简化，再把线段量化为上下左右。
- 合并连续相同方向，输出 `UP`、`DOWN-RIGHT` 等稳定标识。
- P0 支持直线和折线；八方向、曲线模板和可训练自定义手势纳入 P2A。

### 3.4 版本化配置模型

```json
{
  "schemaVersion": 2,
  "gestureOptions": {
    "enabled": true,
    "startDistance": 12,
    "simplificationTolerance": 18,
    "minimumGestureLength": 40,
    "maximumDuration": 5,
    "showsTrail": true,
    "reportsFailures": true
  },
  "bindings": [
    {
      "gesture": "UP",
      "name": "复制",
      "bundleIdentifiers": [],
      "actions": [{ "type": "keyStroke", "value": "Command+C" }]
    }
  ]
}
```

`bundleIdentifiers` 为空表示全局规则；非空时优先匹配特定应用。当前 schema 为 v2：无 `schemaVersion` 的旧平铺配置按 v1 读取，下次保存时写回 v2；高于当前版本的配置不做猜测解析。后续兼容层再负责把 Windows 进程名和 `SendKeys` 动作转换到此模型。

## 4. P1：触控板兼容

P1 不引入独立的“触控板模式”，也不判断事件来自鼠标还是触控板。两种设备同时生效，共用 P0 的状态机、识别器、绑定和动作执行链路。

### 4.1 操作模型

- 鼠标：右键按住 → 拖动绘制 → 松开识别。
- 触控板：辅助点击（右键）并按住 → 拖动绘制 → 松开识别。
- 短点击未达到手势阈值时，仍回放为普通右键，上下文菜单不受影响。
- 轻触式辅助右键不能维持按下状态，因此不能用来持续绘制轨迹；这是操作形式的边界，不通过设备推断规避。

菜单栏需明确展示上述用法，并提供“打开触控板设置…”入口，便于用户选择能持续按住的辅助点击方式。

### 4.2 原生行为边界

- 只处理 `rightMouseDown`、`rightMouseDragged` 和 `rightMouseUp`。
- 不监听或拦截双指滚动、捏合缩放、旋转、Mission Control、桌面切换及其他系统三/四指手势。
- 不使用私有 `MultitouchSupport`、IOKit SPI、原始触点读取或虚拟 HID 驱动。
- P0/P1 只需辅助功能权限，不新增输入监控或屏幕录制权限。

### 4.3 验收

- 鼠标与内建触控板/Magic Trackpad 无需切换即可交替使用同一组默认手势。
- 两种输入的短右键、成功手势、超时和识别失败路径都有一致、可预测的结果。
- 触控板原生滚动、缩放和系统多指手势不因 MouseIncMac 启用而变化。
- 菜单栏文案、系统设置入口、权限状态和监听状态可正常使用。

## 5. P2：双轨并行开发

P0/P1 的配置模型、手势识别和动作接口是两条轨道的共享边界。P2A 与 P2B 同时推进；涉及共享 schema 或接口的改动必须带迁移与回归测试。

### 5.1 P2A：输入与效率

- 八方向、曲线模板与可训练手势。
- 快捷键、延时、URL、应用启动、剪贴板和窗口动作组成的动作序列。
- 窗口最大化/居中/关闭/置顶、Option 拖动、边缘滚轮、热角和音量。
- 剪贴板菜单、连续复制与快速粘贴。

### 5.2 P2B：视觉与设置

- SwiftUI 设置页、手势编辑器、配置导入和权限诊断。
- ScreenCaptureKit 框选截图、窗口截图、贴图与画中画。
- Vision 离线 OCR、二维码与哈希工具。
- 多显示器、Retina 缩放、色彩空间和捕获权限回归。

### 5.3 P3：完善与分发

- 登录启动、自动更新、Developer ID 签名与公证。
- Intel 构建、通用二进制与发布回归矩阵。

## 6. 隐私与安全原则

- 默认离线，不上传剪贴板、截图或按键数据。
- OCR 使用系统 Vision，不复刻 Windows 版的外部 HTTP OCR。
- 按键回显遇到安全输入模式必须停止记录。
- URL、脚本和应用启动动作在设置界面明确展示；导入旧配置时不自动执行。
- 权限按需申请：P0/P1 只申请辅助功能；加入按键回显时再申请输入监控，加入截图时再申请屏幕录制。

## 7. 已知技术风险

- macOS 权限记录与应用签名身份绑定，开发期间每次改变包身份可能需要重新授权。
- `CGEventTap` 超时会被系统停用，必须监听禁用事件并立即恢复。
- 回放右键需要保留位置、按键及事件标记；拖动距离不足时尤其容易出现上下文菜单异常。
- 不同触控板和系统“辅助点击”设置产生的按住体验可能不同，需使用内建触控板和 Magic Trackpad 真机验证。
- Accessibility 对 Electron、自绘窗口和系统受保护界面的支持不一致。
- 屏幕坐标同时存在 Quartz 顶部原点和 AppKit 底部原点，多显示器不能只用主屏高度硬转换。
