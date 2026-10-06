# macOS 原生界面精修

本轮将主面板改为 Popover → Section → Row → Control，设置改为 macOS 侧栏偏好窗口。最低版本仍为 macOS 14；应用音量仍要求 14.2+ 且验证成功。音频引擎、能力探针、自动恢复、权限和路由逻辑均未修改。

## 改动范围

路径相对于 `Sources/VolumeControl/`。

| 优先级 | 文件 | 变更 |
| --- | --- | --- |
| P0 | `Presentation/VolumePanel.swift` | 430pt 面板；移除品牌图块、Beta、宣传语和卡片；分隔线分区；实测固定内容高度、限制列表可用空间；保留高级路由及全局停止入口 |
| P0 | `Presentation/SystemVolumeSection.swift`（新增） | 独立系统音量区域；原生 Slider、静音、等宽百分比；轻量设备 Menu，长名称截断，禁用状态和原因保留 |
| P0 | `Presentation/AppMixerSection.swift`（新增） | 搜索优先，系统 Picker Menu 筛选；LazyVStack；少量应用收缩列表、大量应用滚动；无卡片空状态 |
| P0 | `Presentation/AppVolumeRow.swift` | 图标、名称、百分比和音量操作；不再显示正常“已启用”；特殊状态和原因保留；悬停背景、停止按钮渐进披露；键盘/旁白聚焦时显示；系统右键菜单与旁白停止动作 |
| P0 | `Presentation/SettingsView.swift` | NavigationSplitView + 原生 Form；通用、外观、音频、高级、关于；保留登录项、显示设置、耳机设置、权限入口、实验路由入口、隐私和退出；版本/Beta/GitHub 放在关于 |
| P0 | `Presentation/HeadphoneSwitchSettings.swift` | 改为 Form Section；保留指定耳机、断开设备选项和路由期间暂停提示 |
| P0 | `Presentation/SettingsWindowController.swift` | 默认 720×560，可调整大小，最小 680×480；继续重用窗口，保留主题和显式置前 |
| P1 | `Presentation/PanelStyle.swift` | 统一 8pt 悬停圆角、无常驻按钮背景、短按压反馈与可见焦点；Menu 悬停反馈；微交互 120ms、状态 180ms、分区令牌 200ms |
| P1 | `Presentation/InterfaceAppearance.swift` | 系统强调色；统一 easeOut；屏幕空间/无障碍上下文；删除嵌套玻璃、强调色渐变等旧装饰工具 |
| P1 | `Presentation/PanelBackdrop.swift` | Popover 仅用系统外壳，正文透明；macOS 26+ 独立预览使用官方 glassEffect；旧系统 NSVisualEffectView .popover；深色系统底色保障文字对比，减少透明度时实色 |
| P1 | `Presentation/PanelInlineError.swift`（新增） | 小型行内错误、简短原因、关闭；长错误按需展开完整详情 |
| P1 | `Domain/InterfaceOptions.swift` | 新增 system 强调色并作为新配置默认；材质按系统自动选择；保留旧字段与原始枚举值 |
| P2 | `Presentation/MenuBarPopoverController.swift` | 屏幕高度传入稳定根节点；同步外壳与内容主题；即时响应无障碍通知；图标随现有音量状态变化；缓存符号，避免连续拖动重复创建相同图像；保留 transient、Escape/外部点击和系统动画 |
| P2 | `Presentation/VolumeControlApplicationDelegate.swift` | 订阅现有系统音量/静音/可调节状态更新菜单栏图标；沿用已有 ⌘, 设置快捷键和生命周期 |

测试文件：`VolumePanelTests.swift`（宽度、小屏、长名称、40 应用与错误）、`SettingsWindowTests.swift`（窗口复用和五页截图）、`MenuBarPopoverControllerTests.swift`（图标边界、模板图像、弹出/主题/无障碍与合成截图）、`PanelVisibilityTests.swift`（所有历史材质下实色可见）、`InterfacePreferencesTests.swift`（自动材质回退）、`NativeMaterialTests.swift`（浅/深色实色背景）、`NativeAppearanceCompatibilityTests.swift`（旧字段与系统强调色 round-trip）、`PanelAccessibilityTests.swift`（可选独立进程 AX 验收）。旧玻璃卡片/透明度滑块的截图测试由当前设计的背景及配置兼容测试取代。

## 偏好兼容性

