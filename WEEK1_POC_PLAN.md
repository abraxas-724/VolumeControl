# Week 1: PoC 开发计划

## 目标

验证虚拟音频设备方案的技术可行性。

## Day 1: 环境搭建（今天）

### ✅ 已完成
- [x] 创建 P3 开发分支 `feature/p3-virtual-device`
- [x] 编写详细实施计划文档

### 🔄 进行中
- [ ] 安装 BlackHole 虚拟音频设备

```bash
# 安装 BlackHole
brew install blackhole-2ch

# 验证安装
system_profiler SPAudioDataType | grep -A 5 BlackHole

# 在系统设置中查看设备
open /System/Library/PreferencePanes/Sound.prefPane
```

### 📚 待完成
- [ ] Clone 参考项目
- [ ] 阅读核心代码（2-3 小时）

---

## Day 2-4: PoC 核心开发

### PoC 目标

创建一个最小可行的音频路由示例：
1. 从虚拟设备读取音频
2. 应用音量增益
3. 输出到真实硬件

### PoC 代码结构

```swift
// Sources/VolumeControl/Audio/AudioRoutingPOC.swift
import AVFoundation
import CoreAudio

class AudioRoutingPOC {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    func start() throws {
        // 1. 配置输入：从虚拟设备（BlackHole）读取
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // 2. 配置增益节点
        let gainNode = AVAudioMixerNode()
        gainNode.volume = 0.5 // 测试音量调整
        
        // 3. 配置输出：到真实硬件
        let outputNode = engine.outputNode
        
        // 4. 连接音频节点
        engine.attach(gainNode)
        engine.connect(inputNode, to: gainNode, format: inputFormat)
        engine.connect(gainNode, to: outputNode, format: inputFormat)
        
        // 5. 启动引擎
        try engine.start()
        
        print("✅ 音频路由引擎启动成功")
    }
    
    func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = volume
        print("🔊 音量调整为: \(Int(volume * 100))%")
    }
    
    func stop() {
        engine.stop()
        print("⏹️  音频路由引擎已停止")
    }
    
    func measureLatency() -> TimeInterval {
        // 测量音频延迟
        let inputLatency = engine.inputNode.presentationLatency
        let outputLatency = engine.outputNode.presentationLatency
        return inputLatency + outputLatency
    }
}
```

### PoC 测试程序

```swift
// Tests/VolumeControlTests/AudioRoutingPOCTests.swift
import XCTest
@testable import VolumeControl

final class AudioRoutingPOCTests: XCTestCase {
    func testAudioRoutingBasic() throws {
        let poc = AudioRoutingPOC()
        
        // 启动路由
        try poc.start()
        
        // 测试延迟
        let latency = poc.measureLatency()
        print("音频延迟: \(latency * 1000) ms")
        XCTAssertLessThan(latency, 0.015, "延迟应小于 15ms")
        
        // 测试音量调整
        poc.setVolume(0.3)
        poc.setVolume(0.7)
        poc.setVolume(1.0)
        
        // 运行 5 秒
        sleep(5)
        
        poc.stop()
    }
}
```

### 手动测试步骤

1. **配置系统音频**
   ```
   系统设置 > 声音
   - 输出：选择 BlackHole 2ch
   - 输入：选择 BlackHole 2ch
   ```

2. **播放测试音频**
   - 打开 Safari 播放 YouTube 视频
   - 或使用 `afplay /System/Library/Sounds/Ping.aiff`

3. **运行 PoC 应用**
   ```bash
   swift run VolumeControl
   # 应该能听到声音从 BlackHole 路由到真实扬声器
   ```

4. **测试音量调整**
   - 在 PoC 界面调整音量
   - 验证音量变化实时生效

5. **测量性能**
   ```bash
   # CPU 占用
   top -pid $(pgrep VolumeControl)
   
   # 内存占用
   ps aux | grep VolumeControl
   ```

---

## Day 5: 评审和决策

### PoC 评审清单

#### 功能验证
- [ ] 音频可以从 BlackHole 路由到真实设备
- [ ] 音量调整实时生效
- [ ] 无明显音质损失
- [ ] 多个应用同时播放时正常

#### 性能验证
- [ ] 音频延迟 < 15ms（目标 < 10ms）
- [ ] CPU 占用（空闲）< 1%
- [ ] CPU 占用（播放）< 3%
- [ ] 内存占用 < 50 MB

