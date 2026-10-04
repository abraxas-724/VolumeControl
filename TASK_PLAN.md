# VolumeControl v2.0 应用级音量控制 - 任务计划书

**项目目标**: 实现真正的应用级音量控制，能够独立控制每个应用的音量  
**技术方案**: 原生 Core Audio Process Tap 按应用捕获、增益处理与重放
**开发策略**: 已完成原生应用音量 beta；扩大真机覆盖后推进正式发布
**预计时间**: 后续兼容性与发布验收后估算
**创建日期**: 2026-01-XX

---

## 当前执行状态（2026-10-04）

本文件下方的 DriverKit 示例、时间估算和性能勾选保留为早期方案归档，不代表实测完成。当前执行以本节及 [应用音量验证记录](docs/PROCESS_TAP_VALIDATION.md) 为准。

- P0–P2：系统音量、静音、设备状态、应用发现和设置基础继续保留。
- P3：原生 Process Tap 应用音量已实现。每个应用独立启用、音量、静音、停止和设置恢复；只在真实捕获信号、输出回调与原始播放静音状态验证成功后标记支持。
- 实时处理：C11 原子增益与 Float32 DSP，支持 1–2 通道、缓变和有限值校验；不安装驱动、不切换默认输出、不修改系统音量。
- 生命周期：取消、应用退出、设备/格式/进程变化停止控制；清理失败可重试，BlackHole 混合路由与应用控制互斥。
- 验证：单元/模拟测试及两个独立音频进程真机验收通过；独立增益 0.25/约 0.80、静音/恢复、5 秒连续输出、3 次启停和默认输出保持通过。完整结果见验证记录。
- 里程碑：`2.0.0-beta.1`；应用音量需要 macOS 14.2+，最多 8 个应用，真实设备单输出流、无填充原生 Float32。macOS 14.0/14.1 继续提供系统音量。
- P4：本阶段无需 DriverKit 或 Audio Server Plug-in。浏览器/会议应用及蓝牙、睡眠、长时间性能的真机覆盖仍待扩大，覆盖不足时再评估辅助组件。
- P5：Developer ID 签名、公证、新机器安装/升级/卸载验收待完成。本地包为 ad-hoc 签名。
- 旧 BlackHole Task 1.3 的听音、性能和设备矩阵仍未整体验收；该实验回路不是原生应用音量的前置条件。

## 早期方案归档

以下保留原始设计供研究比较；当前开发不按其 DriverKit 日程执行。

## 📋 执行摘要

### 当前状态
- ✅ v1.0 系统音量控制已完成
- ✅ v2.0 技术研究和架构设计已完成
- ✅ BackgroundMusic 原理分析完成
- ✅ DriverKit 学习笔记和路线图已完成
- ⚠️ v2.0 代码存在音频路由回路问题（音频卡在 BlackHole）

### 核心挑战
**待核验的早期假设**: 原文把所有用户空间路径排除，结论过于绝对。Core Audio 已提供 Process Tap API，应先验证其捕获、静音和重放闭环。
- 当前项目的进程枚举尚未接入进程音频捕获
- AVAudioEngine 无法区分音频来源
- BlackHole 接收到的是混合后的音频流

**解决方案**: 使用 DriverKit 开发自定义音频驱动
- 在驱动层面追踪每个音频客户端的进程 ID
- 标记每个音频 buffer 的来源进程
- 发送带标记的 buffer 到用户空间应用
- 应用独立音量后混合输出

### 开发环境
- ✅ macOS 27.0.1
- ✅ Xcode 27.0
- ✅ Swift 5.9+
- ⚠️ Apple Developer Account / 签名权限 / provisioning profile（待核验）

---

## 🎯 第一阶段：音频路由回路修复（Week 1）

### 目标
验证音频处理管道的技术可行性，为 DriverKit 开发打好基础。

### 时间安排
**预计时间**: 1-2 小时（立即开始）  
**完成标准**: 音频可以从 BlackHole 流向真实设备，用户能听到声音

### 详细任务

#### Task 1.1: 修复 AudioDeviceRouter（30分钟）

**文件**: `Sources/VolumeControl/Audio/V2/AudioDeviceRouter.swift`

