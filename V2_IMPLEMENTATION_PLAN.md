# VolumeControl v2.0 - 应用级音量控制实施计划

**目标**: 实现独立控制每个应用音量的功能  
**基于**: P3 技术研究成果  
**预计时间**: 4-6 周  
**开始日期**: 2024-10-04

---

## 📋 技术方案

基于 P3 研究，采用 **Core Audio HAL + 虚拟音频设备** 方案：

### 架构设计

```
[应用音频输出] → [虚拟设备 BlackHole] → [音频路由管理器]
                                              ↓
                                    [按进程应用增益]
                                              ↓
                                    [混合音频流]
                                              ↓
                                    [真实硬件输出]
```

### 核心组件

1. **AudioDeviceRouter** - 音频设备路由管理
   - 检测和配置虚拟音频设备
   - 管理系统默认输出设备
   - 监听设备变化

2. **AudioStreamMixer** - 音频流混合器
   - 使用 Core Audio HAL 获取应用音频流
   - 按进程 PID 识别音频来源
   - 应用独立增益控制
   - 混合所有音频流

3. **PerAppVolumeController** - 应用音量控制器
   - 存储每个应用的音量设置
   - 提供音量调整接口
   - 持久化音量配置

---

## 🗓 开发路线图

### Week 1: Core Audio HAL 基础 (10.4 - 10.11)

**目标**: 掌握 Core Audio HAL API，实现基础音频流捕获

- [ ] Day 1-2: 学习 Core Audio HAL 文档
  - AudioObjectGetPropertyData
  - kAudioHardwarePropertyDevices
  - kAudioDevicePropertyStreamConfiguration
  
- [ ] Day 3-4: 实现音频流枚举
  - 枚举所有音频设备
  - 获取设备音频流信息
  - 识别进程音频流
  
- [ ] Day 5-7: 构建 PoC
  - 捕获单个应用音频流
  - 应用简单增益
  - 验证技术可行性

**交付物**:
- `AudioStreamCapture.swift` - 音频流捕获
- `ProcessAudioIdentifier.swift` - 进程音频识别
- 技术验证报告

---

### Week 2: 虚拟设备集成 (10.12 - 10.18)

**目标**: 集成 BlackHole，实现完整音频路由

- [ ] Day 1-2: BlackHole 集成
  - 自动检测 BlackHole 安装
  - 引导用户安装（如未安装）
  - 配置虚拟设备参数
  
- [ ] Day 3-4: 音频路由管理器
  - 实现 `AudioDeviceRouter.swift`
  - 切换系统默认输出到 BlackHole
  - 保存用户原始设备设置
  
- [ ] Day 5-7: 音频流路由
  - 从 BlackHole 捕获所有应用音频
  - 路由到真实硬件输出
  - 处理设备切换场景

**交付物**:
- `AudioDeviceRouter.swift`
- `VirtualDeviceManager.swift`
- 路由测试用例

---

### Week 3: 应用级音量控制 (10.19 - 10.25)

**目标**: 实现核心功能——独立控制每个应用音量

- [ ] Day 1-2: 音频流混合器
  - 实现 `AudioStreamMixer.swift`
  - 多路音频流实时混合
  - 性能优化（延迟 < 10ms）
  
- [ ] Day 3-4: 应用音量控制器
  - 实现 `PerAppVolumeController.swift`
  - 按进程应用独立增益
  - 音量变化实时生效
  
- [ ] Day 5-7: 数据持久化
  - 保存每个应用的音量设置
  - 应用启动时恢复音量
  - 处理应用标识变化

**交付物**:
- `AudioStreamMixer.swift`
- `PerAppVolumeController.swift`
- `VolumeConfigStorage.swift`

---

### Week 4: UI 集成和测试 (10.26 - 11.1)

**目标**: 完整 UI 集成，全面测试

- [ ] Day 1-3: UI 更新
  - 应用列表显示音量滑块
  - 每个应用独立音量控制
  - 实时音量指示器
  - 静音按钮（系统 + 应用级）
  
- [ ] Day 4-5: 完整集成测试
  - 多应用同时播放测试
  - 设备切换测试
  - 性能和稳定性测试
  
- [ ] Day 6-7: 错误处理和边界情况
  - BlackHole 未安装处理
  - 设备断开处理
  - 应用崩溃恢复

**交付物**:
- 更新的 SwiftUI 界面
- 完整测试套件
- 性能测试报告

---

### Week 5-6: 优化和发布 (11.2 - 11.15)

**目标**: 性能优化，准备发布

- [ ] Week 5: 性能优化
  - 降低 CPU 占用
  - 优化内存使用
  - 减少音频延迟
  - 电池影响优化
  
