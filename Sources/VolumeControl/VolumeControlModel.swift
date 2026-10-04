import AppKit
import Foundation
import AVFoundation

enum AppAudioCapability: Equatable {
    case supported
    case noAudioSession
    case permissionRequired
    case unsupported(String)

    var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .supported:
            return "可调节"
        case .noAudioSession:
            return "未检测到音频输出"
        case .permissionRequired:
            return "需要音频权限"
        case .unsupported(let reason):
            return reason
        }
    }
}

struct AppVolume: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage
    var volume: Double
    var capability: AppAudioCapability

    static func == (lhs: AppVolume, rhs: AppVolume) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.volume == rhs.volume && lhs.capability == rhs.capability
    }
}

@MainActor
final class VolumeControlModel: ObservableObject {
    @Published var systemVolume: Double
    @Published private(set) var isMuted = false
    @Published private(set) var apps: [AppVolume] = []
    @Published private(set) var outputDeviceName = "默认输出设备"
    @Published private(set) var statusMessage = "正在探测音频状态"
    @Published private(set) var isV2Enabled = false
    @Published private(set) var blackHoleAvailable = false

    private let audio: any AudioService
    private let applicationProvider: any ApplicationProvider
    private var deviceMonitor: AudioDeviceMonitor?
    
    // v2.0 components
    var virtualDeviceManager: VirtualDeviceManager?
    private var audioRouter: AudioDeviceRouter?
    private var audioMixer: AudioStreamMixer?
    private var volumeController: PerAppVolumeController?
    private var volumeStorage: VolumeConfigStorage?

    init(
        audio: any AudioService = CoreAudioService(),
        applicationProvider: any ApplicationProvider = WorkspaceApplicationProvider()
    ) {
        self.audio = audio
        self.applicationProvider = applicationProvider
        systemVolume = 0
        deviceMonitor = nil
        deviceMonitor = AudioDeviceMonitor { [weak self] in
            self?.refresh()
        }
        
        // Initialize v2.0 components
        initializeV2Components()
        
        refresh()
    }
    
    private func initializeV2Components() {
        virtualDeviceManager = VirtualDeviceManager()
        blackHoleAvailable = virtualDeviceManager?.detectBlackHole() ?? false
        
        if blackHoleAvailable {
            audioRouter = AudioDeviceRouter()
            audioMixer = AudioStreamMixer()
            volumeStorage = VolumeConfigStorage()
            
            if let mixer = audioMixer, let storage = volumeStorage {
                volumeController = PerAppVolumeController(mixer: mixer, storage: storage)
            }
            
            statusMessage = "✅ v2.0 应用级音量控制已就绪"
        } else {
            statusMessage = "⚠️ 需要安装 BlackHole 以启用应用级音量控制"
        }
    }

    func refresh() {
        let audioError = refreshSystemAudio()
        let discovered = applicationProvider.applications(excluding: Bundle.main.bundleIdentifier)
        apps = discovered.map { application in
            let capability: AppAudioCapability
            
            // v2.0: Check if we can control this app
            if isV2Enabled && blackHoleAvailable {
                switch application.audioSessionStatus {
                case .detected:
                    capability = .supported
                case .notDetected:
                    capability = .noAudioSession
                case .unavailable(let reason):
                    capability = .unsupported("无法检测音频会话：\(reason)")
                }
            } else {
                // v1.0: Can't control apps without v2.0
                switch application.audioSessionStatus {
                case .detected:
                    capability = .unsupported("需要启用 v2.0 功能")
                case .notDetected:
                    capability = .noAudioSession
                case .unavailable(let reason):
                    capability = .unsupported("无法检测音频会话：\(reason)")
                }
            }
            
            // Restore saved volume for this app
            let savedVolume: Double
            if let controller = volumeController {
                savedVolume = Double(controller.getVolume(forApp: application.bundleID))
            } else {
                savedVolume = 1.0
            }
            
            return AppVolume(
                id: "\(application.bundleID):\(application.processID)",
                name: application.name,
                icon: application.icon,
                volume: savedVolume,
                capability: capability
            )
        }
        if let audioError {
            statusMessage = audioError
        } else if apps.isEmpty {
            statusMessage = "打开应用后点击刷新"
        } else {
            let supportedCount = apps.filter { $0.capability.isSupported }.count
            if isV2Enabled && supportedCount > 0 {
                statusMessage = "已发现 \(apps.count) 个应用，其中 \(supportedCount) 个可控制音量"
            } else {
                statusMessage = "已发现 \(apps.count) 个运行中的应用"
            }
        }
    }

    func refreshLoop() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    func commitSystemVolume() {
        do {
            try audio.writeSystemVolume(systemVolume)
            statusMessage = "系统音量已更新"
        } catch {
            statusMessage = error.localizedDescription
            systemVolume = (try? audio.readSystemVolume()) ?? systemVolume
        }
    }

    func toggleMute() {
        do {
            try audio.writeMuted(!isMuted)
            isMuted.toggle()
            statusMessage = isMuted ? "系统已静音" : "已取消静音"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setAppVolume(id: String, volume: Double) {
        guard let index = apps.firstIndex(where: { $0.id == id }), apps[index].capability.isSupported else { return }
        let clampedVolume = Self.clamped(volume)
        apps[index].volume = clampedVolume
        
        // v2.0: Apply volume to mixer
        if isV2Enabled, let controller = volumeController {
            let parts = id.split(separator: ":")
            if parts.count == 2,
               let bundleID = parts.first.map(String.init),
               let pidString = parts.last.map(String.init),
               let pid = pid_t(pidString) {
                controller.setVolume(Float(clampedVolume), forApp: bundleID, pid: pid)
                statusMessage = "\(apps[index].name) 音量: \(Int(clampedVolume * 100))%"
            }
        }
    }
    
    func toggleAppMute(id: String) {
        guard let index = apps.firstIndex(where: { $0.id == id }), apps[index].capability.isSupported else { return }
        
        if isV2Enabled, let controller = volumeController {
            let parts = id.split(separator: ":")
            if parts.count == 2,
               let bundleID = parts.first.map(String.init),
               let pidString = parts.last.map(String.init),
               let pid = pid_t(pidString) {
                let isMuted = controller.isMuted(forApp: bundleID)
                if isMuted {
                    controller.unmuteApp(bundleID, pid: pid)
                    statusMessage = "\(apps[index].name) 已取消静音"
                } else {
                    controller.muteApp(bundleID, pid: pid)
                    statusMessage = "\(apps[index].name) 已静音"
                }
            }
        }
    }
    
    func enableV2() {
        guard blackHoleAvailable else {
            statusMessage = "⚠️ 需要先安装 BlackHole"
            return
        }
        
        do {
            if let router = audioRouter {
                try router.startRouting()
                isV2Enabled = true
                statusMessage = "✅ v2.0 应用级音量控制已启用"
                refresh()
            }
        } catch {
            statusMessage = "❌ 启用失败: \(error.localizedDescription)"
        }
    }
    
    func disableV2() {
        audioRouter?.stopRouting()
        isV2Enabled = false
        statusMessage = "v2.0 功能已禁用"
        refresh()
    }
    
    func installBlackHole() {
        if let manager = virtualDeviceManager {
            statusMessage = manager.getInstallationGuide()
        }
    }

    private func refreshSystemAudio() -> String? {
        do {
            outputDeviceName = try audio.outputDeviceName()
        } catch {
            outputDeviceName = "输出设备不可用"
            return error.localizedDescription
        }

        do {
            systemVolume = Self.clamped(try audio.readSystemVolume())
            isMuted = try audio.readMuted()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
