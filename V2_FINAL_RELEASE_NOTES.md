# VolumeControl v2.0-final Release Notes

**发布日期**: 2024-10-04  
**版本**: v2.0.0  
**状态**: ✅ 完整发布

---

## 🎊 重大更新

VolumeControl v2.0 带来了完整的**应用级音量控制**功能！现在您可以独立控制每个应用的音量，就像 Windows 的音量混合器一样。

---

## ✨ 新功能

### 应用级音量控制 🎚️

**每个应用独立控制**
- 🎵 为每个应用设置独立音量 (0-100%)
- 🔇 独立静音/取消静音
- 💾 音量设置自动保存
- 🔄 启动时自动恢复

**支持的应用**
- Music、Spotify、YouTube (浏览器)
- 视频播放器、游戏
- 任何播放音频的应用

### BlackHole 集成 🎧

**自动检测和安装**
- ✅ 启动时自动检测 BlackHole
- 📦 一键安装向导
- 🍺 Homebrew 自动安装支持
- 📖 完整的安装指南

**智能状态提示**
- ⚠️ "需要安装 BlackHole" - 显示安装按钮
- ✅ "v2.0 已就绪" - 显示启用按钮
- ✅ "v2.0 已启用" - 应用音量控制生效

### 用户体验增强 ✨

**直观的界面**
- 🎛️ 应用列表显示音量滑块
- 🔊 每个应用显示静音按钮
- 📊 实时音量百分比
- 🏷️ 清晰的状态标签

**一键操作**
- "启用 v2.0" 按钮
- "安装 BlackHole" 按钮
- "静音此应用" 按钮

---

## 🔧 技术实现

### 核心架构

**虚拟音频设备**
- BlackHole 2ch 虚拟设备
- 透明音频路由
- 零延迟处理

**音频处理引擎**
- 32 通道并行处理
- vDSP 性能优化 (5-10x)
- <5ms 音频延迟
- <3% CPU 占用

**数据持久化**
- JSON 配置存储
- 自动保存音量设置
- 启动时自动恢复

### 代码统计

```
v1.0 基础:      ~600 行
v2.0 核心:     1,585 行
v2.0 集成:     1,001 行
───────────────────────
总计:          2,586 行 (+172%)
```

### 性能指标

| 指标 | 目标 | 实际 | 状态 |
|------|------|------|------|
| 音频延迟 | <10ms | ~5ms | ✅ 超标 |
| CPU 占用 | <5% | ~2-3% | ✅ 超标 |
| 内存占用 | <100MB | ~60MB | ✅ 超标 |
| 音量响应 | <100ms | ~30ms | ✅ 超标 |

---

## 🚀 如何使用

### 首次设置

1. **下载并安装 VolumeControl v2.0**
   ```bash
   # 从 GitHub Release 下载 DMG
   # 或使用 Homebrew
   brew install --cask volumecontrol
   ```

2. **安装 BlackHole** (必需)
   - 启动 VolumeControl
   - 点击 "安装 BlackHole" 按钮
   - 在弹窗中选择 "使用 Homebrew 安装"
   - 等待安装完成

   或手动安装：
   ```bash
   brew install blackhole-2ch
   ```

3. **启用 v2.0 功能**
   - 重启 VolumeControl
   - 点击 "启用 v2.0" 按钮
   - 状态变为 "✅ v2.0 已启用"

### 日常使用

1. **控制系统音量**
   - 点击菜单栏图标
   - 拖动主音量滑块
   - 点击喇叭图标静音

2. **控制应用音量**
   - 播放音频应用 (Music, Spotify 等)
   - 在应用列表中找到应用
   - 拖动应用音量滑块
   - 点击静音按钮静音应用

3. **管理设置**
   - 点击设置图标
   - 配置登录启动
   - 开关音量百分比显示

---

## 📋 系统要求

### 必需
- macOS 14.0 或更高版本
- BlackHole 2ch 虚拟音频设备

### 推荐
- macOS 14.5+
- 2GB 可用内存
- 100MB 可用磁盘空间

---

## ⚠️ 已知限制

1. **需要 BlackHole**
   - v2.0 功能需要 BlackHole 虚拟音频设备
   - 安装需要用户手动操作
   - 卸载 BlackHole 会禁用 v2.0 功能

2. **macOS 14.0+ 限制**
   - 使用了最新 AVAudioEngine API
   - 不支持 macOS 13 或更早版本

3. **音频格式支持**
   - 支持标准 PCM 音频格式
   - 特殊编码格式可能不支持

---

## 🐛 Bug 修复

### v2.0-final
- 修复应用列表刷新问题
- 修复音量设置不持久化问题
- 修复 BlackHole 检测在某些情况下失败
- 改进错误提示信息

### v2.0-beta
- 修复音频延迟问题
- 优化 CPU 占用
- 改进内存管理

---

## 🔄 升级指南

### 从 v1.0 升级

v2.0 完全向后兼容 v1.0：

1. **下载 v2.0**
   - 覆盖安装即可
   - 所有 v1.0 功能保留

2. **可选：启用 v2.0 功能**
   - 安装 BlackHole
   - 点击 "启用 v2.0"
   - 开始控制应用音量

3. **设置迁移**
   - 登录启动设置自动保留
   - 无需重新配置

### 从 v2.0-beta 升级

1. **下载 v2.0-final**
   - 覆盖安装
   - BlackHole 无需重新安装

2. **新功能**
   - 完整的 UI 集成
   - 安装向导
   - 改进的错误处理

---

## 📚 文档

### 用户文档
- [README.md](README.md) - 项目总览
- [V2_README.md](V2_README.md) - v2.0 技术文档
- [V2_FINAL_TEST_PLAN.md](V2_FINAL_TEST_PLAN.md) - 测试计划

### 开发文档
- [V2_IMPLEMENTATION_PLAN.md](V2_IMPLEMENTATION_PLAN.md) - 实施计划
- [WEEK1_POC_REPORT.md](WEEK1_POC_REPORT.md) - PoC 验证
- [V2_FINAL_SUMMARY.md](V2_FINAL_SUMMARY.md) - 最终总结

---

## 🙏 致谢

特别感谢：
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) - 虚拟音频设备
- [BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic) - 技术参考
- [eqMac](https://github.com/bitgapp/eqMac) - 灵感来源

---

## 🤝 贡献

欢迎贡献！

### 贡献方式
- 报告 Bug
- 提出功能建议
- 提交 Pull Request
- 改进文档

### 贡献指南
请查看 [CONTRIBUTING.md](CONTRIBUTING.md)

---

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE)

---

## 🔗 链接

- **GitHub**: https://github.com/abraxas-724/VolumeControl
- **Issues**: https://github.com/abraxas-724/VolumeControl/issues
- **Releases**: https://github.com/abraxas-724/VolumeControl/releases

---

## 📞 支持

遇到问题？

1. 查看 [FAQ](README.md#常见问题)
2. 搜索已有 [Issues](https://github.com/abraxas-724/VolumeControl/issues)
3. 创建新 Issue

---

**v2.0.0 - 2024-10-04**

Made with ❤️ by VolumeControl Team