**问题诊断**:
```
当前流程:
系统音频 → BlackHole → ❌ 卡住（没有输出）

期望流程:
系统音频 → BlackHole → 捕获 → 处理 → 真实设备 ✅
```

**修复内容**:
1. 配置 AVAudioEngine 从 BlackHole 读取音频
2. 使用 `installTap` 捕获音频 buffer
3. 创建到真实音频设备的输出连接
4. 处理音频格式转换（如需要）

**实现要点**:
```swift
class AudioDeviceRouter {
    private var inputEngine: AVAudioEngine?  // 从 BlackHole 读取
    private var outputEngine: AVAudioEngine? // 输出到真实设备
    
    func startRouting() throws {
        // 1. 配置输入引擎（从 BlackHole）
        inputEngine = AVAudioEngine()
        let inputNode = inputEngine!.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // 2. 安装 tap 捕获音频
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { 
            [weak self] buffer, time in
            // 将 buffer 转发到输出
            self?.forwardToOutput(buffer)
        }
        
        // 3. 配置输出引擎（到真实设备）
        outputEngine = AVAudioEngine()
        let outputNode = outputEngine!.outputNode
        
        // 4. 启动引擎
        try inputEngine!.start()
        try outputEngine!.start()
    }
}
```

**验证标准**:
- [ ] 启用 v2.0 后能听到声音
- [ ] 音频延迟 <50ms（可接受）
- [ ] 无爆音、断音

---

#### Task 1.2: 实现音频转发逻辑（30分钟）

**目标**: 将从 BlackHole 捕获的音频正确转发到真实设备

**实现要点**:
```swift
class AudioForwarder {
    private let playerNode = AVAudioPlayerNode()
    
    func forwardBuffer(_ buffer: AVAudioPCMBuffer) {
        // 1. 格式转换（如需要）
        let convertedBuffer = convertFormat(buffer)
        
        // 2. 调度播放
        playerNode.scheduleBuffer(convertedBuffer) {
            // 播放完成回调
        }
        
        // 3. 确保播放器运行
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
}
```

**处理问题**:
- 音频格式不匹配 → 使用 `AVAudioConverter`
- 时钟同步问题 → 使用时间戳对齐
- Buffer 积压 → 监控队列深度

---

#### Task 1.3: 测试和验证（15分钟）

**测试场景**:
1. 播放音乐（Music.app 或 Safari）
2. 启用 v2.0 功能
3. 验证能听到声音
4. 检查音频延迟
5. 测试不同音频格式

**性能指标**:
- CPU 占用: <5%
- 内存占用: <100MB
- 音频延迟: <50ms

**回滚方案**:
如果无法修复，可以暂时禁用 v2.0 功能，保留研究成果。

---

### 第一阶段交付物

- [x] 修复后的 AudioDeviceRouter.swift
- [ ] 真机测试报告（性能数据）
- [x] 技术验证文档（模拟结果和待验收矩阵）
- [ ] 第一阶段验收完成后的里程碑 tag（本次仅提交路由修复代码）

### 第一阶段成功标准

- ✅ 音频可以从 BlackHole 流向真实设备
- ✅ 用户能听到声音，无明显延迟
- ✅ 系统稳定，无崩溃
- ✅ 为 DriverKit 开发奠定基础

---

## 🚀 第二阶段：DriverKit 驱动开发（Week 2-16）

### 总体目标
开发自定义音频驱动，实现真正的应用级音量控制。

### 时间安排
**总时间**: 3-4 个月  
**开始时间**: 第一阶段完成后  
**里程碑**: 5 个关键里程碑

---

## Phase 2.1: DriverKit 学习和 PoC（Week 2-3）

### 目标
掌握 DriverKit 框架，创建最简单的虚拟音频设备。

### 时间安排
**预计时间**: 2 周  
**里程碑**: M1 - PoC 完成

### 详细任务

#### Task 2.1.1: DriverKit 环境准备（Day 1）

**检查清单**:
- [ ] Apple Developer Account（DriverKit 所需权限和 profile 待核验）
- [ ] Xcode 27.0 已安装 ✅
- [ ] macOS 27.0.1 ✅
- [ ] 理解 DriverKit 权限模型

