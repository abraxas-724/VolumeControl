# 第一阶段：BlackHole 音频回路验证

本页保留 2026-10-04 的 AVAudioEngine 回路实现记录。2026-10-05 默认路由已改用固定端点 HAL 聚合设备，在 HyperX / BlackHole 配置下通过切换及恢复验收；性能和完整设备矩阵仍未完成。当前实现见 [beta.2 修复验收](AUDIO_FIX_VALIDATION.md)。

原生应用独立音量已在后续阶段通过 Process Tap 实现并完成两进程真机闭环，详见 [应用音量验收记录](PROCESS_TAP_VALIDATION.md)。本页保留 BlackHole 混合流实验结果，不代表当前应用控制能力。

## 发现的问题

原 `AudioDeviceRouter` 只切换默认输出并启动空的 AVAudioEngine，没有绑定 BlackHole 输入、真实设备输出或转发 buffer。原模型把“检测到进程音频会话”当作独立增益能力，原 README 中的独立控制和性能数字没有对应验收证据。

因此第一阶段不能按旧计划中的勾选视为完成；本次先补齐回路和真实能力状态。

## 实现范围

- `AudioRoutingDevices`：可注入的设备查询和切换接口，Core Audio 错误携带操作和 OSStatus。
- `AudioRoutingEngine`：两个 AVAudioEngine 分别绑定 BlackHole 输入和启动前的真实输出。输入 tap 复制 PCM 数据，串行队列转换后用 AVAudioPlayerNode 播放。
- 生命周期：引擎先启动，系统输出后切换；部分启动/切换失败清理；停止时恢复原设备；用户选了其他设备时保留新选择。恢复失败保留恢复信息以供重试，并显示错误。
- 回调：运行时设备/格式变化或转换失败通过主线程停止路由和报告错误；会话代号阻止旧回调停止新路由。
- 缓冲：最多 4 个待完成 buffer，累计输入时长不超过 250ms；超出预算丢弃新 buffer。该数值是积压上限，不是实测延迟，也不保证 <50ms。硬件可能不遵守请求的 512 帧 tap 大小。
- 权限：仅在用户启动验证时请求录音输入权限。取消、面板关闭或停止后，即使权限请求迟到成功也不启动路由。未打包且缺少权限说明时给出可读错误。
- 产品能力：BlackHole 提供混合流；应用级音量和静音保持不可用。模型不创建旧的应用增益组件，也不读取/写入其 UserDefaults 配置。

## 自动验证

环境：Apple Silicon、Xcode 27.0、Swift 6.4；部署目标保持 macOS 14。

- `swift test`：58 项，35 项执行通过，23 项旧硬件测试按设计跳过，0 失败。
- 模拟覆盖：启动顺序、缺少 BlackHole、拒绝虚拟目的地、部分启动失败、切换失败、恢复失败及重试、重复启动/停止、保留用户设备选择、运行时错误、旧会话回调隔离、权限拒绝和取消。
- PCM 验证：交错/非交错深复制、48kHz → 44.1kHz 非静音立体声转换、单声道 → 双声道、格式变化失败。
- 缓冲验证：时长/数量限制、并发生产者、重复完成回调、停止后迟到回调失效。

`sh scripts/build-app.sh`：Release 构建与 ad-hoc 签名打包通过。`plutil -lint`、`codesign --verify --deep --strict`、`sh -n scripts/build-app.sh` 和 `git diff --check` 通过。旧 PoC 文件仍有 4 处既有编译警告（未使用变量和 CFString 指针），本次新路由文件未产生警告。普通测试不修改真实系统音量、设备或偏好；旧 XCTest 的 `setUp` 也在跳过时禁止初始化硬件。

## 真机验收矩阵（待执行）

先运行 `sh scripts/build-app.sh`，打开打包应用，确认默认输出是可用的真实设备，再从界面启动验证。每次测试结束停止验证并检查输出恢复。

| 场景 | 操作 | 预期 | 本次结果 |
| --- | --- | --- | --- |
| 听音回路 | Music/Safari 播放，启用验证 | 从真实输出听到音频，无回授 | 未执行 |
| 格式差异 | 输入 48kHz、输出 44.1kHz | 持续有声，无明显爆音 | 仅离线 PCM 转换通过 |
| 正常停止/退出 | 停止验证、正常退出 | 默认输出恢复 | 仅模拟通过 |
| 重复启停 | 连续启停 10 次 | 无重复 tap、无设备错误 | 仅模拟通过 |
| 主动切换输出 | 验证中选择其他设备，再停止 | 保留用户选择 | 仅模拟通过 |
| 设备断开/格式变化 | 断开耳机或更改采样率 | 停止并显示错误；恢复失败可手动选择设备 | 仅模拟通过 |
| 录音权限 | 拒绝；再次授权；等待中取消 | 不授权不切设备，取消不迟到启动 | 仅模拟通过 |
| 延迟和资源 | 连续运行并测量端到端时间、CPU、RSS | 延迟 <50ms、CPU <5%、内存 <100MB | 未测量 |
| 长时间运行 | 运行至少 30 分钟 | 无累积延迟、无爆音 | 未执行 |

本次没有自动切换用户设备或播放真实音频。听音、时钟漂移、设备拔插和端到端性能需真机确认，不能由模拟测试推断完成。

## 安装、卸载和回滚

本阶段不新增系统扩展或驱动安装器。BlackHole 由用户单独安装，麦克风权限由系统弹窗授权；本地应用使用 ad-hoc 签名。

停止验证后卸载应用；需要移除 BlackHole 时遵循其官方安装方式对应的卸载说明。若恢复失败、进程崩溃或强制退出，手动将系统输出改为真实设备。原设备断开时选择其他可用输出。重新启动验证前确认系统没有停留在 BlackHole。

## 下一阶段技术门槛

1. 先完成上述真机验收，保留原始测量方法和结果，不填写估计性能数字。
2. 核验 Core Audio Process Tap 的系统版本、音频捕获权限、按进程捕获和静音/重放能力。捕获 API 的存在仍不能直接证明本产品的独立音量闭环，需两应用同时播放验收。
3. 若需要虚拟音频设备，使用 Audio Server Plug-in PoC 评估客户端分离能力。DriverKit 不应依据旧文档的伪代码直接创建生产扩展。

依据：Apple 的 [音频驱动示例](https://developer.apple.com/documentation/audiodriverkit/creating-an-audio-device-driver)建议虚拟设备使用 Audio Server Plug-in，并要求显式 App ID、profile 和相关 entitlements；不能假定免费账号即可完成预定 DriverKit 发布路径。[Audio Server Plug-in 示例](https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in)提供虚拟设备结构。[CATapDescription](https://developer.apple.com/documentation/coreaudio/catapdescription)可指定一组进程音频；[CATapMuteBehavior](https://developer.apple.com/documentation/coreaudio/catapmutebehavior)定义捕获时的原始播放行为。

本阶段设备绑定使用 [kAudioOutputUnitProperty_CurrentDevice](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice)；仍需验证 AVAudioEngine 在实际设备切换通知下的行为。
