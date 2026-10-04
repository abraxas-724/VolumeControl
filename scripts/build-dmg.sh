#!/bin/bash

# VolumeControl DMG 构建脚本
# 使用方法: ./scripts/build-dmg.sh [version]

set -e

VERSION=${1:-"1.0.0"}
APP_NAME="VolumeControl"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
BUILD_DIR=".build/release"
STAGING_DIR=".build/dmg-staging"

echo "🔨 构建 ${APP_NAME} v${VERSION} DMG 安装包..."

# 1. 清理旧文件
echo "🧹 清理旧构建文件..."
rm -rf "${STAGING_DIR}"
rm -f "${DMG_NAME}"

# 2. 构建 Release 版本
echo "⚙️  构建 Release 版本..."
swift build -c release

# 3. 创建 DMG staging 目录
echo "📦 准备 DMG 内容..."
mkdir -p "${STAGING_DIR}"

# 4. 复制应用到 staging 目录
if [ -d "${BUILD_DIR}/${APP_NAME}.app" ]; then
    cp -R "${BUILD_DIR}/${APP_NAME}.app" "${STAGING_DIR}/"
else
    echo "⚠️  未找到 .app 包，创建简单的安装说明"
    mkdir -p "${STAGING_DIR}/${APP_NAME}"
    cp "${BUILD_DIR}/${APP_NAME}" "${STAGING_DIR}/${APP_NAME}/"
    cat > "${STAGING_DIR}/安装说明.txt" << INSTALL
VolumeControl 安装说明
======================

1. 将 ${APP_NAME} 文件夹复制到 /Applications
2. 打开 Applications 文件夹
3. 双击 ${APP_NAME} 运行

首次运行时，如果系统提示"无法打开"，请：
1. 右键点击应用
2. 选择"打开"
3. 在弹出的对话框中点击"打开"

更多信息: https://github.com/yourusername/VolumeControl
INSTALL
fi

# 5. 创建 Applications 快捷方式
ln -s /Applications "${STAGING_DIR}/Applications"

# 6. 复制 README
cp README.md "${STAGING_DIR}/README.txt"

# 7. 创建 DMG
echo "💿 创建 DMG 镜像..."
if command -v create-dmg &> /dev/null; then
    # 使用 create-dmg 工具（需要先安装: brew install create-dmg）
    create-dmg \
        --volname "${APP_NAME}" \
        --window-pos 200 120 \
        --window-size 800 400 \
        --icon-size 100 \
        --app-drop-link 600 185 \
        "${DMG_NAME}" \
        "${STAGING_DIR}"
else
    # 使用 hdiutil（系统自带）
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${STAGING_DIR}" \
        -ov -format UDZO \
        "${DMG_NAME}"
fi

# 8. 清理 staging 目录
echo "🧹 清理临时文件..."
rm -rf "${STAGING_DIR}"

echo "✅ DMG 创建完成: ${DMG_NAME}"
echo "📦 文件大小: $(du -h "${DMG_NAME}" | cut -f1)"
echo ""
echo "🚀 可以发布了！"
