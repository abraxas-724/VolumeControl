import AppKit
import Foundation

enum AppAudioCapability: Equatable {
    case supported
    case unsupported(String)

    var isSupported: Bool {
        if case .supported = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .supported: return "可调节"
        case .unsupported(let reason): return reason
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
    @Published private(set) var statusMessage = "应用级音量控制正在探测支持情况"

    private let audio = SystemAudioService()
    private var volumeBeforeMute = 0.5

    init() {
        systemVolume = audio.readSystemVolume()
        refresh()
    }

    func refresh() {
        systemVolume = audio.readSystemVolume()
        isMuted = audio.readMuted()
        outputDeviceName = audio.outputDeviceName()
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { application in
                guard let bundleID = application.bundleIdentifier else { return nil }
                return AppVolume(
                    id: bundleID,
                    name: application.localizedName ?? bundleID,
                    icon: application.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                    volume: 1,
                    capability: .unsupported("需要音频会话支持")
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        statusMessage = apps.isEmpty ? "打开应用后点击刷新" : "当前版本正在接入应用级音频控制"
    }

    func commitSystemVolume() {
        audio.writeSystemVolume(systemVolume)
    }

    func toggleMute() {
        if isMuted {
            systemVolume = volumeBeforeMute
            isMuted = false
        } else {
            volumeBeforeMute = max(systemVolume, 0.5)
            systemVolume = 0
            isMuted = true
        }
        commitSystemVolume()
    }

    func setAppVolume(id: String, volume: Double) {
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[index].volume = volume
    }
}

struct SystemAudioService {
    static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    func readSystemVolume() -> Double {
        Double(NSSound.systemVolume)
    }

    func writeSystemVolume(_ value: Double) {
        NSSound.systemVolume = Float(Self.clamped(value))
    }

    func readMuted() -> Bool { false }

    func writeMuted(_ muted: Bool) {
        // NSSound does not expose a public mute setter; Core Audio integration lands in P1.
        _ = muted
    }

    func outputDeviceName() -> String {
        "默认输出设备"
    }
}