- [ ] Week 6: 文档和发布
  - 更新 README.md
  - 编写用户指南
  - 创建安装向导
  - 准备 v2.0.0 Release

**交付物**:
- 性能优化报告
- v2.0.0 完整文档
- DMG 安装包

---

## 🔧 技术实现细节

### 1. Core Audio HAL 关键 API

```swift
// 枚举音频设备
AudioObjectGetPropertyDataSize(
    kAudioObjectSystemObject,
    &propertyAddress,
    0, nil,
    &propertySize
)

// 获取设备流配置
AudioObjectGetPropertyData(
    deviceID,
    &propertyAddress,
    0, nil,
    &propertySize,
    &streamConfiguration
)

// 监听音频流变化
AudioObjectAddPropertyListener(
    deviceID,
    &propertyAddress,
    audioStreamListener,
    context
)
```

### 2. 进程音频识别

```swift
// 通过 AudioObjectProperty 获取进程信息
kAudioDevicePropertyIOProcStreamUsage
kAudioDevicePropertyDeviceIsRunning

// 关联音频流和进程
struct ProcessAudioStream {
    let processID: pid_t
    let bundleID: String
    let streamID: AudioStreamID
    var volume: Float = 1.0
}
```

### 3. 音频增益应用

```swift
// 使用 Audio Unit 应用增益
AudioUnitSetParameter(
    mixerUnit,
    kMultiChannelMixerParam_Volume,
    kAudioUnitScope_Input,
    busNumber,
    volume,
    0
)
```

---

## 📊 成功标准

### 功能要求
- ✅ 支持至少 10 个应用同时播放
- ✅ 每个应用独立音量控制（0-100%）
- ✅ 音量变化实时生效（延迟 < 100ms）
- ✅ 应用级静音功能
- ✅ 音量设置持久化

### 性能要求
- ✅ CPU 占用 < 5%（播放时）
- ✅ 内存占用 < 100 MB
- ✅ 音频延迟 < 10ms
- ✅ 电池影响 < 2%/小时

### 稳定性要求
- ✅ 7x24 小时稳定运行
- ✅ 无内存泄漏
- ✅ 优雅处理设备切换
- ✅ 应用崩溃不影响音频

---

## ⚠️ 风险和缓解

### 技术风险

**1. Core Audio HAL 复杂度高**
- **风险**: 学习曲线陡峭，可能延期
- **缓解**: Week 1 专注学习和 PoC，尽早验证

**2. 音频延迟问题**
- **风险**: 延迟过高影响用户体验
- **缓解**: 使用硬件缓冲优化，目标 < 10ms

**3. 性能开销**
- **风险**: CPU/内存占用过高
- **缓解**: 分阶段性能测试，持续优化

### 用户体验风险

**4. BlackHole 安装复杂**
- **风险**: 用户放弃安装
- **缓解**: 提供清晰的安装向导，自动化流程

**5. 设备切换中断音频**
- **风险**: 切换设备时音频暂停
- **缓解**: 实现无缝切换，最小化中断时间

---

## 🎯 里程碑

| 里程碑 | 日期 | 交付物 |
|--------|------|--------|
| M1: Core Audio PoC | 10.11 | 音频流捕获 + 验证报告 |
| M2: 虚拟设备集成 | 10.18 | 完整音频路由 |
| M3: 应用音量控制 | 10.25 | 独立音量控制功能 |
| M4: UI 和测试 | 11.1 | 完整功能 + 测试 |
| M5: v2.0.0 发布 | 11.15 | 正式版本 |

---

## 📚 参考资料

### Apple 官方文档
- [Core Audio Overview](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/)
- [Audio Unit Programming Guide](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/AudioUnitProgrammingGuide/)
- [Core Audio HAL Reference](https://developer.apple.com/documentation/coreaudio)

### 开源项目
- [Background Music](https://github.com/kyleneideck/BackgroundMusic) - 应用级音量控制参考
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) - 虚拟音频设备
- [eqMac](https://github.com/bitgapp/eqMac) - 另一个类似项目

### 技术文章
- [Routing Audio on macOS](https://www.objc.io/issues/24-audio/audio-routing/)
- [Core Audio in Swift](https://www.raywenderlich.com/5154-core-audio-tutorial-getting-started)

---

## 💡 替代方案（如果遇到阻塞）

### Plan B: 混合方案
- 保留系统音量控制
- 仅支持特定应用（Spotify、Music.app）
- 使用 Accessibility API 控制

### Plan C: 插件系统
- 提供 SDK 让应用自愿集成
- 社区贡献应用支持
- 逐步扩大覆盖范围

---

**状态**: 🚀 准备开始  
**负责人**: VolumeControl Team  
**更新日期**: 2024-10-04
