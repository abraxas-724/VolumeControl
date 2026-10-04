# VolumeControl v1.0.0 - Initial Release

🎉 首次正式发布！VolumeControl 是一款优雅的 macOS 菜单栏音量控制工具。

## ✨ 功能特性

### 核心功能
- ✅ **系统音量控制** - 实时显示和调整音量（0-100%）
- ✅ **静音开关** - 一键切换系统静音
- ✅ **音频设备管理** - 显示当前默认输出设备，自动检测设备切换
- ✅ **音频应用监控** - 实时显示正在播放音频的应用
- ✅ **系统集成** - 登录时自动启动，菜单栏常驻

### 技术特性
- 原生 SwiftUI 界面
- Core Audio 音频控制
- 实时设备监听
- 符合 macOS 14+ 标准

## 📦 安装

### 方式 1: 下载 DMG（推荐）
1. 下载 `VolumeControl-1.0.0.dmg`
2. 打开 DMG 文件
3. 将 VolumeControl 拖入 Applications 文件夹
4. 首次运行时右键点击选择「打开」

### 方式 2: 从源码编译
```bash
git clone https://github.com/abraxas-724/VolumeControl.git
cd VolumeControl
swift build -c release
```

## 💻 系统要求

- macOS 14.0 (Sonoma) 或更高版本
- Apple Silicon (M1/M2/M3) 或 Intel 处理器
- 约 20-30 MB 磁盘空间

## 📚 文档

- [README](https://github.com/abraxas-724/VolumeControl/blob/main/README.md) - 完整项目介绍
- [CONTRIBUTING](https://github.com/abraxas-724/VolumeControl/blob/main/CONTRIBUTING.md) - 贡献指南
- [CHANGELOG](https://github.com/abraxas-724/VolumeControl/blob/main/CHANGELOG.md) - 版本历史

## 🐛 已知限制

- 仅支持系统级音量控制（无应用级音量控制）
- 需要 macOS 14.0 或更高版本
- 本版本无键盘快捷键支持

## 🚀 未来计划

### v1.1.0（计划中）
- 键盘快捷键支持
- 音量预设保存
- 多语言支持

### v2.0.0（长期）
- 应用级音量控制
- 音频均衡器
- 输出设备快速切换

## 📝 变更日志

### 新增
- 系统音量控制（0-100%）
- 音量百分比实时显示
- 静音/取消静音切换
- 默认输出设备显示
- 设备热插拔自动检测
- 运行中音频应用监控
- 应用图标和名称显示
- 登录时自动启动选项
- 设置面板
- 菜单栏图标常驻
- 原生 SwiftUI 界面

### 技术
- Swift 5.9+ 实现
- 支持 macOS 14.0+
- 使用 Swift Package Manager
- 清晰的分层架构
- 完整的错误处理
- 实时音频设备监听
- 8 个单元测试（100% 通过）

## 🙏 致谢

- Swift 社区的优秀文档
- Core Audio 技术指南
- [Background Music](https://github.com/kyleneideck/BackgroundMusic) 项目的灵感
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) 虚拟音频设备

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](https://github.com/abraxas-724/VolumeControl/blob/main/LICENSE) 文件

---

**完整变更日志**: https://github.com/abraxas-724/VolumeControl/blob/main/CHANGELOG.md

如果这个项目对你有帮助，请给个 ⭐️ Star！
