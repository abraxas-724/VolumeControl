# VolumeControl DriverKit 开发路线图

> 2026-10-04 核验说明：本文保留早期研究与伪代码，不代表已创建可编译的 DriverKit 项目。AudioDriverKit 虚拟设备路径、客户端/PID 接口与签名权限尚未验证。当前已完成无需驱动的原生 Process Tap 应用音量 beta 及两进程真机验收；扩大兼容性后再评估辅助组件，详见 [当前验证记录](docs/PROCESS_TAP_VALIDATION.md)。


## 项目目标

实现真正的应用级音量控制，通过自定义音频驱动追踪每个应用的音频流。

## 技术方案

### BackgroundMusic 的方法

BackgroundMusic 使用自定义音频驱动（BGMDriver）实现进程级音频控制：

1. **虚拟音频设备**
   - 创建虚拟音频设备（类似 BlackHole）
   - 系统将所有音频输出到此设备

2. **进程音频追踪**（关键）
   - 在驱动层面，每个音频客户端连接时提供 task port
   - 从 task port 获取进程 ID
   - 标记每个音频 buffer 的来源进程

3. **用户空间处理**
   - 驱动将带标记的 buffer 发送到用户空间应用
   - 应用根据进程 ID 应用独立音量
   - 混合后输出到真实音频设备

### 我们的实现：DriverKit

使用现代 DriverKit 框架（而非老式 kext）：

**优势**：
- ✅ 运行在用户空间，更安全
- ✅ Apple 官方推荐
- ✅ 不需要禁用 SIP
- ✅ 系统升级更稳定

**核心框架**：
- AudioDriverKit framework
- IOUserAudioDevice
- IOUserAudioStream

---

## 开发阶段

### 阶段 1: 学习和 PoC（Week 1-2）

**目标**：掌握 DriverKit 并创建最简单的虚拟音频设备

**任务**：
- [ ] 研究 Apple DriverKit 文档
- [ ] 研究 AudioDriverKit API
- [ ] 分析 BackgroundMusic 源码
- [ ] 创建 DriverKit 扩展项目
- [ ] 实现基本的 IOUserAudioDevice
- [ ] 验证设备出现在系统音频设置中

**交付物**：
- 可以在系统中显示的虚拟音频设备
- DriverKit 学习笔记
- 技术可行性报告

**预计时间**：1-2 周

---

### 阶段 2: 进程追踪实现（Week 3-6）

**目标**：在驱动中实现进程音频流追踪

**核心技术**：

1. **音频客户端管理**
   ```cpp
   // 伪代码
   class VCUserAudioDevice : IOUserAudioDevice {
       kern_return_t StartIO(IOUserAudioStartStopFlags flags) override {
           // 获取音频客户端列表
           OSArray* clients = GetAudioClients();
           
           for (auto client : clients) {
               // 获取客户端的 task
               task_t task = client->GetTask();
               
               // 提取进程 ID
               pid_t pid;
               pid_for_task(task, &pid);
               
               // 存储进程信息
               client->SetProcessID(pid);
           }
       }
   }
   ```

2. **音频 Buffer 标记**
   ```cpp
   // 为每个 buffer 添加进程 ID 元数据
   struct AudioBufferWithMetadata {
       AudioBuffer buffer;
       pid_t processID;
       uint64_t timestamp;
   };
   ```

3. **用户空间通信**
   ```cpp
   // 使用 IOConnectCallMethod 发送数据
   kern_return_t SendAudioToUserSpace(AudioBufferWithMetadata* buffer) {
       return IOConnectCallMethod(
           userConnection,
           kMethodSendAudio,
           nullptr, 0,
           buffer, sizeof(*buffer),
           nullptr, nullptr,
           nullptr, nullptr
       );
   }
   ```

**任务**：
- [ ] 实现音频客户端枚举
- [ ] 实现进程 ID 提取
- [ ] 实现 buffer 标记机制
- [ ] 实现驱动 → 用户空间通信
- [ ] 测试进程追踪准确性

**交付物**：
- 可以追踪进程的音频驱动
- 用户空间可以接收带进程 ID 的音频数据

**预计时间**：3-4 周

---

### 阶段 3: 音频处理管道（Week 7-10）

**目标**：在用户空间实现音频处理和输出

**架构**：
```
驱动层:
  应用音频 → VCDriver → 标记进程 ID → 发送到用户空间

用户空间:
  接收音频 → 按进程分组 → 应用音量 → 混合 → 输出到真实设备
```

**任务**：
- [ ] 实现用户空间音频接收
- [ ] 实现按进程 ID 分组
- [ ] 实现独立音量调整
- [ ] 实现音频混合
- [ ] 实现输出到真实设备
- [ ] 处理音频格式转换
- [ ] 处理采样率同步

**交付物**：
- 完整的音频处理管道
- 可以独立控制每个应用音量

**预计时间**：3-4 周

---

### 阶段 4: 应用集成（Week 11-13）

**目标**：集成到 VolumeControl 应用

**任务**：
- [ ] 驱动安装/卸载管理
- [ ] 系统扩展权限请求
- [ ] UI 显示应用音量控制
- [ ] 音量滑块实时控制
- [ ] 配置持久化
- [ ] 错误处理和恢复

**交付物**：
- 完整的用户界面
- 驱动管理功能
- 配置管理

**预计时间**：2-3 周

---

### 阶段 5: 测试和优化（Week 14-16）

**目标**：确保稳定性和性能

