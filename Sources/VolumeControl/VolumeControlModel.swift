import AppKit
import Foundation

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

    private let audio: any AudioService
    private let applicationProvider: any ApplicationProvider
    private var deviceMonitor: AudioDeviceMonitor?

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
        refresh()
    }

    func refresh() {
        let audioError = refreshSystemAudio()
        let discovered = applicationProvider.applications(excluding: Bundle.main.bundleIdentifier)
        apps = discovered.map { application in
            let capability: AppAudioCapability
            switch application.audioSessionStatus {
            case .detected:
                capability = .unsupported("系统接口不支持应用增益")
            case .notDetected:
                capability = .noAudioSession
            case .unavailable(let reason):
                capability = .unsupported("无法检测音频会话：\(reason)")
            }
            return AppVolume(
                id: "\(application.bundleID):\(application.processID)",
                name: application.name,
                icon: application.icon,
                volume: 1,
                capability: capability
            )
        }
        if let audioError {
            statusMessage = audioError
        } else if apps.isEmpty {
            statusMessage = "打开应用后点击刷新"
        } else {
            statusMessage = "已发现 \(apps.count) 个运行中的应用"
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
        apps[index].volume = Self.clamped(volume)
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
