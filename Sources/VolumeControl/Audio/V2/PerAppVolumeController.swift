import Foundation

/// 应用音量控制器 - 统一管理所有应用的音量设置
/// Week 3 Day 3-4 交付物
class PerAppVolumeController {
    
    // MARK: - Properties
    
    private let mixer: AudioStreamMixer
    private let storage: VolumeConfigStorage
    
    // 应用音量配置
    private var appConfigs: [String: AppVolumeConfig] = [:]
    
    // MARK: - Initialization
    
    init(mixer: AudioStreamMixer, storage: VolumeConfigStorage) {
        self.mixer = mixer
        self.storage = storage
        loadConfigurations()
    }
    
    // MARK: - Volume Control
    
    /// 设置应用音量
    func setVolume(_ volume: Float, forApp bundleID: String, pid: pid_t) {
        let clampedVolume = min(max(volume, 0.0), 1.0)
        
        // 更新配置
        var config = appConfigs[bundleID] ?? AppVolumeConfig(bundleID: bundleID)
        config.volume = clampedVolume
        config.lastModified = Date()
        appConfigs[bundleID] = config
        
        // 应用到混合器
        mixer.setVolume(clampedVolume, for: pid)
        
        // 持久化
        storage.save(config)
        
        print("🎚️  \(bundleID): \(Int(clampedVolume * 100))%")
    }
    
    /// 获取应用音量
    func getVolume(forApp bundleID: String) -> Float {
        return appConfigs[bundleID]?.volume ?? 1.0
    }
    
    /// 静音应用
    func muteApp(_ bundleID: String, pid: pid_t) {
        setMuted(true, forApp: bundleID, pid: pid)
    }
    
    /// 取消静音应用
    func unmuteApp(_ bundleID: String, pid: pid_t) {
        setMuted(false, forApp: bundleID, pid: pid)
    }
    
    /// 设置静音状态
    func setMuted(_ muted: Bool, forApp bundleID: String, pid: pid_t) {
        var config = appConfigs[bundleID] ?? AppVolumeConfig(bundleID: bundleID)
        config.isMuted = muted
        config.lastModified = Date()
        appConfigs[bundleID] = config
        
        if muted {
            mixer.muteApp(pid)
        } else {
            mixer.unmuteApp(pid)
        }
        
        storage.save(config)
        
        print("\(muted ? "🔇" : "🔊") \(bundleID): \(muted ? "muted" : "unmuted")")
    }
    
    /// 获取静音状态
    func isMuted(forApp bundleID: String) -> Bool {
        return appConfigs[bundleID]?.isMuted ?? false
    }
    
    // MARK: - Configuration Management
    
    /// 加载保存的配置
    private func loadConfigurations() {
        appConfigs = storage.loadAll()
        print("📂 Loaded \(appConfigs.count) app configurations")
    }
    
    /// 重置应用配置
    func resetApp(_ bundleID: String) {
        appConfigs.removeValue(forKey: bundleID)
        storage.delete(bundleID)
        print("🔄 Reset configuration for \(bundleID)")
    }
    
    /// 重置所有配置
    func resetAll() {
        appConfigs.removeAll()
        storage.deleteAll()
        print("🔄 Reset all configurations")
    }
    
    /// 应用启动时恢复音量
    func restoreVolumeForApp(_ bundleID: String, pid: pid_t) {
        if let config = appConfigs[bundleID] {
            mixer.setVolume(config.volume, for: pid)
            
            if config.isMuted {
                mixer.muteApp(pid)
            }
            
            print("♻️  Restored \(bundleID): \(Int(config.volume * 100))%, muted: \(config.isMuted)")
        }
    }
    
    // MARK: - Status
    
    func printStatus() {
        print("\n=== Per-App Volume Controller ===")
        print("Managed apps: \(appConfigs.count)")
        
        if !appConfigs.isEmpty {
            print("\nApp Configurations:")
            for (bundleID, config) in appConfigs.sorted(by: { $0.key < $1.key }) {
                let muteStatus = config.isMuted ? "🔇" : "🔊"
                print("  \(muteStatus) \(bundleID): \(Int(config.volume * 100))%")
            }
        }
        
        print("=================================\n")
    }
}

/// 应用音量配置
struct AppVolumeConfig: Codable {
    let bundleID: String
    var volume: Float = 1.0
    var isMuted: Bool = false
    var lastModified: Date = Date()
}