**测试项目**：
- [ ] 多应用同时播放
- [ ] 设备热插拔
- [ ] 采样率变化
- [ ] 长时间运行稳定性
- [ ] 内存泄漏检测
- [ ] 性能优化（延迟 <10ms）

**交付物**：
- 稳定的 v2.0 版本
- 测试报告
- 性能报告

**预计时间**：2-3 周

---

## 总时间线

**总计：3-4 个月**

- Week 1-2: 学习和 PoC
- Week 3-6: 进程追踪
- Week 7-10: 音频处理
- Week 11-13: 应用集成
- Week 14-16: 测试优化

---

## 技术挑战

### 挑战 1: DriverKit 学习曲线
- 文档较少
- 示例代码有限
- 需要 C++/ObjC 经验

**解决方案**：
- 研究 Apple 官方示例
- 研究 BackgroundMusic 源码
- 逐步实现，从简单到复杂

### 挑战 2: 进程音频追踪
- 需要理解 Core Audio 内部机制
- 需要正确获取 task port
- 需要处理权限问题

**解决方案**：
- 深入研究 BackgroundMusic 实现
- 参考 IOKit 文档
- 充分测试

### 挑战 3: 音频同步
- 输入和输出时钟不同
- 需要缓冲管理
- 需要避免爆音

**解决方案**：
- 使用时间戳对齐
- 实现自适应缓冲
- 参考 BackgroundMusic 的方法

### 挑战 4: 系统权限
- 需要用户批准系统扩展
- 需要代码签名
- 需要公证

**解决方案**：
- 提供清晰的安装指南
- 使用 Developer ID 签名
- 自动化公证流程

---

## 所需资源

### 开发环境
- ✅ macOS 14+ (已有)
- ✅ Xcode 15+ (已有)
- ⚠️  Apple Developer Account（需要）
- ⚠️  Developer ID Certificate（需要）

### 知识储备
- ✅ Swift 编程
- ✅ Core Audio 基础
- ⚠️  C++/Objective-C（需要学习）
- ⚠️  DriverKit 框架（需要学习）
- ⚠️  IOKit 基础（需要学习）

### 参考资料
- Apple DriverKit Documentation
- Apple AudioDriverKit API Reference
- BackgroundMusic Source Code
- IOKit Fundamentals
- Core Audio Programming Guide

---

## 里程碑

### Milestone 1: PoC 完成
**时间**：Week 2  
**标志**：虚拟音频设备出现在系统设置中

### Milestone 2: 进程追踪工作
**时间**：Week 6  
**标志**：可以识别每个应用的音频流

### Milestone 3: 完整音频路由
**时间**：Week 10  
**标志**：音频可以从驱动流向真实设备

### Milestone 4: 应用级控制实现
**时间**：Week 13  
**标志**：可以独立控制每个应用音量

### Milestone 5: v2.0 发布
**时间**：Week 16  
**标志**：稳定的 v2.0 版本发布

---

## 风险和缓解

### 风险 1: DriverKit 技术难度过高
**概率**：中  
**影响**：高  
**缓解**：
- 从最简单的 PoC 开始
- 逐步增加复杂度
- 充分研究参考资料

### 风险 2: 进程追踪无法实现
**概率**：低  
**影响**：致命  
**缓解**：
- BackgroundMusic 已证明可行
- DriverKit 提供类似 API
- 早期验证技术可行性

### 风险 3: 性能不达标
**概率**：中  
**影响**：中  
**缓解**：
- 使用高效的音频处理算法
- 优化缓冲管理
- 参考 BackgroundMusic 性能优化

### 风险 4: 用户体验问题
**概率**：中  
**影响**：中  
**缓解**：
- 提供清晰的安装指南
- 自动化权限请求
- 友好的错误提示

---

## 双轨并行策略

### 轨道 1: v1.0 立即发布（本周）
- 禁用 v2.0 UI
- 完善 v1.0 文档
- 测试和发布
- **目的**：建立用户基础

### 轨道 2: v2.0 DriverKit 开发（3-4个月）
- 并行进行
- 不影响 v1.0 使用
- 完成后推送重大更新
- **目的**：实现应用级控制

---

## 下一步行动

**立即开始**：
1. ✅ 创建 DriverKit 项目骨架
2. ⏸️  配置项目设置和 entitlements
3. ⏸️  实现最简单的 IOUserAudioDevice
4. ⏸️  验证设备可以在系统中显示

**今天的目标**：
创建项目结构，完成基础配置。

---

## 学习资源

### 官方文档
- [DriverKit Documentation](https://developer.apple.com/documentation/driverkit)
- [AudioDriverKit API](https://developer.apple.com/documentation/audiodriverkit)
- [IOKit Fundamentals](https://developer.apple.com/documentation/iokit)

### 参考项目
- [BackgroundMusic](https://github.com/kyleneideck/BackgroundMusic)
- [BlackHole](https://github.com/ExistentialAudio/BlackHole)

### 技术文章
- WWDC Sessions on DriverKit
- Core Audio Programming Guide
- IOKit Device Driver Design Guidelines

---

## 成功标准

### v2.0 必须实现
- ✅ 独立控制每个应用音量
- ✅ 实时音量调整（延迟 <10ms）
- ✅ 稳定运行（无崩溃）
- ✅ 资源占用合理（<100MB 内存，<5% CPU）

### v2.0 期望实现
- ✅ 应用静音功能
- ✅ 音量预设保存
- ✅ 自动启动和恢复
- ✅ 友好的用户体验

---

*最后更新：2026-01-XX*  
*状态：阶段 1 - 学习和 PoC*
