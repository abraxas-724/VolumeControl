# 耳机接入自动切换

2026-10-06。设置 → 通用 → 耳机与输出。

“插入耳机自动切换”默认开启，仅响应新接入事件；启动应用、常规刷新、开启开关或修改指定耳机都不会抢回当前输出。手动改回扬声器后会保持，直到下一次耳机重新接入。系统已经选中该耳机时不重复写入。

“指定耳机”默认自动识别。对没有正确报告耳机终端类型的 USB/蓝牙设备，可选中该设备；用持久 UID 记住选择，重新连接后的 AudioDeviceID 可以不同。断开后设置保留，显示“已保存的耳机（未连接）”。该指定是用户确认目标，不把所有 USB 或蓝牙输出都当作耳机。

## 接入判断与切换

- 优先读取 Core Audio 输出流终端类型 `kAudioStreamTerminalTypeHeadphones`；内置输出读取 `kAudioDevicePropertyJackIsConnected`，支持同一设备 ID 下的插孔状态变化。无终端类型的驱动使用明确的 headphone/headset/earphone/earbud/AirPods/耳机名称兜底。
- 虚拟/聚合设备、HDMI/DisplayPort 和网络输出排除。可选分类属性不存在时保留手动菜单；实际读取失败记录有上下文的错误，并暂停该次自动判断，避免把查询失败当成断开重连。
- 监听系统输出/设备列表以及设备输出端的 jack、data source、streams 属性，在主队列刷新；正常运行还有既有的 2 秒刷新作为补充。移除设备和退出时注销监听。
- 初次快照建立基线，新耳机出现或同一内置输出从非耳机变为耳机时才切换。同批出现多个候选时优先指定耳机，其余按设备 ID 确定顺序。
- 复用 `selectOutputDevice`：确认设备仍可用，取消正在验证的任务，清理绑定旧设备的 Process Tap，保留设置，写入默认输出，然后重新验证恢复。清理失败中止写入，切换失败可读展示；每次接入只尝试一次，不在每 2 秒刷新时反复写入。
- 高级路由测试或启动期间跳过接入，不在测试结束后执行积压切换。拔出后的输出选择由 macOS 接管，本功能不强行恢复某个旧设备。

判断不依赖视图是否显示。View 只绑定模型，UserDefaults 通过 `DeviceSwitchPreferenceStoring` 注入，使用独立的 `devices.autoSwitchHeadphones` / `devices.preferredHeadphoneUID` 键；重置界面不改变音频行为偏好。

## 验证

模拟测试覆盖首次启动、接入/重连、同 ID 插孔变化、手动选择不抢回、关闭开关、路由互斥、稳定 UID 指定、排除音箱/虚拟/显示设备、元数据/设备列表查询失败、一次性失败报告、清理失败中止及偏好保存。测试不修改真实音量、默认设备或用户偏好。

`swift test`：147 项，25 项按条件跳过，0 失败。Release 构建及 `git diff --check` 通过。

显式只读真机验收：

```sh
VOLUMECONTROL_READONLY_DEVICES=1 swift test --filter HeadphoneAutoSwitchPolicyTests
```

本机 macOS 27.0.1 检查通过：HyperX Cloud III 被识别为 USB 耳机；MacBook Air 扬声器为内置非耳机输出；BlackHole 2ch 为虚拟输出，三者的 UID 与分类属性可读。该检查不执行设备切换。

真实 USB 插拔、3.5 mm 插孔、蓝牙断连重连和活跃应用捕获中的切换仍需对应硬件人工验收；未用只读检查代替这些结果。功能不引入新权限、驱动或系统扩展，安装和回滚沿用 README 的正常退出、替换应用步骤。
