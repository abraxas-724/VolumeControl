# VolumeControl

<div align="center">

![VolumeControl](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Version](https://img.shields.io/badge/version-1.0.0-red)

优雅的 macOS 菜单栏音量控制工具

[功能特性](#功能特性) • [安装](#安装) • [使用](#使用) • [开发](#开发) • [贡献](#贡献)

</div>

---

## 概述

VolumeControl 是一款轻量级的 macOS 菜单栏应用，为系统音量控制提供直观、快速的访问方式。采用原生 SwiftUI 构建，提供流畅的用户体验和现代化的界面设计。

### 为什么选择 VolumeControl？

- 🚀 **轻量快速** - 原生 Swift 实现，内存占用低，启动迅速
- 🎨 **优雅设计** - 遵循 macOS 设计规范，与系统完美融合
- 🔒 **隐私安全** - 仅使用公开系统 API，不收集任何用户数据
- 🎯 **功能实用** - 快速调整音量、切换静音、查看音频应用
- 🛠 **开源免费** - MIT 许可证，完全开源，欢迎贡献

---

## 功能特性

### 核心功能

- ✅ **系统音量控制**
  - 实时显示当前音量百分比
  - 拖动滑块调整音量（0-100%）
  - 精确的音量显示和控制

- 🔇 **静音开关**
  - 一键切换系统静音
  - 清晰的静音状态指示

- 🔊 **音频设备管理**
  - 显示当前默认输出设备
  - 自动检测设备切换
  - 支持热插拔设备

- 🎵 **音频应用监控**
  - 实时显示正在播放音频的应用
  - 显示应用图标和名称
  - 快速识别音频来源

- ⚙️ **系统集成**
  - 登录时自动启动
  - 菜单栏图标常驻
  - 最小化系统占用

### 技术特性

- 原生 SwiftUI 界面
- Core Audio 音频控制
- 实时设备监听
- NSWorkspace 应用发现
- 符合 macOS 14+ 标准

---

## 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Apple Silicon (M1/M2/M3) 或 Intel 处理器
- 约 20-30 MB 磁盘空间

---

## 安装

### 方式 1: 下载预编译版本（推荐）

1. 前往 [Releases](https://github.com/yourusername/VolumeControl/releases) 页面
2. 下载最新版本的 `VolumeControl.dmg`
3. 打开 DMG 文件，将 VolumeControl 拖入 Applications 文件夹
4. 首次运行时，右键点击选择「打开」

### 方式 2: 从源码编译

```bash
# 克隆仓库
git clone https://github.com/yourusername/VolumeControl.git
cd VolumeControl

# 使用 Xcode 打开
open Package.swift

# 或使用命令行构建
swift build -c release

# 运行
.build/release/VolumeControl
```

---

## 使用

### 首次启动

1. 启动 VolumeControl
2. 在菜单栏中找到音量图标
3. 点击图标查看音量控制面板

### 基本操作

**调整音量**
- 点击菜单栏图标
- 拖动音量滑块或点击滑块轨道

**切换静音**
- 点击「静音」按钮
- 或使用键盘快捷键

**查看音频应用**
- 在音量面板底部查看「正在播放」列表
- 显示所有当前播放音频的应用

**设置**
- 点击底部齿轮图标
- 配置登录启动等选项

### 卸载

1. 退出 VolumeControl
2. 将应用从 Applications 文件夹移至废纸篓
3. （可选）删除偏好设置：
   ```bash
   rm ~/Library/Preferences/com.volumecontrol.app.plist
   ```

---

## 开发

### 项目结构

```
VolumeControl/
├── Sources/VolumeControl/
│   ├── VolumeControlApp.swift        # 应用入口
│   ├── VolumeControlModel.swift      # 主视图模型
│   ├── AudioService.swift            # 音频服务
│   ├── AudioDeviceMonitor.swift      # 设备监听
│   ├── ApplicationDiscovery.swift    # 应用发现
│   └── LoginItemController.swift     # 登录项管理
├── Tests/VolumeControlTests/         # 单元测试
├── Package.swift                     # Swift Package 配置
├── README.md                         # 本文件
└── LICENSE                           # MIT 许可证
```

### 架构设计

采用经典的分层架构：

- **Presentation Layer** (VolumeControlApp, VolumeControlModel)
  - SwiftUI 视图和用户交互
  
- **Application Layer** (AudioService, ApplicationDiscovery)
  - 业务逻辑和应用服务
  
- **Domain Layer**
  - 音频域模型和规则
  
- **Infrastructure Layer** (AudioDeviceMonitor)
  - 系统 API 封装和监听

### 构建

```bash
# 调试构建
swift build

# 发布构建
swift build -c release

# 运行测试
swift test

# 生成 Xcode 项目
swift package generate-xcodeproj
```

### 测试

```bash
# 运行所有测试
swift test

# 运行特定测试
swift test --filter VolumeControlModelTests

# 查看测试覆盖率
swift test --enable-code-coverage
```

---

## 技术栈

- **语言**: Swift 5.9+
- **框架**: SwiftUI, AppKit
- **音频**: Core Audio, AVFoundation
- **构建**: Swift Package Manager
- **测试**: XCTest
- **最低系统**: macOS 14.0

---

## 路线图

### v1.0.0 (当前版本)
- ✅ 系统音量控制
- ✅ 静音开关
- ✅ 音频应用监控
- ✅ 登录启动

### v1.1.0 (计划中)
- [ ] 键盘快捷键支持
- [ ] 音量预设保存
- [ ] 通知中心集成
- [ ] 多语言支持（中文、英文）

### v2.0.0 (未来)
- [ ] 应用级音量控制（需要 Core Audio HAL）
- [ ] 音频均衡器
- [ ] 输出设备快速切换
- [ ] 音频效果插件

---

## 常见问题

**Q: 为什么应用需要麦克风权限？**

A: VolumeControl 不需要麦克风权限。如果系统提示，可能是 Core Audio 监听导致。你可以拒绝该权限，不影响功能。

**Q: 支持应用级音量控制吗？**

A: 当前版本（v1.0）仅支持系统音量控制。应用级音量控制需要更底层的音频路由技术，已列入 v2.0 路线图。

**Q: 为什么无法控制某些应用的音量？**

A: macOS 的公开 API 不支持直接控制应用音量。系统音量会影响所有应用的音频输出。

**Q: 应用会自动更新吗？**

A: 当前版本需要手动更新。计划在未来版本中添加自动更新功能。

**Q: 应用是否收集数据？**

A: 否。VolumeControl 完全在本地运行，不收集任何用户数据，不联网。

---

## 贡献

欢迎贡献！无论是报告 bug、提出功能建议，还是提交代码，都非常感谢。

### 贡献指南

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

### 代码规范

- 遵循 Swift API Design Guidelines
- 使用有意义的变量和函数名
- 添加必要的代码注释
- 确保所有测试通过
- 保持代码风格一致

### 报告问题

在 [Issues](https://github.com/yourusername/VolumeControl/issues) 页面提交问题时，请包含：

- macOS 版本
- VolumeControl 版本
- 问题描述
- 复现步骤
- 期望行为
- 截图（如果适用）

---

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

---

## 致谢

- [Background Music](https://github.com/kyleneideck/BackgroundMusic) - 应用级音量控制研究参考
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) - 虚拟音频设备
- Swift 社区的所有贡献者

---

## 联系方式

- 项目主页: [https://github.com/yourusername/VolumeControl](https://github.com/yourusername/VolumeControl)
- 问题反馈: [Issues](https://github.com/yourusername/VolumeControl/issues)

---

<div align="center">

**如果这个项目对你有帮助，请给个 ⭐️ Star！**

Made with ❤️ for macOS

</div>
