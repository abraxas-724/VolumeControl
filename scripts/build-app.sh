#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/VolumeControl.app"

swift build -c release --package-path "$ROOT_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/VolumeControl" "$APP_DIR/Contents/MacOS/VolumeControl"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>VolumeControl</string>
    <key>CFBundleExecutable</key>
    <string>VolumeControl</string>
    <key>CFBundleIdentifier</key>
    <string>com.volumecontrol.app</string>
    <key>CFBundleName</key>
    <string>VolumeControl</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>20003</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>捕获您启用的应用音频，应用独立音量和静音后播放到当前输出设备。音频不会录制为文件或上传。</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>音频路由验证需要读取 BlackHole 虚拟音频输入并转发到您选择的输出设备。</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
