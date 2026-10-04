# VolumeControl 项目进度总结

**更新日期**：2024-10-04

## 当前状态

VolumeControl 已完成 **P0、P1、P2** 三个阶段，系统音量控制、设备监听和应用发现功能全部正常。应用级音量控制因 macOS 公开 API 限制尚未实现。

## 已完成功能 ✅

### P0 - 计划与技术验证
- ✅ SwiftPM 工程结构
- ✅ 状态栏应用外壳（MenuBarExtra）
- ✅ 领域模型与协议定义
- ✅ 构建脚本（scripts/build-app.sh）

### P1 - 系统音量 MVP
- ✅ 系统音量读写（0-100%）
- ✅ 硬件静音切换与图标联动
- ✅ 默认输出设备名称显示
- ✅ 设备切换自动刷新
- ✅ 登录启动（SMAppService）
- ✅ 设置页面（登录启动、显示百分比）

### P2 - 应用发现与状态展示
- ✅ 运行中应用列表（NSWorkspace）
- ✅ 应用图标与名称展示
- ✅ Core Audio 进程对象列表读取
- ✅ 音频会话检测状态
- ✅ 应用启动/退出自动刷新
- ✅ 空状态与错误状态分离
- ✅ 8 个单元测试覆盖核心逻辑

## 未完成功能 ⚠️

### P3 - 应用级音量控制（技术限制）
- ⚠️ **当前状态**：会话探测已实现，但所有应用标记为"系统接口不支持应用增益"
- ❌ macOS 公开 Core Audio API 不提供通用进程级增益/静音属性
- 🔄 **需要评估的方案**：
  - 虚拟音频设备（类似 BlackHole/Loopback）
  - 辅助组件/驱动（需要签名、公证、安装流程）
  - 私有 API 研究（可能不稳定或被拒绝）

### P4 - 签名与发布
- ❌ Developer ID Application 签名
- ❌ 公证流程（notarytool + stapler）
- ❌ 新机器安装与卸载验收
- ❌ DMG/ZIP 分发包制作
- ⚠️ 当前仅有 ad-hoc 签名本地应用

## 文件结构

```
VolumeControl/
├── Sources/VolumeControl/
│   ├── VolumeControlApp.swift          # 主应用和 UI
│   ├── VolumeControlModel.swift        # ViewModel 和状态管理
│   ├── AudioService.swift              # Core Audio 系统音量服务
│   ├── AudioDeviceMonitor.swift        # 设备切换监听
│   ├── ApplicationDiscovery.swift      # 应用发现和会话探测
│   └── LoginItemController.swift       # 登录启动管理
├── Tests/VolumeControlTests/
│   └── VolumeControlModelTests.swift   # 单元测试（8 个测试）
├── scripts/
│   └── build-app.sh                    # 应用构建脚本
├── PROJECT_PLAN.md                     # 详细项目计划
├── PRODUCT_TECHNICAL_SOLUTION.md       # 技术方案文档
├── AGENTS.md                           # 开发规范
└── README.md                           # 用户文档
```

## 测试验证

- **构建测试**：`swift build` ✅ 通过
- **单元测试**：`swift test` ✅ 8/8 通过
- **应用打包**：`sh scripts/build-app.sh` ✅ 生成 VolumeControl.app
- **功能测试**：
  - ✅ 系统音量滑杆实时调整
  - ✅ 静音切换和恢复
  - ✅ 设备切换后自动刷新
  - ✅ 应用启动/退出后列表更新
  - ✅ 登录启动注册和取消注册
  - ✅ 百分比显示切换

## 预期功能与实际差距

| 功能 | 计划状态 | 实际状态 | 差距说明 |
|-----|---------|---------|---------|
| 系统音量控制 | P1 | ✅ 已完成 | 完全符合预期 |
| 设备监听 | P1 | ✅ 已完成 | 完全符合预期 |
| 应用发现 | P2 | ✅ 已完成 | 完全符合预期 |
| 应用音量控制 | P3 | ⚠️ 未实现 | macOS API 限制 |
| 签名与公证 | P4 | ❌ 未开始 | 需要 Developer ID |
| 收藏与排序 | P5 | ❌ 未开始 | 增强功能 |

## 技术债务

1. **应用级音量控制技术路径不明确**
   - 文档和代码都承认当前无法通过公开 API 实现
   - 需要独立评估虚拟设备/辅助组件方案及其成本

2. **真机验收测试不完整**
   - 缺少蓝牙设备、外接显示器音频等复杂场景测试
   - 需要在多种硬件配置下验证

3. **CI/CD 未配置**
   - 未添加 GitHub Actions 自动化构建和测试
   - 未设置发布流程自动化

4. **开源许可证未确定**
   - 仓库尚未添加 LICENSE 文件

## 下一步行动建议

### 短期（1-2 周）
1. 决定是否继续 P3：评估虚拟音频设备方案的技术可行性和用户价值
2. 配置 GitHub Actions CI：自动运行 `swift build` 和 `swift test`
3. 添加开源许可证（推荐 MIT 或 Apache 2.0）

### 中期（1 个月）
1. 如果评估 P3 技术方案可行，开始辅助组件设计和实现
2. 配置 Developer ID 签名和公证流程
3. 完善真机验收测试矩阵

### 长期（2-3 个月）
1. 完成 P4 签名与发布
2. 制作 DMG 安装包和用户文档
3. 根据用户反馈评估 P5 增强功能

## 核心问题

**应用级音量控制的技术瓶颈**：

macOS 公开 Core Audio API 提供了进程对象列表（`kAudioHardwarePropertyProcessObjectList`）和进程 PID/Bundle ID 读取，但没有暴露通用的进程级增益（volume）或静音（mute）属性。这意味着：

1. ✅ 可以发现哪些应用正在使用音频
2. ❌ 不能通过公开 API 调整单个应用的音量
3. ⚠️ 可能的解决方案：
   - 虚拟音频设备作为中间层（需要驱动签名）
   - 应用内音频控制（需要每个应用单独支持）
   - 私有 API（不稳定且可能违反 App Store 规则）

当前代码已诚实地将所有应用标记为 `unsupported("系统接口不支持应用增益")`，而不是伪造可用但不生效的控件。