**学习资源**:
- Apple DriverKit Documentation
- AudioDriverKit API Reference
- WWDC Sessions on DriverKit
- BackgroundMusic 源码分析

**输出**:
- 学习笔记更新
- 环境配置文档

---

#### Task 2.1.2: 创建 DriverKit 扩展项目（Day 2）

**步骤**:
1. 在 Xcode 中打开 VolumeControl 项目
2. File → New → Target
3. 选择 "DriverKit" → "System Extension"
4. 配置:
   - Product Name: `VolumeControlDriver`
   - Bundle Identifier: `com.volumecontrol.driver`
   - Team: 选择开发团队

**生成的文件**:
```
VolumeControlDriver/
├── VolumeControlDriver.cpp      # 驱动主类
├── VolumeControlDriver.h        # 头文件
├── Info.plist                   # 驱动配置
├── Entitlements.plist           # 权限配置
└── module.modulemap             # 模块定义
```

**配置 Entitlements**:
```xml
<key>com.apple.developer.driverkit</key>
<true/>
<key>com.apple.developer.driverkit.family.audio</key>
<true/>
<key>com.apple.developer.driverkit.transport.audio</key>
<true/>
```

**配置 Info.plist**:
```xml
<key>IOKitPersonalities</key>
<dict>
    <key>VolumeControlAudioDriver</key>
    <dict>
        <key>CFBundleIdentifier</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
        <key>IOClass</key>
        <string>IOUserAudioDevice</string>
        <key>IOProviderClass</key>
        <string>IOAudioDevice</string>
        <key>IOUserClass</key>
        <string>VCUserAudioDevice</string>
    </dict>
</dict>
```

---

#### Task 2.1.3: 实现最简单的虚拟音频设备（Day 3-5）

**目标**: 创建一个可以在系统中显示的虚拟音频设备

**实现 VCUserAudioDevice**:
```cpp
// VCUserAudioDevice.h
#include <AudioDriverKit/AudioDriverKit.h>

class VCUserAudioDevice : public IOUserAudioDevice {
public:
    virtual kern_return_t Start(IOService* provider) LOCALONLY;
    virtual kern_return_t Stop(IOService* provider) LOCALONLY;
    
    virtual kern_return_t StartIO(
        IOUserAudioStartStopFlags flags
    ) LOCALONLY;
    
    virtual kern_return_t StopIO(
        IOUserAudioStartStopFlags flags
    ) LOCALONLY;
    
private:
    kern_return_t ConfigureAudioStreams();
};
```

**实现 Start 方法**:
```cpp
// VCUserAudioDevice.cpp
kern_return_t VCUserAudioDevice::Start(IOService* provider) {
    kern_return_t ret;
    
    // 1. 调用父类 Start
    ret = super::Start(provider);
    if (ret != kIOReturnSuccess) {
        return ret;
    }
    
    // 2. 配置设备属性
    SetDeviceName("VolumeControl Audio Device");
    SetManufacturerName("VolumeControl");
    SetDeviceUID("VCDevice-001");
    
    // 3. 配置音频流
    ret = ConfigureAudioStreams();
    if (ret != kIOReturnSuccess) {
        return ret;
    }
    
    return kIOReturnSuccess;
}

kern_return_t VCUserAudioDevice::ConfigureAudioStreams() {
    // 配置输出流（立体声，48kHz，Float32）
    IOUserAudioStreamBasicDescription format;
    format.mSampleRate = 48000.0;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 32;
    format.mBytesPerFrame = 8;
    format.mFramesPerPacket = 1;
    format.mBytesPerPacket = 8;
    
    // 创建输出流
    IOUserAudioStream* outputStream;
    kern_return_t ret = CreateOutputStream(
        &outputStream,
        kIOUserAudioStreamDirectionOutput,
        &format
    );
    
    return ret;
}
```

**验证**:
- [ ] 编译成功
- [ ] 驱动可以加载
- [ ] 设备出现在"系统设置 → 声音 → 输出"
- [ ] 设备名称显示为"VolumeControl Audio Device"

---

#### Task 2.1.4: 测试 PoC（Day 6-7）

**测试步骤**:
1. 编译驱动扩展
2. 在 Xcode 中运行主应用
3. 系统会提示批准系统扩展
4. 批准后检查音频设备列表

