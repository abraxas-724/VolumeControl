import Foundation
import CoreAudio

/// 音频流捕获器 - 使用 Core Audio HAL 枚举和捕获音频流
/// Week 1 Day 3-4 交付物
class AudioStreamCapture {
    
    // MARK: - Properties
    
    private var audioDevices: [AudioDeviceID] = []
    
    // MARK: - Initialization
    
    init() {
        enumerateAudioDevices()
    }
    
    // MARK: - Public Methods
    
    /// 枚举所有音频设备
    func enumerateAudioDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        
        // 获取设备列表大小
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            print("Failed to get audio devices size: \(status)")
            return
        }
        
        // 获取设备列表
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        let getStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &devices
        )
        
        guard getStatus == noErr else {
            print("Failed to get audio devices: \(getStatus)")
            return
        }
        
        self.audioDevices = devices
        
        print("Found \(deviceCount) audio devices")
        for device in devices {
            if let name = getDeviceName(device) {
                print("  - Device \(device): \(name)")
            }
        }
    }
    
    /// 获取设备名称
    func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = UInt32(MemoryLayout<CFString>.size)
        var name: CFString = "" as CFString
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &name
        )
        
        guard status == noErr else {
            return nil
        }
        
        return name as String
    }
    
    /// 获取设备的音频流配置
    func getStreamConfiguration(for deviceID: AudioDeviceID) -> AudioBufferList? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        
        // 获取配置大小
        let sizeStatus = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard sizeStatus == noErr else {
            print("Failed to get stream configuration size: \(sizeStatus)")
            return nil
        }
        
        // 分配内存
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        
        // 获取配置
        let getStatus = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            bufferListPointer
        )
        
        guard getStatus == noErr else {
            print("Failed to get stream configuration: \(getStatus)")
            return nil
        }
        
        return bufferListPointer.pointee
    }
    
    /// 检查设备是否正在运行
    func isDeviceRunning(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var isRunning: UInt32 = 0
        var propertySize: UInt32 = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &isRunning
        )
        
        guard status == noErr else {
            return false
        }
        
        return isRunning != 0
    }
    
    /// 获取设备的采样率
    func getSampleRate(for deviceID: AudioDeviceID) -> Float64? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var sampleRate: Float64 = 0
        var propertySize: UInt32 = UInt32(MemoryLayout<Float64>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &sampleRate
        )
        
        guard status == noErr else {
            return nil
        }
        
        return sampleRate
    }
    
    /// 监听音频流变化
    func addStreamListener(for deviceID: AudioDeviceID, callback: @escaping AudioObjectPropertyListenerProc) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectAddPropertyListener(
            deviceID,
            &propertyAddress,
            callback,
            nil
        )
        
        if status != noErr {
            print("Failed to add stream listener: \(status)")
        }
    }
    
    /// 移除音频流监听器
    func removeStreamListener(for deviceID: AudioDeviceID, callback: AudioObjectPropertyListenerProc) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectRemovePropertyListener(
            deviceID,
            &propertyAddress,
            callback,
            nil
        )
        
        if status != noErr {
            print("Failed to remove stream listener: \(status)")
        }
    }
    
    // MARK: - Debug
    
    /// 打印所有音频设备的详细信息
    func printDeviceDetails() {
        print("\n=== Audio Device Details ===")
        for device in audioDevices {
            guard let name = getDeviceName(device) else { continue }
            let isRunning = isDeviceRunning(device)
            let sampleRate = getSampleRate(for: device)
            
            print("\nDevice: \(name) (ID: \(device))")
            print("  Running: \(isRunning)")
            if let rate = sampleRate {
                print("  Sample Rate: \(rate) Hz")
            }
            
            if let config = getStreamConfiguration(for: device) {
                print("  Buffers: \(config.mNumberBuffers)")
            }
        }
        print("===========================\n")
    }
}
