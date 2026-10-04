import AVFoundation
import CoreAudio
import Foundation

/// Proof of Concept: 虚拟音频设备路由验证
/// 
/// 此类用于验证以下技术可行性：
/// 1. 从虚拟设备（BlackHole）读取音频
/// 2. 应用音量增益控制
/// 3. 输出到真实硬件设备
/// 4. 测量音频延迟和性能
class AudioRoutingPOC {
    private let engine = AVAudioEngine()
    private var isRunning = false
    
    enum POCError: LocalizedError {
        case engineNotStarted
        case invalidFormat
        case deviceNotAvailable(String)
        
        var errorDescription: String? {
            switch self {
            case .engineNotStarted:
                return "音频引擎未启动"
            case .invalidFormat:
                return "音频格式不支持"
            case .deviceNotAvailable(let name):
                return "音频设备不可用: \(name)"
            }
        }
    }
    
    /// 启动音频路由引擎
    /// - Throws: POCError 如果启动失败
    func start() throws {
        guard !isRunning else {
            print("⚠️  音频引擎已经在运行")
            return
        }
        
        // 1. 获取输入节点（从虚拟设备读取）
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        print("📥 输入设备: \(inputNode.name ?? "Unknown")")
        print("📊 输入格式: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")
        
        // 2. 创建增益节点用于音量控制
        let gainNode = AVAudioMixerNode()
        gainNode.volume = 0.5 // 初始音量 50%
        engine.attach(gainNode)
        
        // 3. 获取输出节点（到真实硬件）
        let outputNode = engine.outputNode
        print("📤 输出设备: \(outputNode.name ?? "Unknown")")
        
        // 4. 连接音频图：输入 → 增益 → 输出
        engine.connect(inputNode, to: gainNode, format: inputFormat)
        engine.connect(gainNode, to: outputNode, format: inputFormat)
        
        // 5. 准备和启动引擎
        engine.prepare()
        try engine.start()
        
        isRunning = true
        print("✅ 音频路由引擎启动成功")
    }
    
    /// 停止音频路由引擎
    func stop() {
        guard isRunning else {
            print("⚠️  音频引擎未运行")
            return
        }
        
        engine.stop()
        isRunning = false
        print("⏹️  音频路由引擎已停止")
    }
    
    /// 设置主音量
    /// - Parameter volume: 音量值 (0.0 - 1.0)
    func setVolume(_ volume: Float) {
        let clampedVolume = min(max(volume, 0.0), 1.0)
        engine.mainMixerNode.outputVolume = clampedVolume
        print("🔊 音量调整为: \(Int(clampedVolume * 100))%")
    }
    
    /// 测量音频延迟
    /// - Returns: 总延迟（秒）
    func measureLatency() -> TimeInterval {
        let inputLatency = engine.inputNode.presentationLatency
        let outputLatency = engine.outputNode.presentationLatency
        let totalLatency = inputLatency + outputLatency
        
        print("⏱️  输入延迟: \(inputLatency * 1000) ms")
        print("⏱️  输出延迟: \(outputLatency * 1000) ms")
        print("⏱️  总延迟: \(totalLatency * 1000) ms")
        
        return totalLatency
    }
    
    /// 获取当前性能指标
    func getPerformanceMetrics() -> (cpu: Float, memory: UInt64) {
        // 简单的性能指标收集
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return (0, 0)
        }
        
        let memory = info.resident_size
        print("💾 内存占用: \(memory / 1024 / 1024) MB")
        
        return (0, memory)
    }
    
    /// 检查虚拟设备是否存在
    /// - Parameter deviceName: 设备名称（例如 "BlackHole 2ch"）
    /// - Returns: 设备ID，如果不存在返回 nil
    static func detectVirtualDevice(named deviceName: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize) == noErr else {
            return nil
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &dataSize, &devices) == noErr else {
            return nil
        }
        
        // 查找指定名称的设备
        for deviceID in devices {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            
            if AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name) == noErr,
               let deviceNameCF = name?.takeUnretainedValue() as String?,
               deviceNameCF == deviceName {
                print("✅ 找到虚拟设备: \(deviceName) (ID: \(deviceID))")
                return deviceID
            }
        }
        
        print("❌ 未找到虚拟设备: \(deviceName)")
        return nil
    }
}