**验证清单**:
- [ ] 驱动成功加载
- [ ] 设备显示在系统音频设置中
- [ ] 可以选择该设备作为输出
- [ ] 无崩溃和错误

**文档输出**:
- PoC 测试报告
- 遇到的问题和解决方案
- 技术可行性确认

**Milestone 1 完成**: 虚拟音频设备 PoC ✅

---

## Phase 2.2: 进程音频追踪实现（Week 4-7）

### 目标
在驱动中实现进程音频流追踪，这是应用级控制的核心。

### 时间安排
**预计时间**: 4 周  
**里程碑**: M2 - 进程追踪工作

### 核心技术

#### 关键原理
```
当应用连接到音频设备时，驱动会收到客户端连接事件：

IOUserAudioDevice::HandleClientAdded(IOUserAudioClient* client)
{
    // 1. 获取客户端的 task port
    task_t clientTask = client->GetClientTask();
    
    // 2. 从 task port 提取进程 ID
    pid_t pid;
    kern_return_t ret = pid_for_task(clientTask, &pid);
    
    // 3. 存储 客户端 → 进程ID 的映射
    clientToProcessMap[client] = pid;
}
```

### 详细任务

#### Task 2.2.1: 实现客户端管理（Week 4）

**实现客户端追踪**:
```cpp
class VCUserAudioDevice : public IOUserAudioDevice {
private:
    // 客户端 → 进程ID 映射
    OSDictionary* clientToProcessMap;
    
    // 进程ID → 客户端列表 映射
    OSDictionary* processToClientsMap;
    
public:
    virtual kern_return_t HandleClientAdded(
        IOUserAudioClient* client
    ) LOCALONLY;
    
    virtual kern_return_t HandleClientRemoved(
        IOUserAudioClient* client
    ) LOCALONLY;
    
    pid_t GetProcessIDForClient(IOUserAudioClient* client);
};

kern_return_t VCUserAudioDevice::HandleClientAdded(
    IOUserAudioClient* client
) {
    // 1. 获取客户端 task
    task_t task = client->GetClientTask();
    if (task == TASK_NULL) {
        return kIOReturnError;
    }
    
    // 2. 提取进程 ID
    pid_t pid;
    kern_return_t ret = pid_for_task(task, &pid);
    if (ret != KERN_SUCCESS) {
        os_log_error(log, "Failed to get PID: %d", ret);
        return kIOReturnError;
    }
    
    // 3. 存储映射
    OSNumber* pidNumber = OSNumber::withNumber(pid, 32);
    clientToProcessMap->setObject(client, pidNumber);
    
    os_log_info(log, "Client added: PID=%d", pid);
    
    return kIOReturnSuccess;
}
```

**验证**:
- [ ] 可以正确获取进程 ID
- [ ] 客户端连接/断开都被追踪
- [ ] 映射关系正确维护

---

#### Task 2.2.2: 实现音频 Buffer 标记（Week 5）

**定义带元数据的 Buffer**:
```cpp
struct AudioBufferWithMetadata {
    AudioBuffer audioBuffer;     // 音频数据
    pid_t processID;             // 来源进程 ID
    uint64_t timestamp;          // 时间戳
    uint32_t frameCount;         // 帧数
    uint32_t channelCount;       // 通道数
};
```

**在音频处理中标记 Buffer**:
```cpp
kern_return_t VCUserAudioDevice::ProcessAudioBuffer(
    IOUserAudioBufferList* bufferList,
    IOUserAudioClient* client
) {
    // 1. 获取该客户端的进程 ID
    pid_t pid = GetProcessIDForClient(client);
    
    // 2. 创建带元数据的 buffer
    AudioBufferWithMetadata metaBuffer;
    metaBuffer.audioBuffer = bufferList->mBuffers[0];
    metaBuffer.processID = pid;
    metaBuffer.timestamp = mach_absolute_time();
    metaBuffer.frameCount = bufferList->mBuffers[0].mDataByteSize / 8;
    metaBuffer.channelCount = 2;
    
    // 3. 发送到用户空间
    SendBufferToUserSpace(&metaBuffer);
    
    return kIOReturnSuccess;
}
```

---

#### Task 2.2.3: 实现驱动 ↔ 用户空间通信（Week 6-7）

