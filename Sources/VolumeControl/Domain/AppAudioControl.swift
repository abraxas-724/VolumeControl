import Foundation
import CoreAudio

struct AppAudioTarget: Hashable {
    let bundleID: String
    let processID: pid_t
    var id: String { "\(bundleID):\(processID)" }
}

struct AppAudioPreferences: Codable, Equatable {
    var volume: Float = 1
    var isMuted = false
    var isEnabled = false
    var gain: Float { isMuted ? 0 : volume }

    init(volume: Float = 1, isMuted: Bool = false, isEnabled: Bool = false) {
        self.volume = volume
        self.isMuted = isMuted
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey { case volume, isMuted, isEnabled }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        volume = try values.decode(Float.self, forKey: .volume)
        isMuted = try values.decode(Bool.self, forKey: .isMuted)
        // 旧版仅保存音量；不能由旧音量值推断用户同意自动捕获。
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    }

    static func validatedVolume(_ value: Float) throws -> Float {
        guard value.isFinite else { throw AppAudioError.invalidVolume }
        return min(max(value, 0), 1)
    }
}

enum AppAudioError: LocalizedError, Equatable {
    case unavailable(String)
    case noSession
    case permissionRequired
    case unverifiedSignal
    case invalidVolume
    case operation(String, OSStatus)
    case cleanup(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .noSession: return "未找到该应用的音频进程，请先播放音频"
        case .permissionRequired: return "需要系统音频录制权限，请在系统设置 → 隐私与安全性中允许 VolumeControl"
        case .unverifiedSignal: return "未收到可验证音频：请保持应用播放，并检查系统音频录制权限和输出设备"
        case .invalidVolume: return "应用音量必须为有限数值"
        case .operation(let operation, let status): return "\(operation)失败（OSStatus \(status)）"
        case .cleanup(let reason): return "停止应用音频控制失败：\(reason)"
        }
    }
}

struct AppAudioControlState: Equatable {
    var preferences = AppAudioPreferences()
    var capability: AppAudioCapability = .unsupported("点击启用应用音量")
}

@MainActor
protocol AppAudioControlling: AnyObject {
    var availability: AppAudioCapability { get }
    var isActive: Bool { get }
    var onChange: (() -> Void)? { get set }
    func state(for target: AppAudioTarget) -> AppAudioControlState
    func activate(_ target: AppAudioTarget) async throws
    func deactivate(_ target: AppAudioTarget) throws
    func setVolume(_ value: Float, for target: AppAudioTarget) throws
    func setMuted(_ muted: Bool, for target: AppAudioTarget) throws
    func reconcile(_ targets: Set<AppAudioTarget>)
    func stopAll() throws
    func suspendAll() throws
}

@MainActor
protocol ProcessAudioSession: AnyObject {
    func prepare() async throws
    func apply(_ preferences: AppAudioPreferences)
    func validate() throws
    func close() throws
}

@MainActor
protocol ProcessAudioSessionFactory {
    var availability: AppAudioCapability { get }
    func makeSession(for target: AppAudioTarget) throws -> any ProcessAudioSession
}

protocol AppAudioPreferenceStoring {
    func load(_ bundleID: String) throws -> AppAudioPreferences
    func save(_ preferences: AppAudioPreferences, for bundleID: String) throws
    func enabledBundleIDs() throws -> Set<String>
}
