# VolumeControl 产品技术方案

本文档把 [PROJECT_PLAN.md](PROJECT_PLAN.md) 中的产品计划细化为可实施的产品、架构、接口、测试和发布方案。文档中的“应用级音量”始终以运行时能力探测结果为准，不把无法由系统公开接口控制的应用标记为可用。

## 1. 产品定义

### 1.1 核心价值

VolumeControl 是一个 macOS 状态栏工具。用户无需打开系统设置，就能看到当前输出设备、系统主音量和正在运行的应用，并在同一个面板完成音量调整。

### 1.2 目标用户

- 需要同时处理会议、音乐、视频声音的远程办公用户。
- 需要在 IDE、浏览器、播放器之间快速切换音量的开发者和内容创作者。
- 使用耳机、显示器扬声器和蓝牙设备，并频繁切换输出设备的 macOS 用户。

### 1.3 产品边界

系统主音量使用 macOS 音频设备接口完成。应用级音量依赖应用是否暴露可控制的音频会话和当前输出设备是否支持进程级增益。对于不支持的应用，界面必须显示原因，不提供看似可用但不会生效的滑杆。

## 2. 需求分析

### 2.1 功能需求

| 编号 | 需求 | 验收标准 | 优先级 |
| --- | --- | --- | --- |
| FR-01 | 状态栏入口 | 应用无主窗口常驻状态栏，点击后 300ms 内显示面板 | P0 |
| FR-02 | 系统音量 | 显示并写入默认输出设备主音量，范围 0-100% | P0 |
| FR-03 | 系统静音 | 可切换静音，图标和状态实时变化，恢复静音前音量 | P0 |
| FR-04 | 输出设备 | 显示当前默认输出设备名称，设备切换后自动刷新 | P1 |
| FR-05 | 应用发现 | 列出运行中的普通应用，显示图标、名称和唯一标识 | P1 |
| FR-06 | 能力状态 | 每个应用显示可调节、权限不足、无音频会话或不支持等状态 | P1 |
| FR-07 | 应用音量 | 在能力探针确认支持时读写应用增益和静音状态 | P2 |
| FR-08 | 设置 | 支持登录启动、是否显示百分比和诊断日志开关 | P1 |
| FR-09 | 错误恢复 | 音频设备断开、应用退出或写入失败时不崩溃，显示可读错误 | P1 |
| FR-10 | 可访问性 | 所有图标按钮有 VoiceOver 标签，键盘可聚焦滑杆和操作按钮 | P1 |

### 2.2 非功能需求

- **性能**：面板打开后优先显示缓存状态，首次音频探测在 300ms 内完成；拖动音量时 UI 不阻塞。
- **稳定性**：设备切换、睡眠唤醒、应用频繁启动退出不会导致崩溃、音量振荡或重复订阅。
- **兼容性**：目标 macOS 14+，Apple Silicon 优先；Intel 作为兼容性测试目标。
- **隐私**：不录音、不上传音频内容、不收集应用使用历史；诊断日志默认关闭且不包含文件内容。
- **安全**：不绕过 TCC，不静默安装音频驱动；辅助组件必须签名、公证、可卸载。
- **可维护性**：UI 不直接调用 Core Audio，领域层可在 CI 上做纯逻辑测试。

## 3. 整体架构

采用单体菜单栏应用加可选音频辅助组件的结构。主应用保持无特权运行，音频能力通过适配器隔离。

```text
┌──────────────────────────────────────────────┐
│ SwiftUI MenuBarExtra / Settings              │
│  VolumePanel  AppVolumeRow  SettingsView     │
└──────────────────────┬───────────────────────┘
                       │ ViewModel / Actions
┌──────────────────────▼───────────────────────┐
│ Application Layer                             │
│ VolumeControlModel  RefreshCoordinator        │
│ PreferencesStore     CapabilityResolver       │
└──────────────────────┬───────────────────────┘
                       │ Protocols
┌──────────────────────▼───────────────────────┐
│ Domain Layer                                  │
│ AudioDevice  AppAudioSession  VolumeState     │
│ AudioCapability  AudioError                   │
└──────────────────────┬───────────────────────┘
                       │ Implementations
┌──────────────────────▼───────────────────────┐
│ Infrastructure                               │
│ CoreAudioDeviceRepository                     │
│ CoreAudioProcessRepository                    │
│ WorkspaceApplicationRepository                │
│ UserDefaultsPreferencesStore                  │
└──────────────────────┬───────────────────────┘
                       │ optional
              Audio helper / virtual device
```