**创建 User Client**:
```cpp
// VCUserClient.h
class VCUserClient : public IOUserClient {
public:
    virtual kern_return_t ExternalMethod(
        uint64_t selector,
        IOUserClientMethodArguments* args,
        const IOUserClientMethodDispatch* dispatch,
        OSObject* target,
        void* reference
    ) LOCALONLY;
    
    kern_return_t SendAudioBuffer(AudioBufferWithMetadata* buffer);
};
```

**用户空间接收**:
```swift
// DriverCommunicator.swift
class DriverCommunicator {
    private var connection: io_connect_t = 0
    
    func connect() -> Bool {
        // 1. 查找驱动服务
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("VCUserAudioDevice")
        )
        
        guard service != 0 else { return false }
        
        // 2. 打开连接
        let ret = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        
        return ret == KERN_SUCCESS
    }
    
    func receiveAudioBuffer() -> AudioBufferWithMetadata? {
        var buffer = AudioBufferWithMetadata()
        var size = MemoryLayout<AudioBufferWithMetadata>.size
        
        let ret = IOConnectCallStructMethod(
            connection,
            kMethodReceiveAudio,  // 方法选择器
            nil, 0,               // 输入
            &buffer, &size        // 输出
        )
        
        return ret == KERN_SUCCESS ? buffer : nil
    }
}
```

**验证**:
- [ ] 驱动可以发送数据到用户空间
- [ ] 应用可以接收带进程 ID 的音频数据
- [ ] 数据传输性能满足要求（<10ms）

**Milestone 2 完成**: 进程追踪功能工作 ✅

---

## Phase 2.3: 音频处理管道（Week 8-11）

### 目标
在用户空间实现完整的音频处理：接收 → 分组 → 应用音量 → 混合 → 输出

### 时间安排
**预计时间**: 4 周  
**里程碑**: M3 - 完整音频路由

### 详细任务

#### Task 2.3.1: 实现音频接收器（Week 8）

```swift
class AudioReceiver {
    private let communicator = DriverCommunicator()
    private var isRunning = false
    private let processingQueue = DispatchQueue(
        label: "com.volumecontrol.audio.receiver",
        qos: .userInteractive
    )
    
    func start() {
        guard communicator.connect() else {
            print("Failed to connect to driver")
            return
        }
        
        isRunning = true
        
        processingQueue.async { [weak self] in
            self?.receiveLoop()
        }
    }
    
    private func receiveLoop() {
        while isRunning {
            if let buffer = communicator.receiveAudioBuffer() {
                // 转发到处理器
                AudioProcessor.shared.process(buffer)
            }
        }
    }
}
```

---

#### Task 2.3.2: 实现按进程分组和音量控制（Week 9）

```swift
class AudioProcessor {
    static let shared = AudioProcessor()
    
    // 每个进程的音量设置
    private var appVolumes: [pid_t: Float] = [:]
    
    // 按进程缓冲
    private var processBuffers: [pid_t: [AudioBufferWithMetadata]] = [:]
    
    func process(_ buffer: AudioBufferWithMetadata) {
        let pid = buffer.processID
        
        // 1. 获取该进程的音量设置
        let volume = appVolumes[pid] ?? 1.0
        
        // 2. 应用音量
        var processedBuffer = buffer
        applyVolume(&processedBuffer, volume)
        
        // 3. 添加到进程缓冲
        processBuffers[pid, default: []].append(processedBuffer)
        
        // 4. 如果所有进程都准备好，触发混合
        if shouldMix() {
            mixAndOutput()
        }
    }
    
    private func applyVolume(
        _ buffer: inout AudioBufferWithMetadata,
        _ volume: Float
    ) {
        let samples = buffer.audioBuffer.mData
            .assumingMemoryBound(to: Float.self)
        let count = Int(buffer.frameCount * buffer.channelCount)
        
        // 使用 vDSP 加速
        var volumeScalar = volume
        vDSP_vsmul(samples, 1, &volumeScalar, samples, 1, vDSP_Length(count))
    }
    
    func setVolume(forProcess pid: pid_t, volume: Float) {
        appVolumes[pid] = volume
    }
}
```

---

#### Task 2.3.3: 实现音频混合器（Week 10）

