# P3 应用级音量控制实施计划

> 2026-10-04：本文为早期研究/规划，不能把 BlackHole 混合流按 PID 分离视为可行或已完成，也不能据缺少直接增益属性排除 Process Tap 路径。当前执行状态以 [TASK_PLAN.md](TASK_PLAN.md) 和 [验证记录](docs/AUDIO_ROUTING_VALIDATION.md) 为准。


## 目标

在 VolumeControl 中集成虚拟音频设备，实现所有应用的独立音量控制。

## 技术方案

采用 **Background Music 模式**：
1. 使用 BlackHole 作为虚拟音频设备
2. 开发音频路由管理器自动切换设备
3. 实现按进程 PID 的音频流分离和增益控制
4. 提供安装/卸载流程

## 里程碑和时间线

### 第 1 周：环境搭建和 PoC（Proof of Concept）

**目标**：验证技术可行性

#### Day 1-2: 环境准备
- [ ] 安装 BlackHole 测试环境
- [ ] 研究 Background Music 核心代码
- [ ] 搭建音频开发和调试环境
- [ ] 创建 P3 开发分支

```bash
# 安装 BlackHole
brew install blackhole-2ch

# 验证安装
system_profiler SPAudioDataType | grep BlackHole

# Clone 参考项目
git clone https://github.com/kyleneideck/BackgroundMusic.git
git clone https://github.com/ExistentialAudio/BlackHole.git
```

#### Day 3-4: PoC 开发
- [ ] 实现最小音频路由（虚拟设备 → 真实设备）
- [ ] 验证 AVAudioEngine 可以读取虚拟设备输入
- [ ] 验证可以应用增益并输出到真实硬件
- [ ] 测试音频延迟（目标 < 15ms）

**PoC 成功标准**：
- ✅ 音频可以通过虚拟设备正常播放
- ✅ 可以在路由过程中调整音量
- ✅ 延迟 < 15ms
- ✅ 无明显音质损失

#### Day 5: PoC 评审和决策
- [ ] 整理 PoC 测试结果
- [ ] 评估技术风险和复杂度
- [ ] 决定是否继续全力推进

**决策点**：
- ✅ PoC 成功 → 进入第 2 周全面开发
- ❌ PoC 失败 → 放弃 P3，进入 P4 签名发布

---

### 第 2 周：核心组件开发

**目标**：实现音频路由和增益控制

#### 音频设备管理器（AudioDeviceManager）
- [ ] 枚举所有音频输出设备
- [ ] 检测 BlackHole 虚拟设备
- [ ] 自动切换默认输出设备
- [ ] 保存用户原始设备配置
- [ ] 实现恢复原始设备的逻辑

```swift
protocol AudioDeviceManager {
    func detectVirtualDevice() -> AudioDeviceID?
    func setDefaultOutputDevice(_ deviceID: AudioDeviceID) throws
    func saveCurrentDevice() throws
    func restoreOriginalDevice() throws
    func physicalOutputDevices() -> [AudioDevice]
}
```

#### 音频路由引擎（AudioRoutingEngine）
- [ ] 创建 AVAudioEngine 实例
- [ ] 配置输入节点（虚拟设备）
- [ ] 配置输出节点（真实硬件）
- [ ] 实现音频流回调
- [ ] 处理设备切换和错误恢复

```swift
class AudioRoutingEngine {
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    
    func start(inputDevice: AudioDeviceID, outputDevice: AudioDeviceID) throws
    func stop()
    func handleDeviceChange()
}
```

#### 进程音频流分离器（ProcessAudioSplitter）
- [ ] 从混合音频流中按 PID 分离
- [ ] 为每个进程创建独立的音频节点
- [ ] 应用进程级增益
- [ ] 混合所有处理后的音频流

```swift
class ProcessAudioSplitter {
    private var processNodes: [pid_t: AVAudioMixerNode] = [:]
    
    func createNodeForProcess(_ pid: pid_t) -> AVAudioMixerNode
    func setVolume(_ volume: Float, for pid: pid_t)
    func setMuted(_ muted: Bool, for pid: pid_t)
    func removeNodeForProcess(_ pid: pid_t)
}
```

**第 2 周交付物**：
- ✅ 可以自动切换到虚拟设备
- ✅ 音频可以正常路由和播放
- ✅ 基础的音量调整功能
- ✅ 单元测试覆盖核心逻辑

---

### 第 3 周：UI 集成和用户体验

**目标**：将音频引擎集成到主应用

#### 更新 VolumeControlModel
- [ ] 添加虚拟设备状态管理
- [ ] 集成 AudioRoutingEngine
- [ ] 实现应用音量读写
- [ ] 更新应用能力探测逻辑

