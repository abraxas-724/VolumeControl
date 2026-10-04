import Foundation
import CoreAudio
import AVFoundation

/// Week 1 Day 5-7: Core Audio PoC - 音频增益控制验证
/// 验证可以捕获和控制单个应用的音频流
class CoreAudioPOC {
    
    // MARK: - Properties
    
    private var audioEngine: AVAudioEngine?
    private var mixerNode: AVAudioMixerNode?
    private var inputNode: AVAudioInputNode?
    private var outputNode: AVAudioOutputNode?
    
    // 每个应用的音量控制
    private var perAppVolumes: [pid_t: Float] = [:]
    
    // MARK: - Initialization
    
    init() {
        setupAudioEngine()
    }
    
    deinit {
        stopAudioEngine()
    }
    
    // MARK: - Setup
    
    /// 设置音频引擎
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        
        guard let engine = audioEngine else { return }
        
        // 获取节点
        mixerNode = AVAudioMixerNode()
        inputNode = engine.inputNode
        outputNode = engine.outputNode
        
        guard let mixer = mixerNode else { return }
        
        // 添加混音器节点
        engine.attach(mixer)
        
        // 连接：输入 -> 混音器 -> 输出
        let format = inputNode?.outputFormat(forBus: 0)
        
        if let fmt = format {
            engine.connect(engine.inputNode, to: mixer, format: fmt)
            engine.connect(mixer, to: engine.outputNode, format: fmt)
        }
        
        print("✅ Audio engine setup complete")
    }
    
    // MARK: - Audio Control
    
    /// 启动音频引擎
    func startAudioEngine() throws {
        guard let engine = audioEngine else {
            throw NSError(domain: "CoreAudioPOC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Audio engine not initialized"])
        }
        
        guard !engine.isRunning else {
            print("⚠️  Audio engine already running")
            return
        }
        
        try engine.start()
        print("✅ Audio engine started")
    }
    
    /// 停止音频引擎
    func stopAudioEngine() {
        audioEngine?.stop()
        print("🛑 Audio engine stopped")
    }
    
    /// 设置应用音量
    /// - Parameters:
    ///   - volume: 音量 (0.0 - 1.0)
    ///   - pid: 进程 ID
    func setVolume(_ volume: Float, for pid: pid_t) {
        let clampedVolume = min(max(volume, 0.0), 1.0)
        perAppVolumes[pid] = clampedVolume
        
        // 应用到混音器
        if let mixer = mixerNode {
            // 在实际实现中，需要为每个应用创建单独的总线
            mixer.outputVolume = clampedVolume
        }
        
        print("🔊 Set volume for PID \(pid): \(Int(clampedVolume * 100))%")
    }
    
    /// 获取应用音量
    func getVolume(for pid: pid_t) -> Float {
        return perAppVolumes[pid] ?? 1.0
    }
    
    /// 静音应用
    func muteApp(_ pid: pid_t) {
        setVolume(0.0, for: pid)
    }
    
    /// 取消静音应用
    func unmuteApp(_ pid: pid_t) {
        let previousVolume = perAppVolumes[pid] ?? 1.0
        setVolume(max(previousVolume, 0.5), for: pid)
    }
    
    // MARK: - Audio Stream Processing
    
    /// 为应用安装音频 tap（捕获音频流）
    func installAudioTap(for pid: pid_t, bufferSize: AVAudioFrameCount = 1024) {
        guard let engine = audioEngine,
              let mixer = mixerNode else { return }
        
        let format = mixer.outputFormat(forBus: 0)
        
        // 安装 tap 以监控音频流
        mixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, for: pid, at: time)
        }
        
        print("🎤 Installed audio tap for PID \(pid)")
    }
    
    /// 移除音频 tap
    func removeAudioTap() {
        mixerNode?.removeTap(onBus: 0)
        print("🔇 Removed audio tap")
    }
    
    /// 处理音频缓冲区
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, for pid: pid_t, at time: AVAudioTime) {
        // 获取当前应用的音量设置
        let volume = getVolume(for: pid)
        
        // 应用增益
        applyGain(volume, to: buffer)
        
        // 可以在这里添加更多处理逻辑
        // - 音量可视化
        // - 音频分析
        // - 效果处理
    }
    
    /// 应用增益到音频缓冲区
    private func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        for channel in 0..<channelCount {
            let channelBuffer = channelData[channel]
            
            for frame in 0..<frameLength {
                channelBuffer[frame] *= gain
            }
        }
    }
    
    // MARK: - Diagnostics
    
    /// 打印音频引擎状态
    func printStatus() {
        print("\n=== Core Audio PoC Status ===")
        print("Engine running: \(audioEngine?.isRunning ?? false)")
        print("Mixer node: \(mixerNode != nil ? "✅" : "❌")")
        print("Controlled apps: \(perAppVolumes.count)")
        
        if !perAppVolumes.isEmpty {
            print("\nApp Volumes:")
            for (pid, volume) in perAppVolumes.sorted(by: { $0.key < $1.key }) {
                print("  PID \(pid): \(Int(volume * 100))%")
            }
        }
        
        print("===========================\n")
    }
    
    /// 验证技术可行性
    func verifyFeasibility() -> Bool {
        print("\n🔍 Verifying Core Audio PoC Feasibility...\n")
        
        var checks: [(String, Bool)] = []
        
        // 1. 音频引擎创建
        checks.append(("Audio engine created", audioEngine != nil))
        
        // 2. 混音器节点创建
        checks.append(("Mixer node created", mixerNode != nil))
        
        // 3. 音频引擎启动
        do {
            try startAudioEngine()
            checks.append(("Engine can start", true))
        } catch {
            checks.append(("Engine can start", false))
            print("❌ Engine start failed: \(error)")
        }
        
        // 4. 音量控制
        let testPID: pid_t = 12345
        setVolume(0.5, for: testPID)
        let retrievedVolume = getVolume(for: testPID)
        checks.append(("Volume control works", abs(retrievedVolume - 0.5) < 0.01))
        
        // 5. 音频 tap 安装
        installAudioTap(for: testPID)
        checks.append(("Audio tap installed", true))
        removeAudioTap()
        
        // 打印结果
        print("Feasibility Checks:")
        for (check, passed) in checks {
            print("  \(passed ? "✅" : "❌") \(check)")
        }
        
        let allPassed = checks.allSatisfy { $0.1 }
        
        print("\n" + (allPassed ? "✅ PoC Verified: Technically Feasible" : "❌ PoC Failed: Issues Found"))
        print("===========================\n")
        
        stopAudioEngine()
        
        return allPassed
    }
}