```swift
class AudioMixer {
    func mix(_ buffers: [AudioBufferWithMetadata]) -> AVAudioPCMBuffer? {
        guard !buffers.isEmpty else { return nil }
        
        // 1. 创建输出 buffer
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 48000,
            channels: 2
        )!
        
        let frameLength = buffers[0].frameCount
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameLength
        ) else {
            return nil
        }
        
        outputBuffer.frameLength = frameLength
        
        // 2. 混合所有 buffer
        let outputSamples = outputBuffer.floatChannelData!
        
        for buffer in buffers {
            let inputSamples = buffer.audioBuffer.mData
                .assumingMemoryBound(to: Float.self)
            
            let count = Int(frameLength * 2) // 立体声
            
            // 使用 vDSP 加速混合
            vDSP_vadd(
                outputSamples[0], 1,
                inputSamples, 1,
                outputSamples[0], 1,
                vDSP_Length(count)
            )
        }
        
        return outputBuffer
    }
}
```

---

#### Task 2.3.4: 实现输出到真实设备（Week 11）

```swift
class AudioOutput {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    func start() throws {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 48000,
            channels: 2
        )!
        
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        try engine.start()
        playerNode.play()
    }
    
    func output(_ buffer: AVAudioPCMBuffer) {
        playerNode.scheduleBuffer(buffer) {
            // Buffer 播放完成
        }
    }
}
```

**验证**:
- [ ] 音频可以从驱动流向真实设备
- [ ] 可以独立控制每个应用音量
- [ ] 音频同步正常，无爆音
- [ ] 性能满足要求

**Milestone 3 完成**: 完整音频路由 ✅

---

## Phase 2.4: 应用集成和 UI（Week 12-13）

### 目标
将驱动功能集成到 VolumeControl 应用，实现用户界面。

### 时间安排
**预计时间**: 2 周  
**里程碑**: M4 - 应用级控制实现

### 详细任务

#### Task 2.4.1: 驱动管理器（Week 12 Day 1-2）

```swift
class DriverManager: ObservableObject {
    @Published var isDriverInstalled = false
    @Published var isDriverRunning = false
    
    func checkDriverStatus() {
        // 检查驱动是否安装
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("VCUserAudioDevice")
        )
        
        isDriverInstalled = service != 0
        IOObjectRelease(service)
    }
    
    func installDriver() {
        // 使用 SystemExtensions framework 安装
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.volumecontrol.driver",
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
}
```

---

#### Task 2.4.2: 更新 VolumeControlModel（Week 12 Day 3-5）

```swift
@MainActor
class VolumeControlModel: ObservableObject {
    // 现有属性...
    
    // v2.0 驱动相关
    @Published var isV2Enabled = false
    @Published var driverStatus: DriverStatus = .notInstalled
    
    private let driverManager = DriverManager()
    private let audioProcessor = AudioProcessor.shared
    
    func enableV2() {
        guard driverManager.isDriverInstalled else {
            // 提示安装驱动
            showDriverInstallGuide()
            return
        }
        
        // 启动音频接收
        AudioReceiver.shared.start()
        AudioOutput.shared.start()
        
        isV2Enabled = true
    }
    
    func setAppVolume(pid: pid_t, volume: Float) {
        audioProcessor.setVolume(forProcess: pid, volume: volume)
    }
}
```

---

#### Task 2.4.3: 实现应用音量 UI（Week 13）

```swift
struct AppVolumeControlView: View {
    @ObservedObject var model: VolumeControlModel
    let app: AudioApp
    
    @State private var volume: Float = 1.0
    
    var body: some View {
        HStack(spacing: 12) {
            // 应用图标
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                // 应用名称
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                
                // 音量滑块
                HStack(spacing: 8) {
                    Slider(value: $volume, in: 0...1)
                        .onChange(of: volume) { newValue in
                            model.setAppVolume(pid: app.pid, volume: newValue)
                        }
                    
                    // 音量百分比
                    Text("\(Int(volume * 100))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 35)
                }
            }
            
            // 静音按钮
            Button(action: toggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundColor(isMuted ? .red : .primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}
```

**验证**:
- [ ] 驱动安装流程正常
- [ ] UI 显示所有播放音频的应用
- [ ] 音量滑块实时控制
- [ ] 静音按钮工作正常