```swift
@MainActor
final class VolumeControlModel: ObservableObject {
    private let routingEngine: AudioRoutingEngine?
    @Published private(set) var virtualDeviceEnabled = false
    
    func enableVirtualDevice() async throws
    func disableVirtualDevice() async throws
    func setAppVolume(id: String, volume: Double) async throws
}
```

#### 更新 UI 组件
- [ ] AppVolumeRow 解锁音量控制
- [ ] 添加虚拟设备状态指示
- [ ] 添加"启用应用音量控制"入口
- [ ] 设置页面添加虚拟设备开关

```swift
struct AppVolumeRow: View {
    var body: some View {
        HStack {
            // 应用信息
            if app.capability.isSupported {
                Slider(value: $volume, in: 0...1)  // 现在可用
                Button { model.toggleAppMute(id: app.id) } label: {
                    Image(systemName: app.isMuted ? "speaker.slash" : "speaker.wave.2")
                }
            }
        }
    }
}
```

#### 首次运行向导（OnboardingView）
- [ ] 解释虚拟设备的作用
- [ ] 引导用户批准系统扩展
- [ ] 显示安装步骤和进度
- [ ] 提供跳过选项（保持系统音量模式）

```swift
struct OnboardingView: View {
    var body: some View {
        VStack {
            Text("启用应用音量控制")
            Text("需要安装虚拟音频设备...")
            Button("立即启用") { model.enableVirtualDevice() }
            Button("稍后") { dismiss() }
        }
    }
}
```

**第 3 周交付物**：
- ✅ UI 完全集成音频引擎
- ✅ 用户可以调整应用音量
- ✅ 首次运行体验流畅
- ✅ 可以在系统音量和应用音量模式间切换

---

### 第 4 周：安装流程、签名和测试

**目标**：完善发布准备

#### 安装和卸载流程
- [ ] 编写 BlackHole 自动安装脚本
- [ ] 实现虚拟设备配置向导
- [ ] 编写完整卸载脚本
- [ ] 实现设备恢复和回滚

```bash
# scripts/install-virtual-device.sh
#!/bin/bash
echo "正在安装虚拟音频设备..."
brew install blackhole-2ch
# 配置设备权限
# 设置默认设备
```

```bash
# scripts/uninstall-virtual-device.sh
#!/bin/bash
echo "正在卸载虚拟音频设备..."
# 恢复原始设备
brew uninstall blackhole-2ch
```

#### 签名和公证
- [ ] 配置 Developer ID Application 证书
- [ ] 添加 Hardened Runtime entitlements
- [ ] 配置音频驱动签名（如果自己打包 BlackHole）
- [ ] 集成 notarytool 自动化公证
- [ ] 测试 stapler 装订票据

```xml
<!-- VolumeControl.entitlements -->
<key>com.apple.security.audio</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

#### 错误处理和恢复
- [ ] 虚拟设备断开时的恢复逻辑
- [ ] 音频引擎崩溃重启
- [ ] 设备切换竞态处理
- [ ] 用户友好的错误提示

#### 性能优化
- [ ] 减少音频延迟（< 10ms）
- [ ] 优化 CPU 占用（空闲 < 0.5%）
- [ ] 内存泄漏检测和修复
- [ ] 电池影响测试

#### 真机测试矩阵
- [ ] MacBook Pro (M1/M2/M3)
- [ ] MacBook Air (Intel/M1)
- [ ] 内建扬声器
- [ ] 有线耳机
- [ ] 蓝牙耳机（AirPods）
- [ ] 外接显示器音频
- [ ] USB 音频接口

**第 4 周交付物**：
- ✅ 完整的安装/卸载流程
- ✅ 签名和公证完成
- ✅ 所有测试场景通过
- ✅ 性能指标达标
- ✅ 用户文档完整

---

## 文件结构

```
VolumeControl/
├── Sources/VolumeControl/
│   ├── Audio/                              # 新增音频模块
│   │   ├── AudioDeviceManager.swift        # 设备管理
│   │   ├── AudioRoutingEngine.swift        # 音频路由引擎
│   │   ├── ProcessAudioSplitter.swift      # 进程音频分离
│   │   └── VirtualDeviceInstaller.swift    # 安装助手
│   ├── VolumeControlApp.swift
│   ├── VolumeControlModel.swift            # 更新：集成音频引擎
│   ├── AudioService.swift                  # 保持：系统音量
│   ├── ApplicationDiscovery.swift          # 保持：应用发现
│   └── Views/
│       ├── OnboardingView.swift            # 新增：首次运行向导
│       └── VirtualDeviceSettingsView.swift # 新增：虚拟设备设置
├── Tests/VolumeControlTests/
│   ├── AudioRoutingEngineTests.swift       # 新增
│   └── ProcessAudioSplitterTests.swift     # 新增
├── scripts/
│   ├── install-virtual-device.sh           # 新增
│   └── uninstall-virtual-device.sh         # 新增
└── Docs/
    ├── VirtualDeviceSetup.md               # 新增：用户指南
    └── TroubleShooting.md                  # 新增：故障排除