### 3.1 模块职责

- **Presentation**：只负责布局、输入绑定、格式化和可访问性；不保存音频设备句柄。
- **Application**：协调刷新、写入、错误映射和 UI 状态；保证所有发布到 UI 的变化在主线程。
- **Domain**：定义值类型、能力状态和业务规则，例如音量范围、静音恢复值和排序规则。
- **Infrastructure**：包装 Core Audio、NSWorkspace、UserDefaults 和可选辅助组件。
- **Helper**：只有在公共 Core Audio 不能完成进程级增益时才启用；与主应用通过 XPC 或本地受限 IPC 通讯。

## 4. 核心数据模型与接口

### 4.1 领域模型

```swift
struct AudioDevice: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let isDefaultOutput: Bool
}

struct AppAudioSession: Identifiable, Equatable {
    let id: String              // bundle id + process id
    let bundleID: String
    let processID: Int32
    let name: String
    let icon: NSImage
    var volume: Float?
    var isMuted: Bool?
    var capability: AudioCapability
}

enum AudioCapability: Equatable {
    case supported
    case noAudioSession
    case permissionRequired
    case unsupported(reason: String)
}
```

### 4.2 仓储协议

```swift
protocol AudioDeviceRepository {
    func defaultOutputDevice() async throws -> AudioDevice
    func readMasterVolume(deviceID: UInt32) async throws -> Float
    func writeMasterVolume(_ value: Float, deviceID: UInt32) async throws
    func readMasterMute(deviceID: UInt32) async throws -> Bool
    func writeMasterMute(_ muted: Bool, deviceID: UInt32) async throws
    var changes: AsyncStream<AudioChange> { get }
}

protocol AppAudioRepository {
    func sessions(deviceID: UInt32) async throws -> [AppAudioSession]
    func setVolume(_ value: Float, for sessionID: String) async throws
    func setMuted(_ muted: Bool, for sessionID: String) async throws
}
```

实际实现中使用 `AudioObjectPropertyAddress` 读取默认输出设备、设备名称、输出音量和静音属性。所有 Core Audio 状态码转换为 `AudioError`，不把非零 OSStatus 当作成功。

## 5. 音频能力实现方案

### 5.1 系统主音量

1. 读取 `kAudioHardwarePropertyDefaultOutputDevice` 获取默认输出设备 ID。
2. 使用设备属性地址读取输出通道的主音量和静音状态。
3. 写入前把输入限制在 `[0, 1]`，写入失败保留旧值并向 ViewModel 返回错误。
4. 注册设备属性监听器，收到设备、音量、静音变化后通过 `AsyncStream` 合并更新。

### 5.2 应用发现

`NSWorkspace.shared.runningApplications` 用于发现普通应用和图标；Core Audio 进程对象列表用于判断该进程是否真的创建了音频会话。两个来源通过 PID 和 bundle ID 合并，避免把没有音频输出的应用误显示为可控制。

### 5.3 应用级音量

能力探针按以下顺序执行：

1. 查询当前输出设备是否暴露进程对象列表。
2. 按 PID/bundle ID 查找进程音频对象。
3. 检查音量、静音属性是否存在且可读写。
4. 读取一次当前值并执行可回滚的无变化写入，确认读写闭环。
5. 成功则标记 `supported`；否则返回明确的 `AudioCapability`。

macOS 并没有保证所有第三方应用都提供统一的公开进程音量接口。无法通过探针控制时，产品不伪造滑杆效果。后续若需要覆盖更多应用，新增签名的虚拟音频设备或辅助组件，且保持 `AppAudioRepository` 接口不变。

### 5.4 可选辅助组件