**Milestone 4 完成**: 应用级控制实现 ✅

---

## Phase 2.5: 测试和优化（Week 14-16）

### 目标
确保系统稳定性和性能，准备日常使用。

### 时间安排
**预计时间**: 3 周  
**里程碑**: M5 - v2.0 发布

### 详细任务

#### Task 2.5.1: 功能测试（Week 14）

**测试矩阵**:

| 场景 | 测试项 | 通过标准 |
|------|--------|---------|
| 单应用 | Music.app 播放 | 音量控制正常 |
| 多应用 | Music + Safari | 独立控制正常 |
| 设备切换 | 插拔耳机 | 自动适应 |
| 长时间运行 | 连续播放 8 小时 | 无崩溃，无内存泄漏 |
| 应用启动 | 新应用开始播放 | 自动检测 |
| 应用退出 | 应用停止播放 | 正确清理 |
| 重启 | 系统重启 | 设置恢复 |

**性能测试**:
- CPU 占用: <5%
- 内存占用: <100MB
- 音频延迟: <10ms
- 响应时间: <100ms

---

#### Task 2.5.2: 稳定性测试（Week 15）

**压力测试**:
- 同时播放 10 个应用
- 快速切换音量
- 频繁插拔设备
- 驱动重启

**异常测试**:
- 驱动崩溃恢复
- 音频设备断开
- 系统休眠唤醒
- 采样率突变

**内存测试**:
- 运行 Instruments 检测泄漏
- 长时间内存增长分析
- Buffer 管理验证

---

#### Task 2.5.3: 性能优化（Week 16）

**优化方向**:
1. 音频处理优化
   - 使用 vDSP 加速
   - 优化 buffer 管理
   - 减少内存拷贝

2. 延迟优化
   - 调整 buffer 大小
   - 优化时间戳对齐
   - 减少线程切换

3. 资源占用优化
   - 降低 CPU 使用
   - 优化内存分配
   - 减少系统调用

**优化目标**:
- 音频延迟: 从 <50ms 优化到 <10ms
- CPU 占用: 从 <5% 优化到 <3%
- 内存占用: 保持 <100MB

---

#### Task 2.5.4: 文档完善（Week 16）

**用户文档**:
- 安装指南
- 使用说明
- 常见问题
- 故障排除

**开发文档**:
- 架构设计
- API 文档
- 调试指南
- 已知问题

**Milestone 5 完成**: v2.0 发布 ✅

---

## 📊 项目跟踪

### 里程碑进度

| 里程碑 | 预计完成时间 | 完成标志 | 状态 |
|--------|-------------|---------|------|
| M0: 音频回路修复 | Week 1 | 音频正常输出 | ⏸️ 待开始 |
| M1: PoC 完成 | Week 3 | 虚拟设备显示 | ⏸️ 待开始 |
| M2: 进程追踪 | Week 7 | 可识别应用音频 | ⏸️ 待开始 |
| M3: 完整路由 | Week 11 | 音频完整流转 | ⏸️ 待开始 |
| M4: 应用集成 | Week 13 | UI 完整可用 | ⏸️ 待开始 |
| M5: v2.0 发布 | Week 16 | 稳定可用 | ⏸️ 待开始 |

### 每周检查点

**每周五检查**:
- 本周完成的任务
- 遇到的问题和解决方案
- 下周计划
- 风险评估

---

## ⚠️ 风险管理

### 已识别风险

| 风险 | 概率 | 影响 | 缓解措施 | 状态 |
|------|------|------|---------|------|
| DriverKit 学习曲线陡峭 | 中 | 高 | 充分研究，逐步实现 | 监控中 |
| 进程追踪无法实现 | 低 | 致命 | BackgroundMusic 已验证 | 已缓解 |
| 音频延迟过高 | 中 | 中 | 优化 buffer 管理 | 监控中 |
| 系统稳定性问题 | 中 | 高 | 充分测试，谨慎推进 | 监控中 |
| 开发时间超预期 | 中 | 中 | 分阶段交付，降低范围 | 监控中 |

### 应急方案

**如果进度严重落后**:
- 优先完成核心功能（进程追踪 + 音量控制）
- 推迟优化和完善
- 先发布 beta 版本

