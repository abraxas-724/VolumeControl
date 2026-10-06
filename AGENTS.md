# VolumeControl Agent 开发规范

## 项目背景

VolumeControl 是 macOS SwiftUI 状态栏音量控制工具。产品需要同时处理系统主音量、应用发现和可选的应用级音量控制。应用级音量必须经过能力探测，不能把不支持的应用伪装成可控制。

**当前进度**：P0-P2 已完成，系统音量、静音、设备切换、应用发现和状态展示全部正常。P3 原生 Process Tap 应用音量 beta 已实现，要求 macOS 14.2+；逐应用验证后启用，当前支持真实设备单输出流、1–2 通道 Float32。真实应用/设备覆盖和长时间性能仍需扩大验收，P5 正式签名发布未完成。

## 目录约定

- `Sources/VolumeControl/`：生产代码；按 Presentation、Application、Domain、Infrastructure 拆分文件。
- `Tests/VolumeControlTests/`：单元测试和仓储模拟测试。
- `scripts/`：本地构建、打包和发布辅助脚本。
- `PROJECT_PLAN.md`：产品计划和里程碑。
- `PRODUCT_TECHNICAL_SOLUTION.md`：详细技术方案和接口约定。

## 代码写作规范

- 使用 Swift 5.9+，目标 macOS 14+；需要兼容更早系统时必须在代码和文档中说明。
- 遵循 Swift API Design Guidelines；类型使用 `UpperCamelCase`，变量和函数使用 `lowerCamelCase`。
- 一个源文件聚焦一个主要职责；文件名使用主要类型名，例如 `VolumeControlModel.swift`。
- UI 使用 SwiftUI；View 只负责展示和用户输入，不直接访问 Core Audio、NSWorkspace 或 UserDefaults。
- 系统能力通过协议注入；生产实现与测试替身分离。
- 音频和通知回调不得直接修改 UI；通过 `@MainActor`、`AsyncStream` 或明确的主线程调度合并状态。
- Core Audio 的 `OSStatus` 必须转换为有上下文的错误；禁止忽略失败返回值。
- 音量统一使用 `Float`/`Double` 的 0...1 区间，进入系统 API 前后都做钳制和校验。
- 对不支持的应用返回结构化能力状态和可读原因，禁止静默吞错或显示虚假的成功状态。
- 异步任务必须可取消；避免重复注册通知、循环引用和在后台线程访问 AppKit 对象。
- 所有图标按钮必须有 VoiceOver `accessibilityLabel`；不使用纯文本替代已有 SF Symbol 图标按钮。
- 新增公共类型或复杂音频逻辑时补充简短注释，注释解释原因而不是复述代码。
- 不提交密钥、签名证书、用户路径、诊断日志和构建产物；`.build/`、`.swiftpm/`、`.DS_Store` 应保持忽略。

## 测试规范

- 业务规则、能力探针、错误映射和刷新竞态必须有单元测试。
- 测试不得修改真实系统音量、设备状态或用户偏好；使用协议替身和内存存储。
- 涉及 Core Audio 的测试分为模拟测试和真机验收，不把硬件依赖塞进普通单元测试。
- 提交前运行 `swift test`；有完整 Xcode 时再运行 Release 构建和真机验收矩阵。
- 新增 bug 先添加能复现问题的测试，再修改实现。

## 提交与阶段同步

- 提交信息使用简短祈使句，推荐格式：`feat: add device repository`、`fix: handle disconnected output`、`docs: update setup guide`。
- 每次提交只包含一个逻辑变更；不要混入无关格式化或构建产物。
- 每个计划阶段完成后必须：
  1. 运行相关测试和静态检查；
  2. 更新 `PROJECT_PLAN.md`、技术方案或 README 中的状态；
  3. 创建阶段提交和必要的 Git tag；
  4. 将该阶段代码推送到 GitHub 远程仓库，并在提交说明中记录验证结果。
- 推送前确认 `git diff --check`、`git status` 和提交内容；不要强制推送，不覆盖其他人的分支。

## GitHub 工作流

- 默认分支为 `main`，功能开发使用短生命周期分支。
- Pull Request 必须说明用户影响、技术实现、测试命令和已知限制。
- 涉及权限、系统扩展、虚拟音频设备或签名的变更必须单独列出安装、卸载和回滚步骤。
- 发布版本使用语义化版本号；每个发布 tag 关联变更说明和已知兼容性。
