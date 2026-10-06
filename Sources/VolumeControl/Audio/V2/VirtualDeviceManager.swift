import Foundation
import CoreAudio

/// 虚拟设备管理器 - 检测和配置 BlackHole
/// Week 2 Day 1-2 交付物
class VirtualDeviceManager {
    
    // MARK: - Properties
    
    private var blackHoleDeviceID: AudioDeviceID?
    private var originalDefaultDevice: AudioDeviceID?
    
    // MARK: - BlackHole Detection
    
    /// 检测 BlackHole 是否已安装
    func detectBlackHole() -> Bool {
        let devices = enumerateAudioDevices()
        
        for deviceID in devices {
            if let name = getDeviceName(deviceID),
               name.contains("BlackHole") {
                blackHoleDeviceID = deviceID
                print("✅ Found BlackHole: \(name) (ID: \(deviceID))")
                return true
            }
        }
        
        print("❌ BlackHole not found")
        return false
    }
    
    /// 获取 BlackHole 设备 ID
    func getBlackHoleDeviceID() -> AudioDeviceID? {
        if blackHoleDeviceID == nil {
            _ = detectBlackHole()
        }
        return blackHoleDeviceID
    }
    
    // MARK: - Device Enumeration
    
    private func enumerateAudioDevices() -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        ) == noErr else {
            return []
        }
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &devices
        ) == noErr else {
            return []
        }
        
        return devices
    }
    
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        
        guard AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &name
        ) == noErr else {
            return nil
        }
        
        return name as String
    }
    
    // MARK: - Device Configuration
    
    /// 获取默认输出设备
    func getDefaultOutputDevice() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        ) == noErr else {
            return nil
        }
        
        return deviceID
    }
    
    /// 设置默认输出设备
    func setDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var mutableDeviceID = deviceID
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            propertySize,
            &mutableDeviceID
        )
        
        if status == noErr {
            print("✅ Set default output device to ID: \(deviceID)")
            return true
        } else {
            print("❌ Failed to set default output device: \(status)")
            return false
        }
    }
    
    /// 切换到 BlackHole
    func switchToBlackHole() -> Bool {
        guard let blackHoleID = getBlackHoleDeviceID() else {
            print("❌ Cannot switch: BlackHole not found")
            return false
        }
        
        // 保存原始默认设备
        originalDefaultDevice = getDefaultOutputDevice()
        
        // 切换到 BlackHole
        return setDefaultOutputDevice(blackHoleID)
    }
    
    /// 恢复原始输出设备
    func restoreOriginalDevice() -> Bool {
        guard let originalID = originalDefaultDevice else {
            print("⚠️  No original device to restore")
            return false
        }
        
        return setDefaultOutputDevice(originalID)
    }
    
    // MARK: - Installation Guide
    
    /// 获取 BlackHole 安装指南
    func getInstallationGuide() -> String {
        return """
        
        📦 BlackHole 安装指南
        
        方法 1: 使用 Homebrew (推荐)
        ────────────────────────────
        brew install blackhole-2ch
        
        方法 2: 手动下载
        ────────────────────────────
        1. 访问: https://github.com/ExistentialAudio/BlackHole/releases
        2. 下载: BlackHole2ch.vX.X.X.pkg
        3. 双击安装
        4. 重启 VolumeControl
        
        验证安装:
        ────────────────────────────
        系统设置 → 声音 → 输出
        应该看到 "BlackHole 2ch"
        
        """
    }
    
    // MARK: - Debug
    
    func printStatus() {
        print("\n=== Virtual Device Manager ===")
        print("BlackHole detected: \(detectBlackHole())")
        
        if let blackHoleID = blackHoleDeviceID,
           let name = getDeviceName(blackHoleID) {
            print("BlackHole: \(name) (ID: \(blackHoleID))")
        }
        
        if let defaultID = getDefaultOutputDevice(),
           let name = getDeviceName(defaultID) {
            print("Default output: \(name) (ID: \(defaultID))")
        }
        
        if let originalID = originalDefaultDevice,
           let name = getDeviceName(originalID) {
            print("Original device: \(name) (ID: \(originalID))")
        }
        
        print("==============================\n")
    }
}
