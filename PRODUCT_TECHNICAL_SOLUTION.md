# VolumeControl 产品技术方案

本文档把 [TASK_PLAN.md](TASK_PLAN.md) 中的产品计划细化为可实施的产品、架构、接口、测试和发布方案。文档中的“应用级音量”始终以运行时能力探测结果为准，不把无法由系统公开接口控制的应用标记为可用。

## 1. 产品定义

### 1.1 核心价值

VolumeControl 是一个 macOS 状态栏工具。用户无需打开系统设置，就能看到当前输出设备、系统主音量和检测到音频输出的应用，并在同一个面板完成音量调整。

### 1.2 目标用户

- 需要同时处理会议、音乐、视频声音的远程办公用户。
- 需要在 IDE、浏览器、播放器之间快速切换音量的开发者和内容创作者。
- 使用耳机、显示器扬声器和蓝牙设备，并频繁切换输出设备的 macOS 用户。

### 1.3 产品边界

系统主音量使用 macOS 音频设备接口完成。应用级音量使用 macOS 14.2+ 的 Process Tap 捕获目标应用，在私有聚合设备中处理增益后重放，依赖进程归属、录制权限和当前输出设备格式的运行时验证。对于不支持的应用，界面必须显示原因，不提供看似可用但不会生效的滑杆。

## 2. 需求分析

2026-10-05 beta.3：`AppAudioPreferences.isEnabled` 按 bundle ID 保存成功启用选择，旧 JSON 缺字段默认 false。`ProcessTapVolumeController.activate` 在捕获和静音行为验证成功后持久化；`suspendAll` 仅清理会话用于退出，`deactivate/stopAll` 清除启用标记但保留音量/静音。模型在面板之外每 2 秒刷新，按 HAL `kAudioProcessPropertyIsRunningOutput` 和可验证进程归属判断播放，仅恢复已记住程序。恢复串行、不重复注册、失败至少间隔 30 秒重试，并与 BlackHole 路由互斥。手动取消/停止会取消排队任务，权限/格式/无信号失败仍为不可调节状态。

### 2.1 功能需求

| 编号 | 需求 | 验收标准 | 优先级 |
| --- | --- | --- | --- |
| FR-01 | 状态栏入口 | 应用无主窗口常驻状态栏，点击后 300ms 内显示面板 | P0 |
| FR-02 | 系统音量 | 显示并写入默认输出设备主音量，范围 0-100% | P0 |
| FR-03 | 系统静音 | 可切换静音，图标和状态实时变化，恢复静音前音量 | P0 |
| FR-04 | 输出设备 | 显示当前默认输出设备名称，设备切换后自动刷新 | P1 |
| FR-05 | 应用发现 | 列出有音频输出证据或已启用/记住的应用，显示图标、名称和唯一标识 | P1 |
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
│ AppKit NSStatusItem / NSPopover / Settings    │
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

状态栏窗口由 `MenuBarPopoverController` 管理，SwiftUI 继续绘制面板和设置内容。使用公共 `NSPopover` 锚定声音图标，按界面偏好及系统减少动态效果控制原生展开/收起动画。面板根内容始终可见，材质分别应用于独立背景层及局部控件，避免切换材质时触发根视图生命周期与显隐状态冲突。设置继续使用独立单实例窗口；AppKit 启动保留设置、退出和文本编辑快捷键。

主页面采用分区玻璃结构：独立 `PanelBackdrop` 采样窗口后方，液态模式的底层使用 underWindowBackground 磨砂；`PanelCard` 将实际音量卡片正文交给 macOS 26+ 原生 `glassEffect(.regular)` 合成，保留光学边缘、自适应文字与背景透色。卡片内按钮使用薄填充，避免玻璃套玻璃；独立控件继续使用原生玻璃。macOS 26+ 根 GlassEffectContainer 始终保留，间距为 0，切换材质不会替换根容器。窗口同步清除不透明底色；减少透明度或经典模式恢复实色，系统无障碍通知即时更新已打开窗口。背景不承接输入；实际效果以自建背景窗口的屏幕合成截图验收，不能仅靠离屏缓存或独立窗口 PNG 判定。系统玻璃偏好由原生框架响应，不读取私有偏好键，也不保存应用自己的玻璃透明度。

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

耳机自动切换由 `HeadphoneAutoSwitchPolicy` 对完整设备快照做接入边沿判断，元数据适配器读取输出终端类型、插孔连接状态和持久 UID。初始基线及手动选择保持不变，仅新接入耳机通过既有设备切换事务写入。偏好通过独立仓储注入模型；高级路由期间跳过，读取失败保留基线，清理失败中止，完整规则与验收边界见 [耳机自动切换](docs/HEADPHONE_AUTO_SWITCH.md)。

### 5.2 应用发现

`NSWorkspace.shared.runningApplications` 用于发现普通应用和图标；Core Audio 进程对象列表用于判断该进程是否真的创建了音频会话。两个来源通过 PID 和 bundle ID 合并，避免把没有音频输出的应用误显示为可控制。

