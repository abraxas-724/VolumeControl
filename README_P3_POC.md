# P3 PoC 快速开始指南

## 当前状态

✅ 已创建 P3 开发分支 `feature/p3-virtual-device`
✅ 已编写 PoC 代码框架
🔄 等待安装 BlackHole 并开始测试

## 下一步操作（按顺序执行）

### 1. 安装 BlackHole（5 分钟）

```bash
# 使用 Homebrew 安装
brew install blackhole-2ch

# 验证安装
system_profiler SPAudioDataType | grep -A 5 BlackHole
```

预期输出：
```
BlackHole 2ch:
  Manufacturer: Existential Audio Inc.
  Output Channels: 2
  Input Channels: 2
```

### 2. 配置系统音频（2 分钟）

```bash
# 打开系统声音设置
open /System/Library/PreferencePanes/Sound.prefPane
```

**手动配置**：
- 输出设备：选择 "BlackHole 2ch"
- 输入设备：选择 "BlackHole 2ch"

⚠️ 注意：配置后系统声音会消失，这是正常的。PoC 会将音频路由回真实扬声器。

### 3. 运行 PoC 测试（2 分钟）

```bash
# 在 VolumeControl 项目目录
cd /Users/abraxas/Projects/VolumeControl

# 运行测试
swift test --filter AudioRoutingPOCTests
```

### 4. 手动验证（5 分钟）

**测试步骤**：

1. **启动 PoC**
   ```bash
   # 将来会有独立的 PoC 可执行文件
   # 现在通过测试来验证
   ```

2. **播放测试音频**
   ```bash
   # 在另一个终端
   afplay /System/Library/Sounds/Ping.aiff
   
   # 或播放在线音频
   open "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
   ```

3. **验证音频路由**
   - ✅ 能听到声音从扬声器播放
   - ✅ 音质正常，无明显失真
   - ✅ 延迟 < 100ms（人耳几乎无感知）

4. **测试音量调整**
   - PoC 测试会自动测试 30%, 70%, 100% 音量
   - 验证音量变化立即生效

### 5. 收集测试数据（10 分钟）

填写 PoC 评审表：

```
PoC 测试结果
─────────────────────────────────────
✅ 功能验证
  [ ] 音频可以从 BlackHole 路由到真实设备
  [ ] 音量调整实时生效
  [ ] 无明显音质损失
  [ ] 延迟可接受

⏱️ 性能指标
  音频延迟: _____ ms (目标 < 15ms)
  CPU 占用: _____ % (目标 < 3%)
  内存占用: _____ MB (目标 < 50MB)
  
🐛 问题记录
  1. _____________________________
  2. _____________________________
  
✅ 决策
  [ ] 继续推进 P3 (Week 2-4)
  [ ] 需要调整方案
  [ ] 放弃 P3，进入 P4
```

## 预期时间线

- **今天下午**：安装 BlackHole，运行基础测试
- **明天**：完善 PoC，测试多种场景
- **Day 3-4**：性能优化和稳定性测试
- **Day 5**：PoC 评审和决策

## 参考项目（可选，供深入研究）

```bash
# Clone 参考项目到单独目录
mkdir -p ~/Projects/Research
cd ~/Projects/Research

git clone https://github.com/kyleneideck/BackgroundMusic.git
git clone https://github.com/ExistentialAudio/BlackHole.git
```

## 故障排除

### Q: BlackHole 安装失败

```bash
# 方法 1: 手动下载安装
curl -L https://github.com/ExistentialAudio/BlackHole/releases/download/v0.5.0/BlackHole2ch.v0.5.0.pkg -o ~/Downloads/BlackHole.pkg
sudo installer -pkg ~/Downloads/BlackHole.pkg -target /
```

### Q: 测试提示权限错误

需要授予麦克风权限：
1. 系统设置 > 隐私与安全性 > 麦克风
2. 找到 Terminal 或 Xcode，勾选允许

### Q: 听不到声音

1. 确认 BlackHole 已设置为默认输出
2. 确认 PoC 测试正在运行
3. 尝试调整系统音量（虽然滑杆可能不响应）

### Q: 恢复正常音频

```bash
# 在系统设置中切换回原来的输出设备
# 或者重启系统
```

## 当前文件清单

```
VolumeControl/
├── Sources/VolumeControl/Audio/
│   └── AudioRoutingPOC.swift           ✅ PoC 核心代码
├── Tests/VolumeControlTests/
│   └── AudioRoutingPOCTests.swift      ✅ PoC 测试
├── P3_SOLUTION_RESEARCH.md             ✅ 技术方案研究
├── P3_IMPLEMENTATION_PLAN.md           ✅ 4周实施计划
├── WEEK1_POC_PLAN.md                   ✅ Week 1 详细计划
└── README_P3_POC.md                    ✅ 本文件
```

## 联系和反馈

PoC 测试完成后：
1. 填写测试结果表
2. 记录遇到的问题
3. 评估是否继续推进

成功标准：
- ✅ 音频延迟 < 15ms
- ✅ 内存占用 < 50MB
- ✅ CPU 占用 < 3%
- ✅ 音质无明显损失
- ✅ 稳定运行无崩溃
