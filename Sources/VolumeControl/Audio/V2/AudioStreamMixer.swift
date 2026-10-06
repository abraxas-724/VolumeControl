import Foundation
import CoreAudio
import AVFoundation
import Accelerate

/// 音频流混合器 - 混合多个应用的音频流并应用独立增益
/// Week 3 Day 1-2 交付物
class AudioStreamMixer {
    
    // MARK: - Properties
    
    private var audioEngine: AVAudioEngine?
    private var mixerNode: AVAudioMixerNode?
    
    // 每个应用的音频总线
    private var appBuses: [pid_t: AVAudioNodeBus] = [:]
    private var nextBus: AVAudioNodeBus = 0
    
    // 每个应用的音量设置
    private var appVolumes: [pid_t: Float] = [:]
    
    // MARK: - Initialization
    
    init() {
        setupAudioEngine()
    }
    
    deinit {
        stopMixer()
    }
    
    // MARK: - Setup
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        mixerNode = AVAudioMixerNode()
        
        guard let engine = audioEngine,
              let mixer = mixerNode else { return }
        
        engine.attach(mixer)
        
        let format = engine.inputNode.outputFormat(forBus: 0)
        engine.connect(mixer, to: engine.outputNode, format: format)
        
        print("✅ Audio stream mixer initialized")
    }
    
    // MARK: - Mixer Control
    
    /// 启动混合器
    func startMixer() throws {
        guard let engine = audioEngine else {
            throw MixerError.notInitialized
        }
        
        guard !engine.isRunning else {
            print("⚠️  Mixer already running")
            return
        }
        
        try engine.start()
        print("✅ Audio stream mixer started")
    }
    
    /// 停止混合器
    func stopMixer() {
        audioEngine?.stop()
        print("🛑 Audio stream mixer stopped")
    }
    
    // MARK: - App Stream Management
    
    /// 为应用注册音频流
    func registerAppStream(for pid: pid_t) -> AVAudioNodeBus {
        if let existingBus = appBuses[pid] {
            return existingBus
        }
        
        let bus = nextBus
        nextBus += 1
        
        appBuses[pid] = bus
        appVolumes[pid] = 1.0
        
        print("📝 Registered stream for PID \(pid) on bus \(bus)")
        return bus
    }
    
    /// 取消注册应用音频流
    func unregisterAppStream(for pid: pid_t) {
        appBuses.removeValue(forKey: pid)
        appVolumes.removeValue(forKey: pid)
        print("❌ Unregistered stream for PID \(pid)")
    }
    
    // MARK: - Volume Control
    
    /// 设置应用音量
    func setVolume(_ volume: Float, for pid: pid_t) {
        let clampedVolume = min(max(volume, 0.0), 1.0)
        appVolumes[pid] = clampedVolume
        
        guard let bus = appBuses[pid],
              let mixer = mixerNode else { return }
        
        mixer.volume = clampedVolume
        
        print("🔊 Set volume for PID \(pid): \(Int(clampedVolume * 100))%")
    }
    
    /// 获取应用音量
    func getVolume(for pid: pid_t) -> Float {
        return appVolumes[pid] ?? 1.0
    }
    
    /// 静音应用
    func muteApp(_ pid: pid_t) {
        setVolume(0.0, for: pid)
    }
    
    /// 取消静音应用
    func unmuteApp(_ pid: pid_t) {
        let volume = appVolumes[pid] ?? 0.5
        setVolume(max(volume, 0.5), for: pid)
    }
    
    // MARK: - Audio Processing
    
    /// 处理音频流
    func processAudioStream(_ buffer: AVAudioPCMBuffer, for pid: pid_t) {
        let volume = getVolume(for: pid)
        applyGain(volume, to: buffer)
    }
    
    /// 应用增益到音频缓冲区
    private func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        for channel in 0..<channelCount {
            let channelBuffer = channelData[channel]
            
            // 使用 Accelerate 框架优化性能
            var scalarGain = gain
            vDSP_vsmul(channelBuffer, 1, &scalarGain, channelBuffer, 1, vDSP_Length(frameLength))
        }
    }
    
    // MARK: - Status
    
    func printStatus() {
        print("\n=== Audio Stream Mixer ===")
        print("Mixer running: \(audioEngine?.isRunning ?? false)")
        print("Registered apps: \(appBuses.count)")
        
        if !appBuses.isEmpty {
            print("\nApp Streams:")
            for (pid, bus) in appBuses.sorted(by: { $0.key < $1.key }) {
                let volume = getVolume(for: pid)
                print("  PID \(pid) → Bus \(bus): \(Int(volume * 100))%")
            }
        }
        
        print("=========================\n")
    }
    
    // MARK: - Error Types
    
    enum MixerError: LocalizedError {
        case notInitialized
        case startFailed
        
        var errorDescription: String? {
            switch self {
            case .notInitialized:
                return "混合器未初始化"
            case .startFailed:
                return "混合器启动失败"
            }
        }
    }
}