模型保留完整发现结果用于音频会话协调，但界面只发布通过 `isPlayingAudio` 检测到真实输出的应用，以及已启用/记住、正在验证或已有可调节会话的应用。单独存在音频进程对象可能只是输入会话，不足以加入输出列表。本次运行按 bundle ID + PID 记住输出证据，暂停时保留，进程退出或替换后清除；该记录不写用户偏好。正常应用每 2 秒刷新，首次播放后出现，仍提供手动刷新。未记住的应用在本工具重启后需再次检测到播放。显示行不改变能力验证或触发捕获；查询失败时已知音频应用保留结构化原因，空列表也在状态栏显示检测失败原因。

### 5.3 应用级音量

公开 Core Audio 没有通用的进程增益属性，但 macOS 14.2+ Process Tap 可指定进程及输出流，捕获后应用增益并重放。当前实现不安装虚拟驱动、不切换系统默认输出，也不修改系统主音量。

`AppAudioControlling` 注入模型；`ProcessTapVolumeController` 管理每个应用的能力、独立会话、保存设置和失败回滚；`ProcessAudioSessionFactory`/`ProcessAudioSession` 隔离 HAL 实现与测试。目标由 bundle ID / PID 标识，合并精确 bundle ID 或可验证父子进程，界面按 bundle ID 去重。

原生会话先创建未静音的私有设备 scoped tap 与聚合设备，收到可验证非静音输入后设置 `mutedWhenTapped`，启用 C DSP 重放，再验证输出帧与静音属性。只有完整闭环通过才返回 `supported`。C 回调使用原子增益，支持交错/非交错无填充 Float32、1–2 通道和短增益缓变，不分配内存或访问 UI。

设置按 bundle ID 保存；静音保留原音量，写入失败恢复之前增益。健康检查发现输出、格式、进程组变化或回调停止时关闭会话，恢复原始播放；取消、退出和单应用停止走同一清理路径，清理失败可重试。最多同时 8 个应用；未知布局、无信号、权限不足和不明确进程归属显示原因。BlackHole 混合流回路独立且与应用控制互斥。

具体生命周期、验证结果、权限与当前覆盖限制见 [应用音量验证记录](docs/PROCESS_TAP_VALIDATION.md)。

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

- 没有检测到音频应用：显示“暂无音频应用”和播放提示、刷新入口；查询失败保留可读原因。
- 应用无音频会话：显示应用信息与“未检测到音频输出”。
- 应用不支持进程音量：显示原因和帮助入口。
- 输出设备断开：保留最近状态，提示“正在等待新的输出设备”。

## 7. 权限与隐私设计

- 系统主音量和普通应用发现不需要麦克风权限。
- 应用音量显式启用时由系统请求音频录制权限，打包配置 `NSAudioCaptureUsageDescription`；音频仅在内存实时处理，不保存录音、不上传。系统主音量不触发该权限。
- 不主动请求屏幕图像、辅助功能或完整磁盘访问权限；旧 BlackHole 输入实验的麦克风权限与应用音量独立。
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

当前进度：P0–P2 基础能力保留；P3 原生应用音量 beta 已实现并通过模拟和两进程真机闭环验收，逐应用能力以运行时验证为准。P4 不需要驱动即可覆盖当前已验收路径，真实应用/设备覆盖及长时间性能待扩大；P5 Developer ID 签名、公证和新机器安装验收待发布流程配置。


## 11. 2026-10-04 第一阶段实现同步

BlackHole 混合流回路已补齐两个引擎的设备绑定、PCM 复制与格式转换、限量缓冲和启动失败恢复。设备操作与引擎通过协议注入；输入权限仅在启动验证时请求，界面不再把音频会话存在误报为可调节。系统主音量仍不请求录音权限。

普通 `swift test` 隔离真实硬件及 UserDefaults；听音和端到端性能仍待验收。具体结构、测试结果、安装/卸载/回滚和技术门槛见 [第一阶段验证记录](docs/AUDIO_ROUTING_VALIDATION.md)。

该阶段识别出 Process Tap 捕获、增益与重放的可验证路径；后续已完成原生闭环，见第 12 节。DriverKit 路线仍不能基于早期伪代码视为已证明可行。

## 12. 2026-10-04 应用音量 beta 实现同步

第 5.3 节已落地 Process Tap 捕获、增益、原始播放静音与输出闭环；早期 DriverKit 草案保持研究归档。验证命令为 `swift test` 和显式 `sh scripts/verify-app-audio.sh`，普通单元测试不访问真实音频硬件或用户偏好。里程碑为 `2.0.0-beta.1`，安装/卸载/回滚及已知兼容性见 [README](README.md) 和 [验收记录](docs/PROCESS_TAP_VALIDATION.md)。

## 13. 2026-10-05 beta.2 修复

USB 耳机的麦克风流仍可能出现在聚合设备的回调中，即使使用标志读回为关闭，也不能只靠空指针判断。`ProcessTapInputPlan` 验证物理输入前缀和 tap 通道，C DSP 在启动前固定缓冲范围，完全不读麦克风缓冲。BlackHole 混合流改用 `HALAudioRoutingEngine`，以真实设备为时钟，固定输入与输出范围，默认设备切换不改变回放目的地；采样率/通道不匹配明确拒绝，错误清理保留句柄重试。

启用和路由任务由模型持有，权限提示导致面板隐藏时继续等待；显式取消、停止或退出才取消。面板与错误提示使用明确高度，系统音量刷新不会通过滑块回调反向写入。测试与本机 TencentMeeting / HyperX 验收见 [修复记录](docs/AUDIO_FIX_VALIDATION.md)。