- 存储键、结构字段和旧枚举值保留，仅向 `InterfaceAccent` 追加 `system`；已有颜色选择不被覆盖。
- Standard/Frosted/Liquid、glassStyle、透明度数值从普通设置隐藏，读取和保存仍兼容；实际面板材质自动随系统选择，历史透明度不再改变界面。
- 不新增破坏性迁移，不在读取时重写偏好；原有 playful → subtle 内存迁移保留。原有百分比键继续使用。
- 紧凑布局开关映射到原来的 density，动效开关映射到原来的 motion，不新增同义键。

## 材质与动效

macOS 26+ 使用 NSPopover 原生 Liquid Glass 外壳，内容无玻璃卡片；独立 SwiftUI 预览才使用官方 `.glassEffect(.regular, in: Rectangle())`。深色面板额外使用系统 `windowBackgroundColor` 的中性填充保障亮背景上的文字对比，不增加另一层玻璃。macOS 14–25 回退到 `.popover` 系统材质。设置使用系统 NavigationSplitView / Form 自动获得对应版本表现，未模拟 Liquid Glass。

Reduce Transparency 优先于全部历史配置：SwiftUI 使用 `windowBackgroundColor`，AppKit 窗口设为不透明；通知使已打开面板即时更新。Reduce Motion 或关闭界面动效会关闭自定义动画、按压缩放和 NSPopover 动画。数字保留 `.numericText()` 与 `.monospacedDigit()`；无弹簧、过冲或整窗缩放。

## 自审

- 主面板与应用行没有永久卡片；背景只由外层系统容器承担；设置的分组外观由原生 Form 提供。
- 自定义圆角仅 8pt；Popover 和设置分组形状交给系统；没有自定义阴影、渐变、大面积强调色或自定义 Slider。
- 正常应用无“已启用”状态文字；待启用的默认说明不重复显示；异常原因和完整错误详情仍可访问。
- 刷新、设置、静音、停止、筛选和设备菜单具有轻量悬停；不会为停止操作增减行宽或行高。
- 系统 Button / Slider / TextField / Menu 保留原生交互。停止按钮保持布局和焦点节点，键盘/旁白焦点显现；行另有旁白停止动作及右键菜单。⌘, 沿用原有 AppKit 菜单并在面板设置按钮标记。
- 列表继续懒加载；只测量固定控件；悬停仅改变局部填充；屏幕和无障碍上下文仅在数值变化时发布。

## 验证与局限

具体验证结果见下方记录。所有 UI 测试使用模拟音频、内存偏好或临时独立 UserDefaults suite，不调节真实音量或设备。显式截图验收只创建测试窗口；合成截图使用 ScreenCaptureKit 只包含测试面板和背景，避免本机 `screencapture -R` 的区域捕获错误。

- 当前真窗口视觉环境为 macOS 27.0.1；26+ API 分支已编译和运行，macOS 14–25 的 fallback 已检查和测试选择逻辑，但尚无对应版本真机截图。
- AX 服务在本机将 xctest 的窗口属性解析为应用节点，未暴露测试窗口。因此旁白树验收显式跳过，不能声称完整 VoiceOver 或物理 Tab / Shift-Tab / Space / Return 已通过。保留独立进程验收入口，后续应在打包应用中人工验收。
- 悬停及焦点反馈已实现和代码审查；长期 UI 性能、Intel 真机和真实音频/设备覆盖不由短时截图测试替代。
- 既有音频代码的未使用变量与 CFString 指针警告不属于本轮 UI 代码；没有为修复界面改动音频引擎。
- 本轮不是发布版本，不修改版本号、签名策略或创建发布 tag；正式 Developer ID 签名和公证仍未完成。

### 本轮验证结果

- `swift build`：Debug 通过，表现层无新增警告。
- `swift test`：156 项，26 项跳过，0 失败。跳过项目为既有硬件/显式验收入口。
- 显式真窗口矩阵：12 项，1 项 AX 窗口不可用跳过，0 失败；覆盖浅/深色面板、紧凑、错误、五个设置页、玻璃合成和连续开关。最后的深色对比修复另行运行真实 Popover 验收，1 项通过。
- `scripts/build-app.sh`：Apple Silicon / Intel 双架构 Release 打包通过；`codesign --verify --deep --strict VolumeControl.app` 通过；`lipo -archs` 确认 x86_64 / arm64，`vtool -show-build` 确认两个切片 minos 14.0。Xcode 27 另有 Intel 架构弃用诊断，但实际最低系统版本未提高。
- `git diff --check` 通过；仓库没有独立 SwiftLint 配置，静态检查使用编译器诊断及 diff 检查。

设计 API 依据：Apple [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)；合成截图使用官方 [SCContentFilter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(display:including:))。
