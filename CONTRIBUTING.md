# Contributing to VolumeControl

感谢你对 VolumeControl 的贡献兴趣！我们欢迎所有形式的贡献。

## 贡献方式

### 报告 Bug

在 [Issues](https://github.com/yourusername/VolumeControl/issues) 页面提交问题时，请包含：

- **macOS 版本**: 例如 macOS 14.0 Sonoma
- **VolumeControl 版本**: 例如 v1.0.0
- **问题描述**: 清晰简洁的描述
- **复现步骤**: 如何触发该问题
- **期望行为**: 应该发生什么
- **实际行为**: 实际发生了什么
- **截图**: 如果适用
- **日志**: 如果有相关错误日志

### 提出功能建议

在 Issues 中创建功能请求时：

- 描述功能的用途和价值
- 说明为什么需要这个功能
- 提供可能的实现思路（可选）
- 考虑是否有替代方案

### 提交代码

1. **Fork 仓库**
   ```bash
   # 在 GitHub 上点击 Fork 按钮
   ```

2. **克隆你的 Fork**
   ```bash
   git clone https://github.com/your-username/VolumeControl.git
   cd VolumeControl
   ```

3. **创建分支**
   ```bash
   git checkout -b feature/your-feature-name
   # 或
   git checkout -b fix/your-bug-fix
   ```

4. **开发**
   - 遵循代码规范（见下文）
   - 编写测试
   - 确保所有测试通过

5. **提交更改**
   ```bash
   git add .
   git commit -m "feat: add amazing feature"
   # 或
   git commit -m "fix: resolve audio device bug"
   ```

6. **推送到你的 Fork**
   ```bash
   git push origin feature/your-feature-name
   ```

7. **创建 Pull Request**
   - 在 GitHub 上打开 Pull Request
   - 填写 PR 模板
   - 等待代码审查

## 代码规范

### Swift 风格指南

遵循 [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)：

```swift
// ✅ 好的示例
func adjustVolume(to level: Float) {
    let clampedLevel = min(max(level, 0.0), 1.0)
    setSystemVolume(clampedLevel)
}

// ❌ 避免
func vol(l: Float) {
    setSystemVolume(l)
}
```

### 命名规范

- **类型**: `UpperCamelCase`
- **变量和函数**: `lowerCamelCase`
- **常量**: `lowerCamelCase` 或 `SCREAMING_SNAKE_CASE`（全局常量）
- **协议**: 描述功能的名词或形容词

### 代码组织

```swift
// 1. Import 语句
import SwiftUI
import CoreAudio

// 2. 类型定义
class AudioService {
    // 3. 类型属性（静态）
    static let shared = AudioService()
    
    // 4. 实例属性
    private var deviceID: AudioDeviceID?
    
    // 5. 初始化器
    init() {
        // ...
    }
    
    // 6. 公共方法
    func getVolume() -> Float {
        // ...
    }
    
    // 7. 私有方法
    private func setupDevice() {
        // ...
    }
}
```

### 注释规范

```swift
/// 获取系统音量
/// - Returns: 0.0 到 1.0 之间的音量值
/// - Throws: AudioError 如果无法获取音量
func getSystemVolume() throws -> Float {
    // 实现细节注释
    let volume = try fetchVolumeFromDevice()
    return volume
}
```

### 错误处理

```swift
// 定义明确的错误类型
enum AudioError: LocalizedError {
    case deviceNotFound
    case permissionDenied
    case invalidVolumeRange(Float)
    
    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "未找到音频设备"
        case .permissionDenied:
            return "没有音频权限"
        case .invalidVolumeRange(let value):
            return "无效的音量值: \(value)"
        }
    }
}
```

## 测试

### 运行测试

```bash
# 运行所有测试
swift test

# 运行特定测试
swift test --filter VolumeControlModelTests

# 查看覆盖率
swift test --enable-code-coverage
```

### 编写测试

```swift
import XCTest
@testable import VolumeControl

final class AudioServiceTests: XCTestCase {
    var sut: AudioService!
    
    override func setUp() {
        super.setUp()
        sut = AudioService()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func testVolumeRange() {
        // Given
        let volume: Float = 0.5
        
        // When
        sut.setVolume(volume)
        let result = sut.getVolume()
        
        // Then
        XCTAssertEqual(result, volume, accuracy: 0.01)
    }
}
```

## Commit 消息规范

遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Type

- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式（不影响功能）
- `refactor`: 重构（不是新功能或 bug 修复）
- `test`: 测试相关
- `chore`: 构建过程或辅助工具

### 示例

```
feat(audio): add volume preset save functionality

Implement the ability to save and restore volume presets.
Users can now save up to 5 volume configurations.

Closes #123
```

## Pull Request 流程

1. **PR 标题**: 遵循 commit 消息规范
2. **描述**: 清楚说明改动内容和原因
3. **截图**: 如果是 UI 改动，提供前后对比
4. **测试**: 确认所有测试通过
5. **文档**: 更新相关文档

### PR 模板

```markdown
## 改动描述
简要描述这个 PR 做了什么

## 改动类型
- [ ] Bug 修复
- [ ] 新功能
- [ ] 重构
- [ ] 文档更新

## 测试
- [ ] 添加了单元测试
- [ ] 所有测试通过
- [ ] 手动测试通过

## 截图（如适用）
添加截图

## 相关 Issue
Closes #123
```

## 开发环境

### 必需

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

### 推荐

- SwiftLint（代码风格检查）
- SwiftFormat（代码格式化）

### 设置开发环境

```bash
# 克隆仓库
git clone https://github.com/yourusername/VolumeControl.git
cd VolumeControl

# 安装依赖（如果有）
swift package resolve

# 打开项目
open Package.swift
```

## 项目结构

```
VolumeControl/
├── Sources/VolumeControl/
│   ├── Presentation/           # UI 层
│   ├── Application/            # 应用服务层
│   ├── Domain/                 # 领域层
│   └── Infrastructure/         # 基础设施层
├── Tests/VolumeControlTests/   # 测试
├── Documentation/              # 文档
└── Scripts/                    # 工具脚本
```

## 发布流程

1. 更新版本号（Package.swift）
2. 更新 CHANGELOG.md
3. 创建 tag: `git tag v1.0.0`
4. 推送 tag: `git push origin v1.0.0`
5. GitHub Actions 自动构建发布

## 需要帮助？

- 📖 查看 [文档](https://github.com/yourusername/VolumeControl/wiki)
- 💬 在 [Discussions](https://github.com/yourusername/VolumeControl/discussions) 提问
- 📧 联系维护者

## 行为准则

请阅读并遵守我们的 [行为准则](CODE_OF_CONDUCT.md)。

---

再次感谢你的贡献！🎉
