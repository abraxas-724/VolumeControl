# DriverKit 学习笔记

> 2026-10-04 核验说明：本文保留早期研究与伪代码，不代表已创建可编译的 DriverKit 项目。AudioDriverKit 虚拟设备路径、客户端/PID 接口与签名权限尚未验证。下一阶段先评估 Process Tap / Audio Server Plug-in，详见 [当前验证记录](docs/AUDIO_ROUTING_VALIDATION.md#下一阶段技术门槛)。


## 什么是 DriverKit？

DriverKit 是 Apple 在 macOS 10.15+ 引入的现代驱动框架，用于替代传统的内核扩展（kext）。

### 关键特性

1. **用户空间运行**
   - 驱动运行在用户空间，不在内核
   - 更安全，崩溃不会影响系统
   - 更容易调试

2. **现代化 API**
   - 面向对象的 C++ API
   - 与 IOKit 类似但更安全
   - 支持异步操作

3. **系统支持**
   - Apple 官方推荐
   - 长期支持保证
   - 不需要禁用 SIP

### 与 kext 的区别

| 特性 | kext（老式） | DriverKit（现代） |
|------|-------------|-------------------|
| 运行空间 | 内核空间 | 用户空间 |
| 安全性 | 低（可以破坏系统） | 高（隔离运行） |
| 调试 | 困难 | 相对容易 |
| SIP | 需要禁用 | 不需要 |
| 系统支持 | 逐步淘汰 | 官方推荐 |

---

## AudioDriverKit 框架

AudioDriverKit 是 DriverKit 的音频子框架，用于开发音频设备驱动。

### 核心类

1. **IOUserAudioDevice**
   - 音频设备的基类
   - 管理音频流和客户端
   - 处理音频数据

2. **IOUserAudioStream**
   - 音频流对象
   - 输入流或输出流
   - 管理音频格式和缓冲

3. **IOUserAudioEngine**
   - 音频引擎
   - 协调多个流
   - 管理采样率和时钟

### 典型架构

```
IOUserAudioDevice
  ├─ IOUserAudioEngine
  │   ├─ IOUserAudioStream (Output)
  │   └─ IOUserAudioStream (Input)
  └─ 客户端管理
```

---

## BackgroundMusic 技术分析

### 核心原理

BackgroundMusic 使用自定义音频驱动（BGMDriver）实现应用级音量控制：

1. **虚拟音频设备**
   ```
   系统应用 → Core Audio → BGMDriver (虚拟设备)
   ```

2. **进程音频追踪**（关键创新）
   ```cpp
   // 伪代码：BGMDriver 如何追踪进程
   IOReturn BGMDevice::performAudioEngineStart() {
       // 获取所有音频客户端
       OSArray* clients = getAudioClients();
       
       for (auto client : clients) {
           // 获取客户端的 task port
           task_t task = client->getClientTask();
           
           // 从 task 提取进程 ID
           pid_t pid;
           pid_for_task(task, &pid);
           
           // 存储进程信息
           clientProcessMap[client] = pid;
       }
   }
   ```

3. **音频 Buffer 标记**
   ```cpp
   // 在混合音频时标记来源
   void BGMDevice::mixOutputSamples() {
       for (auto client : audioClients) {
           pid_t pid = clientProcessMap[client];
           AudioBuffer* buffer = client->getBuffer();
           
           // 标记这个 buffer 的来源进程
           buffer->metadata.processID = pid;
           
           // 发送到用户空间应用
           sendBufferToUserSpace(buffer);
       }
   }
   ```

4. **用户空间处理**
   ```swift
   // BGMApp 接收并处理
   func receiveAudioBuffer(_ buffer: AudioBufferWithMetadata) {
       let pid = buffer.processID
       let volume = appVolumes[pid] ?? 1.0
       
       // 应用独立音量
       applyVolume(buffer, volume)
       
       // 混合后输出到真实设备
       outputToRealDevice(buffer)
   }
   ```

### 关键技术点

#### 1. 进程 ID 获取

Core Audio 驱动层面，每个音频客户端连接时会提供 task port：

```cpp
// IOAudioEngine 回调
kern_return_t IOAudioEngine::addAudioStream(
    IOAudioStream *audioStream
) {
    // 获取客户端 task
    task_t clientTask = getCurrentTask();
    
    // 提取进程 ID
    pid_t pid;
    pid_for_task(clientTask, &pid);
    
    // 存储映射关系
    streamToProcessMap[audioStream] = pid;
}
```

#### 2. 音频 Buffer 管理

需要为每个 buffer 附加元数据：

```cpp
struct AudioBufferWithMetadata {
    AudioBuffer buffer;      // 音频数据
    pid_t processID;         // 来源进程 ID
    uint64_t timestamp;      // 时间戳
    uint32_t frameCount;     // 帧数
};
```

#### 3. 用户空间通信

使用 IOConnectCallMethod 在驱动和应用之间传递数据：

```cpp
// 驱动端：发送音频到用户空间
kern_return_t SendAudioBuffer(
    IOUserClient* client,
    AudioBufferWithMetadata* buffer
) {
    return IOConnectCallMethod(
        client->getConnection(),
        kMethodSendAudio,           // 方法选择器
        nullptr, 0,                 // 输入标量
        buffer, sizeof(*buffer),    // 输入结构
        nullptr, nullptr,           // 输出标量
        nullptr, nullptr            // 输出结构
    );
}
```

```swift
// 应用端：接收音频
func setupAudioReceiver() {
    IOConnectSetNotificationPort(
        connection,
        0,
        port,
        0
    )
    
    IOConnectCallStructMethod(
        connection,
        kMethodReceiveAudio,
        &buffer,
        &bufferSize
    )
}
```

---

## 我们的实现计划

### 阶段 1: 最简单的虚拟音频设备

目标：创建一个可以在系统中显示的虚拟音频设备

```cpp
// VCUserAudioDevice.h
class VCUserAudioDevice : public IOUserAudioDevice {
public:
    // 初始化
    kern_return_t Start(IOService* provider) override;
    
    // 停止
    kern_return_t Stop(IOService* provider) override;
    
    // 音频 I/O
    kern_return_t StartIO(IOUserAudioStartStopFlags flags) override;
    kern_return_t StopIO(IOUserAudioStartStopFlags flags) override;
};
```

实现步骤：
1. 创建 DriverKit 扩展项目
2. 实现 VCUserAudioDevice 类
3. 配置音频格式（48kHz, Stereo, Float32）
4. 注册设备

验证：设备出现在"系统设置 → 声音 → 输出"中

### 阶段 2: 添加进程追踪

目标：在驱动中追踪每个音频客户端的进程 ID

```cpp
class VCUserAudioDevice : public IOUserAudioDevice {
private:
    // 存储客户端 → 进程 ID 映射
    OSCollectionRef clientProcessMap;
    
    // 追踪新客户端
    kern_return_t HandleNewAudioClient(IOUserAudioClient* client) {
        // 获取客户端 task
        task_t task = client->GetTask();
        
        // 提取进程 ID
        pid_t pid;
        kern_return_t ret = pid_for_task(task, &pid);
        if (ret != KERN_SUCCESS) {
            return ret;
        }
        
        // 存储映射
        clientProcessMap->set(client, pid);
        
        return KERN_SUCCESS;
    }
    
    // 标记音频 buffer
    kern_return_t ProcessAudioBuffer(AudioBuffer* buffer) {
        IOUserAudioClient* client = getCurrentClient();
        pid_t pid = clientProcessMap->get(client);
        
        // 标记 buffer
        buffer->metadata.processID = pid;
        
        return KERN_SUCCESS;
    }
};
```

### 阶段 3: 用户空间通信

目标：将带标记的音频数据发送到应用

驱动端：
```cpp
class VCUserAudioDevice : public IOUserAudioDevice {
    // 发送音频到用户空间
    kern_return_t SendAudioToApp(AudioBufferWithMetadata* buffer) {
        return userClient->SendAudioBuffer(buffer);
    }
};

class VCUserClient : public IOUserClient {
    kern_return_t SendAudioBuffer(AudioBufferWithMetadata* buffer) {
        // 通过共享内存或 IPC 发送
        return sharedMemory->write(buffer);
    }
};
```

应用端：
```swift
class DriverCommunicator {
    private var connection: io_connect_t = 0
    
    func receiveAudio() -> AudioBufferWithMetadata? {
        var buffer = AudioBufferWithMetadata()
        var size = MemoryLayout<AudioBufferWithMetadata>.size
        
        let ret = IOConnectCallStructMethod(
            connection,
            kMethodReceiveAudio,
            nil, 0,
            &buffer, &size
        )
        
        return ret == KERN_SUCCESS ? buffer : nil
    }
}
```

### 阶段 4: 音频处理管道

目标：在应用中处理音频并输出

```swift
class AudioProcessor {
    private let mixer = AudioMixer()
    private let output = AudioOutput()
    
    func processAudio(_ buffer: AudioBufferWithMetadata) {
        let pid = buffer.processID
        let volume = appVolumes[pid] ?? 1.0
        
        // 应用音量
        var processedBuffer = buffer
        applyVolume(&processedBuffer, volume)
        
        // 混合
        mixer.addBuffer(processedBuffer)
        
        // 输出
        if mixer.isReady() {
            let mixed = mixer.mix()
            output.play(mixed)
        }
    }
    
    private func applyVolume(_ buffer: inout AudioBufferWithMetadata, _ volume: Float) {
        let samples = buffer.buffer.samples
        for i in 0..<buffer.buffer.frameCount {
            samples[i] *= volume
        }
    }
}
```

---

## 关键挑战和解决方案

### 挑战 1: DriverKit 文档不足

**问题**：AudioDriverKit 文档较少，示例有限

**解决方案**：
1. 研究 Apple 官方示例（虽然少）
2. 深入分析 BackgroundMusic 源码
3. 使用 `class-dump` 工具分析系统音频驱动
4. 逐步实验和测试

### 挑战 2: 进程 ID 获取

**问题**：如何在驱动层面正确获取进程 ID

**解决方案**：
```cpp
// 方法 1: 从 task port 获取（推荐）
pid_t GetProcessIDFromTask(task_t task) {
    pid_t pid;
    kern_return_t ret = pid_for_task(task, &pid);
    if (ret == KERN_SUCCESS) {
        return pid;
    }
    return -1;
}

// 方法 2: 从 IOAudioClient 获取
pid_t GetProcessIDFromClient(IOUserAudioClient* client) {
    task_t task = client->GetTask();
    return GetProcessIDFromTask(task);
}
```

### 挑战 3: 音频同步

**问题**：输入和输出使用不同时钟，可能导致爆音

**解决方案**：
1. 使用时间戳对齐
2. 实现自适应缓冲
3. 监控缓冲区水位

```cpp
class AudioSynchronizer {
    uint64_t inputTimestamp;
    uint64_t outputTimestamp;
    RingBuffer buffer;
    
    void addInputBuffer(AudioBuffer* input, uint64_t timestamp) {
        inputTimestamp = timestamp;
        buffer.write(input);
        
        // 检查缓冲区水位
        if (buffer.size() > maxSize) {
            // 丢弃最老的数据
            buffer.dropOldest();
        }
    }
    
    AudioBuffer* getOutputBuffer(uint64_t timestamp) {
        outputTimestamp = timestamp;
        
        // 计算延迟
        int64_t delay = outputTimestamp - inputTimestamp;
        
        // 调整缓冲
        if (delay > targetDelay + tolerance) {
            // 输出太慢，跳过一些数据
            buffer.skip(skipFrames);
        } else if (delay < targetDelay - tolerance) {
            // 输出太快，插入静音
            buffer.insertSilence(silenceFrames);
        }
        
        return buffer.read();
    }
};
```

### 挑战 4: 系统权限

**问题**：DriverKit 扩展需要用户批准

**解决方案**：
1. 提供清晰的安装指南
2. 使用 SystemExtensions framework 请求权限
3. 友好的错误提示

```swift
import SystemExtensions

class DriverInstaller: NSObject, OSSystemExtensionRequestDelegate {
    func installDriver() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: "com.volumecontrol.driver",
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    func request(_ request: OSSystemExtensionRequest, 
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            print("✅ 驱动安装成功")
        case .willCompleteAfterReboot:
            print("⚠️  需要重启后生效")
        @unknown default:
            break
        }
    }
    
    func request(_ request: OSSystemExtensionRequest, 
                 didFailWithError error: Error) {
        print("❌ 安装失败: \(error.localizedDescription)")
    }
}
```

---

## 开发环境设置

### 必需工具

1. **Xcode 15+**
   - 包含 DriverKit SDK
   - 代码签名工具

2. **Apple Developer Account**
   - Developer ID Certificate
   - System Extension entitlement

3. **测试设备**
   - macOS 14+ 测试机
   - 最好是独立的测试机（驱动开发风险）

### 项目配置

```xml
<!-- Info.plist -->
<key>IOKitPersonalities</key>
<dict>
    <key>VolumeControlDriver</key>
    <dict>
        <key>CFBundleIdentifier</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
        <key>IOClass</key>
        <string>VCUserAudioDevice</string>
        <key>IOProviderClass</key>
        <string>IOAudioDevice</string>
        <key>IOUserClass</key>
        <string>VCUserAudioDevice</string>
    </dict>
</dict>
```

```xml
<!-- Entitlements -->
<key>com.apple.developer.driverkit</key>
<true/>
<key>com.apple.developer.driverkit.family.audio</key>
<true/>
<key>com.apple.developer.driverkit.transport.hid</key>
<true/>
```

---

## 下一步

1. ✅ 创建 DriverKit 扩展项目
2. ⏸️  实现最简单的虚拟音频设备
3. ⏸️  验证设备显示在系统中
4. ⏸️  添加进程追踪功能
5. ⏸️  实现用户空间通信
6. ⏸️  完整音频处理管道

---

*最后更新：2026-01-XX*  
*当前阶段：学习和准备*