- 独立进程负责虚拟设备或系统扩展，主应用只处理 UI 和策略。
- 使用 XPC 定义最小命令集：列举会话、读写增益、订阅变化、健康检查。
- 安装、升级和卸载必须有明确用户操作；组件崩溃时主应用回退到系统音量能力。
- 发布前单独验证 Developer ID 签名、公证、系统扩展批准和恢复路径。

## 6. 状态管理与交互流程

### 6.1 刷新流程

```text
打开面板 / 设备通知 / 应用启动退出
             │
             ▼
      RefreshCoordinator 去重
             │
             ▼
  读取设备 -> 读取主音量 -> 发现应用 -> 能力探针
             │
             ▼
       MainActor 发布 ViewState
```

刷新任务必须可取消；同一设备在短时间内的多次通知合并为一次刷新。应用退出后写入操作返回 `sessionUnavailable`，UI 移除该行并保留诊断记录。

### 6.2 写入流程

拖动滑杆时采用节流写入（建议 30-60Hz 上限），结束拖动后执行一次最终写入。写入失败显示非阻塞错误提示，并通过重新读取确认系统真实值，避免 UI 与硬件状态分离。

### 6.3 空状态与错误状态

- 没有普通应用：显示“暂无运行中的应用”和刷新入口。
- 应用无音频会话：显示应用信息与“未检测到音频输出”。
- 应用不支持进程音量：显示原因和帮助入口。
- 输出设备断开：保留最近状态，提示“正在等待新的输出设备”。

## 7. 权限与隐私设计

- 系统主音量和普通应用发现不需要麦克风权限。
- 不请求屏幕录制、辅助功能或完整磁盘访问权限。
- 若辅助组件需要系统扩展批准，首次启用时解释用途、权限范围和卸载方式。
- 日志使用 OSLog，默认只记录错误码、设备 ID 和能力状态，不记录音频内容。
- 诊断导出由用户主动触发，导出前显示包含的字段。

## 8. 测试方案

### 8.1 单元测试

- 音量钳制、静音恢复值和排序规则。
- Core Audio `OSStatus` 到领域错误的映射。
- 能力探针每种失败原因的状态转换。
- 刷新去重、取消和应用退出竞态。

### 8.2 集成测试

- 模拟音频设备仓储验证 ViewModel 不直接依赖 Core Audio。
- 模拟设备切换、应用启动/退出和写入失败。
- XPC 辅助组件协议的版本兼容和超时恢复。

### 8.3 真机验收矩阵

| 场景 | 设备/应用 | 结果 |
| --- | --- | --- |
| 内建扬声器 | macOS 默认输出 | 系统音量读写闭环 |
| 有线耳机 | 插拔切换 | 面板设备名和音量刷新 |
| 蓝牙耳机 | 连接、断开、睡眠唤醒 | 无崩溃，状态最终一致 |
| 浏览器/播放器/会议应用 | 有音频输出 | 正确显示能力状态 |
| 独占音频应用 | 独占设备 | 明确显示不可控制原因 |

## 9. 发布与运维

1. Xcode Release 构建，启用 Hardened Runtime。
2. Developer ID Application 签名；如有辅助组件，分别签名并配置嵌套代码。
3. `notarytool` 公证，`stapler` 装订票据。
4. 生成 DMG 或 ZIP，提供卸载说明和版本变更记录。
5. 每个里程碑创建 Git tag，并在 GitHub Actions 中执行格式检查、单元测试和构建验证。

## 10. 交付阶段与退出条件

| 阶段 | 主要任务 | 退出条件 |
| --- | --- | --- |
| P0 | SwiftPM、领域模型、状态栏壳 | 可启动，纯逻辑测试通过 |
| P1 | 系统设备与主音量 | 内建扬声器和耳机读写闭环 |
| P2 | 应用发现与图标 | 启动/退出最终一致，空状态完整 |
| P3 | 进程级能力探针与写入 | 支持项目读写闭环，不支持项目有原因 |
| P4 | 辅助组件评估 | 能力覆盖率和权限成本经过评审 |
| P5 | 签名、公证、发布 | 新机器可安装、升级、卸载和回滚 |
