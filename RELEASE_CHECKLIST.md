# VolumeControl v1.0.0 发布清单

## ✅ 已完成

### 开发
- [x] P0-P2 功能完成
- [x] 8 个单元测试通过
- [x] P3 PoC 评审完成
- [x] 决策：专注 v1.0 系统音量

### 文档
- [x] README.md（专业项目介绍）
- [x] CONTRIBUTING.md（贡献指南）
- [x] CHANGELOG.md（版本历史）
- [x] LICENSE（MIT）
- [x] POC_EVALUATION.md（技术评审）

### 基础设施
- [x] DMG 构建脚本
- [x] GitHub Actions CI
- [x] GitHub Actions Release
- [x] Git tag v1.0.0

### 构建
- [x] Release 构建成功
- [x] DMG 安装包创建
- [x] 所有代码已提交

## 🔄 可选（需要 Apple Developer 账号）

### 签名和公证
- [ ] 申请 Apple Developer ID（$99/年）
- [ ] 配置代码签名证书
- [ ] 签名应用
- [ ] 提交公证
- [ ] 等待公证通过
- [ ] 装订公证票据

### GitHub 发布
- [ ] 推送代码到 GitHub
- [ ] 推送 tag 到 GitHub
- [ ] 创建 GitHub Release
- [ ] 上传 DMG 文件
- [ ] 编写发布说明

## 📋 发布步骤（当您准备好时）

### 1. 推送到 GitHub

```bash
# 添加远程仓库（替换为您的 GitHub 用户名）
git remote add origin https://github.com/yourusername/VolumeControl.git

# 推送 main 分支
git push -u origin main

# 推送所有 tags
git push origin --tags

# 或推送特定 tag
git push origin v1.0.0
```

### 2. 创建 GitHub Release

1. 访问：https://github.com/yourusername/VolumeControl/releases/new
2. 选择 tag：v1.0.0
3. 填写标题：VolumeControl v1.0.0 - Initial Release
4. 复制 CHANGELOG.md 中的发布说明
5. 上传 `VolumeControl-1.0.0.dmg`
6. 点击「Publish release」

### 3. 签名和公证（可选）

如果您有 Apple Developer 账号：

```bash
# 1. 签名应用
codesign --deep --force --verify --verbose \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  VolumeControl.app

# 2. 创建签名的 DMG
./scripts/build-dmg.sh 1.0.0

# 3. 提交公证
xcrun notarytool submit VolumeControl-1.0.0.dmg \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password" \
  --wait

# 4. 装订公证票据
xcrun stapler staple VolumeControl-1.0.0.dmg

# 5. 验证
spctl -a -t open --context context:primary-signature -v VolumeControl-1.0.0.dmg
```

## 🎯 发布后任务

- [ ] 在社交媒体宣传
- [ ] 提交到 awesome-macos 列表
- [ ] 回复用户反馈
- [ ] 收集功能建议
- [ ] 规划 v1.1.0

## 📊 成功指标

- 下载量
- GitHub Stars
- Issues 和 PR
- 用户反馈
- Bug 报告率

## 🚀 未来路线图

参见 README.md 中的 Roadmap 部分。

---

当前状态：**✅ 可以发布！**

所有核心工作已完成，随时可以推送到 GitHub 并创建 Release。
签名和公证是可选的，可以在后续版本中添加。
