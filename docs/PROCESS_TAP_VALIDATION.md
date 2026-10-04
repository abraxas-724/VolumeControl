# 应用级音量控制：2.0.0-beta.1

日期：2026-10-04。状态：Process Tap 真实捕获、独立增益、静音、界面模型和设置恢复已实现；扩大应用/设备覆盖、长时间性能及正式签名发布待完成。

## 实现

公开 Process Tap API 可指定进程音频，并控制捕获期间的原始播放行为。本阶段用该路径代替早期计划中的 DriverKit 虚拟设备假设。最低系统为 macOS 14.2；macOS 14.0/14.1 只保留系统音量能力。

每个应用使用独立的私有 tap 和聚合设备，把 tap 输入与真实输出放在同一 HAL IOProc/时钟上。设备 scoped tap 的格式必须与输出流一致；聚合输入/输出通道也必须能安全映射。实时增益由 C11 原子状态传入 C DSP 回调，支持交错/非交错 Float32、增益缓变、数值校验和静音；回调不分配内存、不持有锁、不访问 SwiftUI 或 AppKit。

启动时保持原始播放且不重放。收到非静音输入信号后才设置 `mutedWhenTapped`，启用增益输出，并确认输出帧与系统的原始播放静音状态，随后发布 supported。静音保存用户音量，取消静音恢复该值；写入设置失败会回滚实际增益与 UI 状态。

应用/辅助进程按精确 bundle ID 与可验证父子进程合并。界面按 bundle ID 去重，避免两行捕获同一应用导致重复重放。默认输出、格式、进程组或输出回调健康状态变化时停止控制。后台健康任务可取消；退出、取消和重复启停清理资源；失败的资源释放保留以供重试。每个应用可单独停止，其他应用继续控制。

## 验证

环境：Apple Silicon、Xcode 27.0、Swift 6.4，本机真实输出；应用部署目标仍为 macOS 14。

- `swift test`：83 项：60 通过、23 项旧硬件 PoC 按预期跳过、0 失败。新测试涵盖真实 C DSP 的独立增益/静音、通道布局、缓变、数值钳制、格式拒绝、错误映射、进程归属、取消/退出竞态、保存失败回滚、设置恢复、单应用停止、清理重试、路由权限等待竞态和界面能力状态。
- `sh scripts/verify-app-audio.sh`：真机通过。两个独立进程输出低音量 440Hz/880Hz 信号，由打包应用创建真实 tap、聚合设备和 HAL 回调。不修改默认输出、系统音量或用户音量偏好。
- Release 构建和本地 ad-hoc 打包通过；`git diff --check`、shell 语法、Info.plist 和签名检查通过。

最近一次完整真机结果：

| 项目 | 结果 |
| --- | --- |
| 输入/输出格式 | 48kHz，双声道 |
| 应用 A 输出/输入 RMS 比例 | 0.25 |
| 应用 B 输出/输入 RMS 比例 | 0.799999237 |
| 静音 A 后输出 RMS | 0 |
| 静音 A 时 B 增益 | 保持约 0.80 |
| 取消静音 A 后增益 | 恢复 0.25 |
| 输出回调帧 A / B | 26112 / 15360 |
| 原始播放静音属性读回 | 通过 |
| 连续输出检查 | 5 秒通过 |
| 重复启停 | 3 次通过 |
| 清理并保持默认输出 | 通过 |

RMS 比例来自真实 HAL 回调中的 PCM 输入和增益输出；不等同于扬声器声压测量。3 次启停和 5 秒连续检查不能代替长时间稳定性，也未测量端到端延迟、CPU 或内存。临时报告/诊断日志不提交到 Git。

## 使用与权限

构建并打开 `VolumeControl.app`，播放目标应用音频，点击该应用的启用图标，验证成功后调节滑块。首次捕获由 macOS 请求系统音频录制权限，Info.plist 使用 `NSAudioCaptureUsageDescription`。此功能不请求麦克风权限；旧 BlackHole 输入测试的麦克风权限是独立的。

停止该行或全部控制会释放 tap，恢复原始播放。应用设置按 bundle ID 保留供下次显式启用，不自动捕获未启用的程序。

安装、卸载、权限撤销和回滚步骤见 [README](../README.md#安装卸载和回滚)。本阶段不安装驱动，不调整系统默认设备，不新增系统扩展 entitlement；正式 Developer ID 签名和公证仍属于后续发布阶段。

## 兼容性与待验收

当前上限 8 个应用。只支持真实默认设备的单输出流、1–2 通道、原生无填充 Float32 PCM；额外聚合输入或复杂布局拒绝启用。暂停、无可验证信号、权限拒绝、受保护音频、独占设备或输出到其他设备时，不显示虚假的可控状态。归属不能确认的浏览器辅助进程不自动合并；新的辅助进程出现需要重新启用。

| 场景 | 状态 |
| --- | --- |
| 两个独立音频进程增益/静音、清理、重复启停 | 真机通过 |
| 权限拒绝/没有信号、取消、应用退出、写入和清理错误 | 模拟通过，拒绝权限未改动本机隐私设置来重复测试 |
| Music / Safari / Chrome / 会议应用实际覆盖 | 待逐应用验收 |
| 蓝牙断开、换设备、采样率变化、睡眠唤醒 | 业务模拟通过，真机矩阵待扩大 |
| 30 分钟以上运行、CPU/内存、端到端延迟 | 待测量 |
| macOS 14.2 / Intel / 新机器安装 | 有版本保护，真机覆盖待扩大 |

## 依据

- [Apple：Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)：进程 tap、聚合设备输入、macOS 14.2 与系统音频录制权限。
- [CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription) 与 [CATapMuteBehavior](https://developer.apple.com/documentation/coreaudio/catapmutebehavior)：指定进程/设备流和捕获期间的原始播放行为。
- 本机 SDK：`AudioHardwareTapping.h`、`CATapDescription.h`、`AudioHardware.h`：函数、版本、属性、聚合设备和 IOProc 生命周期。
