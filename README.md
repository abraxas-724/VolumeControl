# VolumeControl

macOS 14+ SwiftUI 状态栏音量工具，使用 Swift 5.9+。

## 当前能力

- 系统主音量、静音和输出设备状态。
- 运行应用发现、图标和音频会话状态。
- 实验性 BlackHole 混合音频路由验证：输入捕获、格式转换、真实设备输出、失败清理和输出恢复。

**应用独立音量尚未实现。** BlackHole 接收混合后的音频，不能凭进程枚举为每个应用提供独立增益。应用行继续显示不可控制原因，不显示可用的应用音量/静音控件。

2026-10-04：按 [TASK_PLAN.md](TASK_PLAN.md) 推进第一阶段。Task 1.1/1.2 的路由代码和模拟测试已完成；Task 1.3 的听音、延迟和稳定性验收待执行。详见 [验证记录](docs/AUDIO_ROUTING_VALIDATION.md)。当前没有经过真机验证的延迟、CPU 或内存指标。

## 构建和测试

```sh
git clone https://github.com/abraxas-724/VolumeControl.git
cd VolumeControl
swift test
swift build -c release
sh scripts/build-app.sh
open VolumeControl.app
```

`swift test` 使用路由和权限替身、内存 PCM 数据，不切换系统设备、不写用户偏好、不启动真实录音。旧硬件 PoC 测试默认跳过；它们不能证明新版路由回路正确，不要用其结果替代人工验收。

## 音频路由验证

1. 按需安装 BlackHole 2ch，确认系统能识别其输入/输出。
2. 在系统设置中选择真实输出设备，例如内建扬声器或耳机。不能以 BlackHole 或聚合设备作为转发目的地。
3. 启动打包的 `VolumeControl.app`，点击“验证音频路由”。首次启动验证会请求麦克风/音频输入权限，目的是读取 BlackHole 输入；系统主音量功能不需要此权限。
4. 播放音乐，按[真机验收矩阵](docs/AUDIO_ROUTING_VALIDATION.md#真机验收矩阵待执行)检查听音、设备变化和恢复。
5. 点击“停止路由验证”。正常退出应用也会尝试恢复原始输出；若验证期间主动选择了其他设备，保留该选择。

路由仅在用户操作后启用。先启动转发引擎，再切换默认输出到 BlackHole；启动失败会清理引擎并尝试恢复原始输出。恢复失败会显示错误，并在下次停止/启动时重试。

路由期间系统主音量针对默认设备 BlackHole，其是否支持音量属性由设备决定；真实设备音量请在系统设置中调节。此功能仍处于 PoC 阶段，尚无独立时钟漂移补偿或无缝热插拔能力。

## 安装、卸载和回滚

应用脚本生成的是本地 ad-hoc 签名包，尚未完成 Developer ID 签名、公证和发布验收。

- 安装：运行打包脚本后，可将应用放入“应用程序”。BlackHole 必须通过其官方安装包或 Homebrew 单独安装；应用不自动安装驱动。
- 卸载：先停止验证，确认默认输出已恢复到真实设备，退出并删除应用。使用 BlackHole 官方卸载说明移除驱动；若由 Homebrew 安装，使用对应 cask 的卸载命令。
- 回滚：关闭验证并选择真实输出设备。若应用崩溃、强制退出或原设备断开导致恢复失败，在“系统设置 → 声音 → 输出”中手动选择可用设备。可以撤销应用的麦克风权限，系统主音量功能仍可使用。

## 后续路线

第一阶段通过真机验收后再评估应用音频隔离方案。计划中的 DriverKit 虚拟设备及客户端 API 示例尚未通过 SDK/签名验证，不能视为可运行实现。优先验证 Core Audio Process Tap 捕获/重放闭环；若需要虚拟设备，评估 Audio Server Plug-in。详见 [技术方案](PRODUCT_TECHNICAL_SOLUTION.md)和[当前验证记录](docs/AUDIO_ROUTING_VALIDATION.md#下一阶段技术门槛)。

## 项目结构

- `Sources/VolumeControl/`：SwiftUI、应用状态和系统音频服务。
- `Sources/VolumeControl/Audio/V2/`：实验性音频组件与协议适配器。
- `Tests/VolumeControlTests/`：模拟业务测试、PCM 测试和显式选择的旧硬件 PoC。
- `scripts/`：本地应用和 DMG 构建脚本。
- `TASK_PLAN.md`：执行计划。
- `docs/AUDIO_ROUTING_VALIDATION.md`：本阶段实现范围、验证结果和验收步骤。

[GitHub 仓库](https://github.com/abraxas-724/VolumeControl) · [MIT License](LICENSE)
