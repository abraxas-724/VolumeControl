import Foundation
import CoreAudio
import AVFoundation

/// 音频设备路由管理器 - 管理音频流路由
/// Week 2 Day 3-4 交付物
class AudioDeviceRouter {
    
    // MARK: - Properties
    
    private let virtualDeviceManager = VirtualDeviceManager()
    private var audioEngine: AVAudioEngine?
    private var isRouting = false
    
    // MARK: - Initialization
    
    init() {
        setupAudioEngine()
    }
    
    deinit {
        stopRouting()
    }
    
    // MARK: - Audio Engine Setup
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        print("✅ Audio engine created for routing")
    }
    
    // MARK: - Routing Control
    
    /// 开始音频路由
    /// BlackHole (虚拟设备) → 音频处理 → 真实硬件
    func startRouting() throws {
        guard !isRouting else {
            print("⚠️  Routing already active")
            return
        }
        
        // 1. 检测 BlackHole
        guard virtualDeviceManager.detectBlackHole() else {
            throw RoutingError.blackHoleNotFound
        }
        
        // 2. 获取 BlackHole 设备 ID
        guard let blackHoleID = virtualDeviceManager.getBlackHoleDeviceID() else {
            throw RoutingError.blackHoleNotFound
        }
        
        // 3. 切换系统输出到 BlackHole
        guard virtualDeviceManager.switchToBlackHole() else {
            throw RoutingError.switchFailed
        }
        
        // 4. 启动音频引擎（从 BlackHole 读取）
        try audioEngine?.start()
        
        isRouting = true
        print("✅ Audio routing started: System → BlackHole → Processing → Output")
    }
    
    /// 停止音频路由
    func stopRouting() {
        guard isRouting else { return }
        
        // 1. 停止音频引擎
        audioEngine?.stop()
        
        // 2. 恢复原始输出设备
        _ = virtualDeviceManager.restoreOriginalDevice()
        
        isRouting = false
        print("🛑 Audio routing stopped")
    }
    
    /// 安装音频处理回调
    func installProcessingTap(callback: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) {
        guard let engine = audioEngine else { return }
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            callback(buffer, time)
        }
        
        print("🎤 Processing tap installed")
    }
    
    /// 移除音频处理回调
    func removeProcessingTap() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        print("🔇 Processing tap removed")
    }
    
    // MARK: - Device Management
    
    /// 检查 BlackHole 是否可用
    func isBlackHoleAvailable() -> Bool {
        return virtualDeviceManager.detectBlackHole()
    }
    
    /// 获取 BlackHole 安装指南
    func getBlackHoleInstallGuide() -> String {
        return virtualDeviceManager.getInstallationGuide()
    }
    
    // MARK: - Status
    
    func printStatus() {
        print("\n=== Audio Device Router ===")
        print("Routing active: \(isRouting)")
        print("BlackHole available: \(isBlackHoleAvailable())")
        print("Audio engine running: \(audioEngine?.isRunning ?? false)")
        virtualDeviceManager.printStatus()
        print("===========================\n")
    }
    
    // MARK: - Error Types
    
    enum RoutingError: LocalizedError {
        case blackHoleNotFound
        case switchFailed
        case engineStartFailed
        
        var errorDescription: String? {
            switch self {
            case .blackHoleNotFound:
                return "BlackHole 虚拟音频设备未安装"
            case .switchFailed:
                return "无法切换到 BlackHole 设备"
            case .engineStartFailed:
                return "音频引擎启动失败"
            }
        }
    }
}
