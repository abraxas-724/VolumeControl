# VolumeControl

VolumeControl 是一个原生 macOS 状态栏音量控制工具。它把系统输出音量、当前输出设备和运行中的应用集中到一个轻量面板中，目标是在会议、音乐、视频和开发工作之间快速调整声音。

## 项目状态

当前版本已完成 P0，并完成 P1/P2 的基础能力：

- 已有 SwiftUI `MenuBarExtra` 状态栏入口。
- 已有系统音量滑杆、硬件静音交互、真实默认输出设备名称和设置入口。
- 已有运行中应用的图标、名称和 Core Audio 音频会话能力状态展示。
- 应用级音量目前只对能力探针确认支持的会话开放；macOS 公共接口不支持的应用会明确提示原因。
- 详细产品计划见 [PROJECT_PLAN.md](PROJECT_PLAN.md)，详细技术设计见 [PRODUCT_TECHNICAL_SOLUTION.md](PRODUCT_TECHNICAL_SOLUTION.md)。

## 产品能力

### 已实现

- 状态栏常驻面板，不创建普通主窗口。
- 系统音量 0-100% 调整。
- 软静音和恢复静音前音量。
- 当前运行中普通应用的图标和名称列表。
- 不可控制应用的明确提示，而不是伪造可用滑杆。
- 设置页面：登录启动和显示百分比偏好项。

### 开发中

- 支持应用的进程级音量和静音读写。
- 可选虚拟音频设备/辅助组件，用于覆盖不暴露进程级增益的应用。
- 应用级音频写入的安全回滚和更细粒度的刷新去重。

## 技术架构

项目采用 SwiftUI + AppKit + Swift Package Manager：

```text
状态栏 UI
   ↓
ViewModel / 刷新协调器
   ↓
领域模型与 AudioRepository 协议
   ↓
Core Audio、NSWorkspace、UserDefaults
   ↓
可选音频辅助组件
```

UI 不直接调用 Core Audio。系统音量和应用音量通过仓储协议隔离，便于模拟测试和处理 macOS 不同版本的能力差异。

## 环境要求

- macOS 14 或更高版本。
- Xcode 15 或更高版本，包含完整 macOS SDK。
- Apple Silicon 优先；Intel Mac 可作为兼容性测试目标。
- Git 和 GitHub CLI（仅在需要推送仓库时需要）。

当前开发环境若只有 Command Line Tools，可能无法解析 XCTest 模块；需要安装完整 Xcode 才能运行测试、生成签名应用和完成真机验收。

## 快速开始

### 用 SwiftPM 构建和测试

```sh
swift build
swift test
```

`swift build` 用于验证生产目标；`swift test` 需要完整 Xcode 提供 XCTest SDK。

### 生成未签名应用

安装完整 Xcode 后：

```sh
sh scripts/build-app.sh
open VolumeControl.app
```

脚本会生成 `VolumeControl.app`，当前未包含 Developer ID 签名和公证，适合本地评审。

### 用 Xcode 打开

1. 打开 Xcode。
2. 选择 `File > Open`，打开项目目录中的 `Package.swift`。
3. 选择 `VolumeControl` scheme 和 `My Mac` 运行目标。
4. 运行后从系统状态栏点击扬声器图标打开面板。

## 使用教程

1. 启动应用，状态栏会出现 VolumeControl 图标。
2. 点击图标，在顶部查看当前输出设备和系统音量。
3. 拖动系统音量滑杆，音量会即时调整。
4. 点击扬声器按钮执行静音，再次点击恢复静音前音量。
5. 在“应用音量”区域查看运行中的应用。应用显示“需要音频会话支持”时，代表当前版本尚未确认该应用可进行进程级控制。
6. 点击刷新按钮重新发现应用和音频状态。
7. 点击齿轮进入设置页面，配置登录启动和音量百分比显示。

## 应用级音量的限制

macOS 公共 API 能稳定控制系统输出设备，但并没有保证所有第三方应用都提供统一的进程级音量接口。浏览器、播放器、会议软件、独占音频设备和虚拟音频设备的行为可能不同。

VolumeControl 会先探测应用音频会话和读写能力：

- 探测成功：显示可操作的应用滑杆。
- 没有音频会话：显示未检测到音频输出。
- 权限或设备不支持：显示具体原因。

项目不会静默安装驱动，也不会把不生效的控件伪装成成功。需要更高覆盖率时，会通过经过签名和公证的可选辅助组件扩展能力。

## 开发文档

- [PROJECT_PLAN.md](PROJECT_PLAN.md)：产品定位、里程碑、质量指标。
- [PRODUCT_TECHNICAL_SOLUTION.md](PRODUCT_TECHNICAL_SOLUTION.md)：需求、架构、Core Audio 方案、测试和发布流程。
- [AGENTS.md](AGENTS.md)：代码规范、测试要求和 GitHub 阶段同步规则。

## 贡献流程

1. 从 `main` 创建功能分支。
2. 按 `AGENTS.md` 的 Swift、并发、错误处理和测试规范修改代码。
3. 运行 `swift test`，并在有 Xcode 的环境运行应用验收。
4. 提交信息使用 `feat:`、`fix:`、`docs:` 等前缀。
5. 创建 Pull Request，说明用户影响、实现方式、测试命令和已知限制。

每个计划阶段完成后，必须更新文档、创建阶段提交和 tag，并将代码推送到 GitHub 仓库。

## 隐私与权限

项目不录音、不上传音频内容、不收集应用使用历史。系统音量和应用发现不需要麦克风权限；未来若启用辅助组件，会在安装前明确说明系统扩展权限、用途、卸载和回滚方法。

## 许可证

当前仓库尚未确定开源许可证。正式发布前应由项目维护者选择并添加合适的许可证文件。
