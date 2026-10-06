# UI 美化与开源功能调研

调研日期：2026-10-06。依据项目官方 README、公开源码目录及 FineTune 面板源文件；未安装这些第三方工具做音频性能对比。下列实现难度是结合 VolumeControl 当前架构的判断，并非这些项目的实测结果。

## 参考项目

| 项目 | 官方可确认的能力 | 对本项目的价值 | 边界 |
| --- | --- | --- | --- |
| [FineTune](https://github.com/ronitsingh10/FineTune) | 应用音量、固定/隐藏应用、设备优先级、逐应用路由、键盘操作、EQ、外观密度 | 最接近本产品；借鉴设备/应用分区、简洁应用行、渐进展开高级功能 | 要求 macOS 15+；本项目保留 macOS 14，不能直接搬入高版本 API |
| [BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic) | 其他音源播放时自动暂停/恢复音乐、逐应用音量、系统录音 | 自动暂停音乐适合会议与视频场景 | README 标注 alpha；虚拟设备架构与当前原生 Process Tap 方案不同 |
| [MonitorControl](https://github.com/MonitorControl/MonitorControl) | 外接显示器音量、DDC、快捷键与原生媒体键、OSD | 原生控件风格、精简菜单与高级设置分层；外接显示器音量是实际痛点 | DDC 随显示器/连接协议变化，媒体键可能需要辅助功能权限 |
| [eqMac](https://github.com/bitgapp/eqMac) | 基础/10 段 EQ、左右平衡、HDMI 音量等；README 另列 Pro 功能 | 后续音色与软件音量方向的参考 | 仓库明确公开源码对应 v1.3.2、不含 Pro，新版本在私有分支；Pro 混音器不能作为公开实现证据 |

源码入口，供下一阶段继续调查：

- FineTune：[MenuBarPopupView.swift](https://github.com/ronitsingh10/FineTune/blob/main/FineTune/Views/MenuBarPopupView.swift)、[DesignTokens.swift](https://github.com/ronitsingh10/FineTune/blob/main/FineTune/Views/DesignSystem/DesignTokens.swift)、[PopupKeyboardNavModel.swift](https://github.com/ronitsingh10/FineTune/blob/main/FineTune/Views/MenuBar/PopupKeyboardNavModel.swift)。面板代码包含设备区、应用区及固定但未播放的应用行。
- BackgroundMusic：[BGMAutoPauseMusic.mm](https://github.com/kyleneideck/BackgroundMusic/blob/master/BGMApp/BGMApp/BGMAutoPauseMusic.mm)、[BGMAppVolumesController.mm](https://github.com/kyleneideck/BackgroundMusic/blob/master/BGMApp/BGMApp/BGMAppVolumesController.mm)。
- MonitorControl：[MediaKeyTapManager.swift](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Support/MediaKeyTapManager.swift)、[KeyboardShortcutsManager.swift](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Support/KeyboardShortcutsManager.swift)。
- eqMac：[BasicEqualizer.swift](https://github.com/bitgapp/eqMac/blob/master/native/app/Source/Audio/Effects/Equalizers/Basic/BasicEqualizer.swift)。

本轮自行编写 SwiftUI 实现，没有复制第三方代码、图标或截图。后续若复用源码，应先核对对应文件许可证及项目分发要求。

## 本轮已落地

- 面板保留 480 点宽度，使用系统动态背景色、靛蓝强调色、14 点圆角与细描边，随系统浅色/深色切换。
- 系统音量成为独立卡片；大号百分比、静音与输出设备选择集中展示。不支持硬件音量的提示与百分比设置无关，始终可见。
- 应用混音器显示已验证启用数与发现总数；每行包含图标、名称、状态和操作。等待恢复、验证中、不可调节均保留具体原因，不展示无效滑块。
- 新增即时名称搜索和“全部应用 / 已启用”筛选。“已启用”包括等待恢复的已记住应用和正在验证的应用，便于取消或停止；不据此把应用标记为已验证支持，也不触发捕获。上方启用计数只统计已验证支持的应用。
- 保留 320 点应用列表高度；无应用、筛选无结果有单独空状态。停止全部、设置、刷新与静音使用 SF Symbols 和 VoiceOver 标签。
- 高级路由默认收起；解释信息移到列表下方及控件提示中。错误仍单独显示、可以选择复制并关闭。
- 界面拆入 `Presentation/`。应用启动/退出监听移到模型，使用 NSWorkspace 自己的通知中心，面板关闭时仍刷新，释放模型时移除监听。

## 推荐功能与实施顺序

| 顺序 | 功能 / 来源 | 用户收益 | 当前状态与实现难度 | 验收重点 |
| --- | --- | --- | --- | --- |
| 已有 | 记住音量、静音与启用选择 / FineTune 类工具 | 重启后不用重新调节 | beta.3 已有，应保留 | 真实播放后重新验证，失败保留原因 |
| 本轮 | 搜索和已启用筛选 | 运行应用较多时快速找到目标 | 已完成；只筛选显示数据 | 中文/大小写/空白、等待恢复仍可停止 |
| 下一轮 1 | 固定常用应用、隐藏无关应用 / FineTune | 面板更短，更容易操作 | 低至中；用注入偏好仓储按 bundle ID 保存 | 固定未运行应用不自动捕获；隐藏不等于停止控制，需明确提示 |
| 下一轮 2 | 面板键盘操作与快捷键 / FineTune、MonitorControl | 无需鼠标调音量或打开面板 | 面板内低至中，全局快捷键中；建议先实现面板内 | 搜索输入不被拦截，焦点可见；媒体键冲突与权限单独验收 |
| 下一轮 3 | 设备优先级 / FineTune | 插入耳机自动切换，拔出自动回退 | 中；现有设备列表与安全切换可复用 | 用户显式开启、断开回退、外部手动选择不被反复覆盖、会话清理失败中止切换 |
| 后续 1 | 会议时降低音乐 / BackgroundMusic 自动暂停启发 | 会议讲话时保留低音量音乐 | 中至高；建议先做临时衰减而非控制播放器 | 真实信号活动、恢复原增益、去抖与迟滞；临时衰减不得覆盖记忆音量 |
| 后续 2 | 音量场景 / 本项目扩展建议 | 一键进入会议、工作、游戏配置 | 中；在以上能力稳定后组合设备和应用偏好 | 不自动启用从未授权的应用；部分失败可回滚并解释 |
| 音频专项 | 实时电平表 / 混音器方向 | 看见哪一个受控应用在发声 | 中；增加实时安全峰值/RMS 采样、低频发布 | 未捕获应用不显示假电平，回调不分配/加锁，面板关闭停止 UI 更新 |
| 音频专项 | 外接显示器音量 / MonitorControl、eqMac | HDMI/显示器无法用系统滑块时可调音量 | 高；DDC 或软件增益需独立能力探针 | 接口、显示器和睡眠矩阵；未知设备仍禁用控件 |
| 音频专项 | 逐应用设备路由 / FineTune | 会议走耳机，音乐走扬声器 | 高；当前只支持默认真实输出，需扩展会话端点及多时钟处理 | 设备断开、时钟漂移、格式变化、CPU 与端到端延迟 |
| 暂缓 | EQ、增益超过 100%、录音 / eqMac、BackgroundMusic | 音色调整或录制 | 高；不属于当前 0...1 增益合同，需独立设计 | 滤波稳定性、限幅和削波、独立录制授权与存储生命周期 |

建议先完成“常用应用固定 → 面板键盘操作 → 设备优先级”，三项都能提升每天的操作效率。会议衰减有辨识度，但需要先扩大真实应用验收，不能把检测到音频进程当成持续有声信号。

## 验证及限制

- `swift test`：117 项测试，23 项既有硬件 PoC 跳过，0 失败。新增 3 项筛选测试，覆盖搜索匹配、状态保留、组合条件与重复名称进程。
- `VolumePanelTests`：面板列表可用高度、刷新不反向写系统音量；渲染浅色、深色与设备切换错误三种截图，已人工查看。
- `sh scripts/build-app.sh`：Release 构建与 ad-hoc 签名成功。旧 `Audio/V2/` 实验代码仍有未使用变量与 CFString 指针编译警告，本轮未修改。
- `git diff --check`：通过。
- 截图由协议替身生成，应用图标为占位图标；不代表腾讯会议等真实应用在本轮重新验收。搜索、筛选和截图测试未修改真实音量、默认设备或用户偏好。
- 尚未自动操纵真实状态栏面板、VoiceOver、小屏弹出布局或系统权限弹窗；音频兼容性、长时间性能及正式签名进度不因此改变。上述推荐功能除标记“已有/本轮”外均未实现。