#### 稳定性验证
- [ ] 运行 1 小时无崩溃
- [ ] 切换输出设备不崩溃
- [ ] 应用启动/退出时音频路由正常

#### 用户体验验证
- [ ] 设备切换流程可接受（< 3 秒）
- [ ] 音频中断时间 < 0.5 秒
- [ ] 错误提示清晰

### 决策矩阵

| 指标 | 目标 | 实测 | 结果 |
|-----|------|------|------|
| 音频延迟 | < 15ms | ____ ms | ☐ Pass ☐ Fail |
| CPU（空闲） | < 1% | ____ % | ☐ Pass ☐ Fail |
| CPU（播放） | < 3% | ____ % | ☐ Pass ☐ Fail |
| 内存占用 | < 50MB | ____ MB | ☐ Pass ☐ Fail |
| 音质损失 | 无 | ____ | ☐ Pass ☐ Fail |
| 稳定性 | 1小时 | ____ | ☐ Pass ☐ Fail |

### 决策标准

**✅ 继续推进** 如果：
- 所有核心指标通过（延迟、CPU、内存）
- 音质无明显损失
- 稳定性可接受
- 技术风险可控

**❌ 放弃 P3** 如果：
- 音频延迟 > 20ms 且无法优化
- CPU 占用 > 5% 影响续航
- 音质明显下降
- 技术实现过于复杂

**⚠️ 需要调整** 如果：
- 部分指标勉强通过
- 需要权衡性能和功能
- 需要简化用户体验

---

## 参考资源

### 必读代码

1. **Background Music - Audio Engine**
   - `BGM_Driver/BGM_Device.cpp` - 虚拟设备实现
   - `BGMApp/BGMApp/Music Players/BGMMusicPlayer.mm` - 音频路由
   - `BGMApp/BGMApp/BGMAudioDeviceManager.mm` - 设备管理

2. **BlackHole - Driver**
   - `BlackHole.driver/Contents/MacOS/BlackHole` - 驱动二进制
   - 查看 Info.plist 了解设备属性

3. **Apple 官方文档**
   - [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)
   - [Core Audio Programming Guide](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/)
   - [Audio Unit Hosting Guide](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/AudioUnitHostingGuide_iOS/)

### 关键概念

1. **音频格式**
   - Sample Rate: 48000 Hz (标准)
   - Channels: 2 (立体声)
   - Bit Depth: 32-bit float
   - Buffer Size: 512 samples (可调整)

2. **延迟计算**
   ```
   总延迟 = 输入延迟 + 处理延迟 + 输出延迟
   输入延迟 = buffer_size / sample_rate
   512 / 48000 = 10.67 ms
   ```

3. **音频图**
   ```
   应用 → 虚拟设备(BlackHole) → AVAudioEngine输入
                                         ↓
                                    增益节点
                                         ↓
                                    混音节点
                                         ↓
                                  真实硬件输出
   ```

---

## 问题和解决方案

### 预期问题

1. **Q: BlackHole 安装失败**
   ```bash
   # 手动安装
   curl -L https://github.com/ExistentialAudio/BlackHole/releases/download/v0.5.0/BlackHole2ch.v0.5.0.pkg -o BlackHole.pkg
   sudo installer -pkg BlackHole.pkg -target /
   ```

2. **Q: 无法访问音频输入**
   - 需要在系统设置中授予麦克风权限
   - Info.plist 添加 `NSMicrophoneUsageDescription`

3. **Q: 音频延迟过高**
   - 减小缓冲区大小：`engine.inputNode.setBufferSize(256)`
   - 使用更高的线程优先级

4. **Q: 音频断断续续**
   - 增大缓冲区：512 或 1024 samples
   - 确保音频线程不被阻塞

5. **Q: 切换设备时崩溃**
   - 在切换前停止引擎
   - 使用设备变化通知优雅处理

---

## 下一步（如果 PoC 成功）

Week 2 准备工作：
- [ ] 设计 AudioDeviceManager 接口
- [ ] 规划进程音频流分离算法
- [ ] 准备单元测试框架
- [ ] 更新项目文档

如果 PoC 失败：
- [ ] 整理失败原因
- [ ] 更新技术方案文档
- [ ] 决定是否尝试备选方案
- [ ] 或直接进入 P4 签名发布