**如果遇到技术瓶颈**:
- 深入研究 BackgroundMusic 源码
- 寻求社区帮助
- 考虑替代方案

---

## 📈 成功标准

### 第一阶段成功标准（音频回路）
- ✅ 音频可以从 BlackHole 流向真实设备
- ✅ 延迟 <50ms，无爆音
- ✅ 系统稳定运行

### 第二阶段成功标准（DriverKit）
- ✅ 虚拟音频设备正常工作
- ✅ 可以追踪每个应用的音频流
- ✅ 可以独立控制每个应用音量
- ✅ 音频延迟 <10ms
- ✅ CPU 占用 <5%
- ✅ 内存占用 <100MB
- ✅ 长时间运行稳定

### 最终验收标准
- ✅ 可以同时控制 10+ 个应用
- ✅ 响应流畅，无明显延迟
- ✅ 稳定运行，无崩溃
- ✅ 满足日常使用需求

---

## 📚 参考资料

### 技术文档
- [Apple DriverKit Documentation](https://developer.apple.com/documentation/driverkit)
- [AudioDriverKit API](https://developer.apple.com/documentation/audiodriverkit)
- [IOKit Fundamentals](https://developer.apple.com/documentation/iokit)
- [Core Audio Programming Guide](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/)

### 参考项目
- [BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic) - 主要参考
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) - 虚拟设备参考

### 学习资源
- WWDC Sessions on DriverKit
- WWDC Sessions on Core Audio
- Apple Developer Forums

### 项目文档
- `DRIVERKIT_LEARNING_NOTES.md` - 学习笔记
- `DRIVERKIT_ROADMAP.md` - 详细路线图
- `PRODUCT_TECHNICAL_SOLUTION.md` - 技术方案

---

## 📝 附录

### A. 开发环境配置

**系统要求**:
- macOS 27.0.1+ ✅
- Xcode 27.0+ ✅
- Apple Developer Account（DriverKit 所需权限和 profile 待核验）

**必需工具**:
- Xcode Command Line Tools
- Git
- Homebrew（可选）

### B. Git 工作流

**分支策略**:
- `main`: 稳定版本（v1.0）
- `feature/v2-per-app-volume`: v2.0 开发
- `feature/driverkit-poc`: DriverKit PoC

**提交规范**:
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `test`: 测试相关
- `refactor`: 重构
- `perf`: 性能优化

### C. 关键联系人

**技术支持**:
- Apple Developer Support
- DriverKit Forums
- Core Audio Mailing List

**参考项目作者**:
- BackgroundMusic: @kyleneideck
- BlackHole: @ExistentialAudio

---

## 🎯 下一步行动

### 当前待办

- 逐应用验证 Music、Safari、Chrome 和会议软件，记录音频辅助进程归属和不支持原因。
- 扩大有线/蓝牙设备切换、睡眠唤醒、采样率变化及 Intel / macOS 14.2 真机矩阵。
- 测量端到端延迟、CPU、内存和至少 30 分钟稳定性，不用短时 PCM 验收替代性能指标。
- 配置正式签名、公证和新机器安装流程，再决定稳定版发布时间。

P3 的安装、权限、卸载和回滚见 [应用音量验证记录](docs/PROCESS_TAP_VALIDATION.md)。BlackHole 混合流实验保持独立，历史 DriverKit 接口未经验证。

---

## 📅 更新日志

| 日期 | 版本 | 更新内容 | 作者 |
|------|------|---------|------|
| 2026-01-XX | 1.0 | 初始版本，完整计划 | System |
| 2026-10-04 | 1.1 | 实现 BlackHole 转发与失败恢复；纠正能力误报；真机验收仍待执行 | Codex |
| 2026-10-04 | 1.2 | 完成原生应用音量 beta、两进程真机验收及安全能力门槛；归档旧 DriverKit 路线 | Codex |

---

**项目状态**: 🟡 开发中
**当前阶段**: P3 原生应用音量 beta 完成；扩大兼容性/性能验收与 P5 发布准备
**预计完成**: 覆盖矩阵与正式签名条件确认后估算
**责任人**: 您

---

*本计划书是动态文档，会根据实际进度持续更新。*
