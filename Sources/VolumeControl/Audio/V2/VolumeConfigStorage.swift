import Foundation

/// 音量配置存储 - 持久化应用音量设置
/// Week 3 Day 5-7 交付物
class VolumeConfigStorage {
    
    // MARK: - Properties
    
    private let storageURL: URL
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    init() {
        // 使用 Application Support 目录
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("VolumeControl", isDirectory: true)
        
        // 创建目录
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        storageURL = appDir.appendingPathComponent("app_volumes.json")
        
        print("📁 Storage path: \(storageURL.path)")
    }
    
    // MARK: - Save
    
    /// 保存单个应用配置
    func save(_ config: AppVolumeConfig) {
        var configs = loadAll()
        configs[config.bundleID] = config
        saveAll(configs)
    }
    
    /// 保存所有配置
    func saveAll(_ configs: [String: AppVolumeConfig]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(configs)
            try data.write(to: storageURL)
            
            print("💾 Saved \(configs.count) configurations")
        } catch {
            print("❌ Failed to save configurations: \(error)")
        }
    }
    
    // MARK: - Load
    
    /// 加载所有配置
    func loadAll() -> [String: AppVolumeConfig] {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            return [:]
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let configs = try decoder.decode([String: AppVolumeConfig].self, from: data)
            print("📂 Loaded \(configs.count) configurations")
            return configs
        } catch {
            print("❌ Failed to load configurations: \(error)")
            return [:]
        }
    }
    
    /// 加载单个应用配置
    func load(_ bundleID: String) -> AppVolumeConfig? {
        let configs = loadAll()
        return configs[bundleID]
    }
    
    // MARK: - Delete
    
    /// 删除单个应用配置
    func delete(_ bundleID: String) {
        var configs = loadAll()
        configs.removeValue(forKey: bundleID)
        saveAll(configs)
    }
    
    /// 删除所有配置
    func deleteAll() {
        try? fileManager.removeItem(at: storageURL)
        print("🗑️  Deleted all configurations")
    }
    
    // MARK: - Utilities
    
    /// 获取存储大小
    func getStorageSize() -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: storageURL.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }
    
    /// 打印状态
    func printStatus() {
        let configs = loadAll()
        let size = getStorageSize()
        
        print("\n=== Volume Config Storage ===")
        print("Storage path: \(storageURL.path)")
        print("File exists: \(fileManager.fileExists(atPath: storageURL.path))")
        print("Stored configs: \(configs.count)")
        print("File size: \(size) bytes")
        print("============================\n")
    }
}