```

---

## 风险和缓解措施

### 技术风险

1. **PoC 失败**
   - 缓解：第 1 周立即验证，失败则转向放弃方案
   - 回退：保留当前系统音量功能，直接进入 P4

2. **音频延迟过高**
   - 缓解：使用小缓冲区（256 samples）
   - 回退：增大缓冲区牺牲延迟换稳定性

3. **设备切换不稳定**
   - 缓解：完善错误处理和自动恢复
   - 回退：提供手动恢复工具

4. **签名和公证问题**
   - 缓解：提前验证 Developer ID 和公证流程
   - 回退：仅发布 ad-hoc 签名版本（测试版）

### 用户体验风险

1. **用户不理解虚拟设备**
   - 缓解：详细的首次运行向导
   - 提供跳过选项保持简单模式

2. **系统扩展权限批准复杂**
   - 缓解：清晰的步骤说明和截图
   - 提供视频教程

3. **卸载不干净**
   - 缓解：完善的卸载脚本
   - 自动恢复原始设备配置

---

## 质量指标

### 功能完整性
- [ ] 所有应用都可以调整音量
- [ ] 音量调整实时生效（< 100ms）
- [ ] 静音功能正常
- [ ] 设备切换自动恢复
- [ ] 安装和卸载流程完整

### 性能指标
- [ ] 内存占用 < 70 MB
- [ ] CPU 占用（空闲）< 0.5%
- [ ] CPU 占用（播放 5 个应用）< 5%
- [ ] 音频延迟 < 10ms
- [ ] 电池影响 < 1%/小时

### 稳定性指标
- [ ] 无崩溃运行 24 小时
- [ ] 设备切换 100 次无错误
- [ ] 应用启动/退出 100 次状态一致
- [ ] 睡眠唤醒恢复正常

### 测试覆盖率
- [ ] 单元测试覆盖率 > 70%
- [ ] 核心音频逻辑覆盖率 > 90%
- [ ] 真机测试 6 种设备配置

---

## 阶段验收标准

### Week 1 验收
- ✅ PoC 代码可运行
- ✅ 音频延迟 < 15ms
- ✅ 无明显音质损失
- ✅ 决策文档完成

### Week 2 验收
- ✅ AudioDeviceManager 单元测试通过
- ✅ AudioRoutingEngine 可以路由音频
- ✅ 基础音量调整功能可用
- ✅ 代码 review 完成

### Week 3 验收
- ✅ UI 完全集成
- ✅ 用户可以通过界面调整应用音量
- ✅ 首次运行向导可用
- ✅ 设置页面完善

### Week 4 验收
- ✅ 所有测试场景通过
- ✅ 签名和公证完成
- ✅ 性能指标达标
- ✅ 用户文档完整
- ✅ 可以发布 TestFlight 或公开下载

---

## 下一步行动

### 立即执行（今天）
1. [ ] 创建 P3 开发分支
   ```bash
   git checkout -b feature/p3-virtual-device
   ```

2. [ ] 安装 BlackHole 测试环境
   ```bash
   brew install blackhole-2ch
   ```

3. [ ] Clone 参考项目
   ```bash
   cd ~/Projects/Research
   git clone https://github.com/kyleneideck/BackgroundMusic.git
   git clone https://github.com/ExistentialAudio/BlackHole.git
   ```

4. [ ] 阅读核心代码（2-3 小时）
   - Background Music 的音频路由实现
   - BlackHole 的驱动接口
   - AVAudioEngine 的使用模式

### 明天开始
5. [ ] 编写 PoC 代码（Day 1-4）
6. [ ] 测试和评估（Day 5）
7. [ ] 决策是否继续（Day 5 结束前）

---

## 预算和资源

### 开发时间
- PoC：5 天
- 核心开发：5 天
- UI 集成：5 天
- 签名测试：5 天
- **总计：20 工作日（4 周）**

### 外部依赖
- BlackHole（开源，MIT 许可证）
- Apple Developer ID 证书
- 测试设备（MacBook Pro/Air，各种音频设备）

### 文档
- 技术设计文档（已完成）
- 用户安装指南（Week 4）
- 故障排除文档（Week 4）
- API 文档（Week 2-3）

---

## 成功标准

项目成功的标志：
1. ✅ 用户可以调整任意应用的音量
2. ✅ 音频质量和延迟无感知
3. ✅ 安装和使用流程简单
4. ✅ 性能和资源占用在预期范围
5. ✅ 可以签名和公证正式发布

**最终目标**：发布 VolumeControl 1.0，包含完整的应用级音量控制功能。
