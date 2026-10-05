import AppKit
import Foundation

/// 显式真机验收用内存偏好重复创建模型，验证真实播放检测与自动恢复，不改用户设置。
@MainActor
enum AppAudioRestorationValidationRunner {
    static func run(arguments: [String]) async {
        guard let index = arguments.firstIndex(of: "--verify-remembered-audio"), arguments.count > index + 3,
              let pid = pid_t(arguments[index + 1]) else { NSApplication.shared.terminate(nil); return }
        let target = AppAudioTarget(bundleID: arguments[index + 2], processID: pid)
        let url = URL(fileURLWithPath: arguments[index + 3])
        let storage = RestorationValidationPreferences(bundleID: target.bundleID)
        var report: [String: Any] = ["passed": false]
        var models: [VolumeControlModel] = []
        if #available(macOS 14.2, *) {
            do {
                let original = try CoreAudioService().defaultOutputDevice()
                var frames: [UInt64] = []
                for _ in 0..<2 {
                    let factory = RestorationValidationFactory()
                    let control = ProcessTapVolumeController(factory: factory, storage: storage)
                    let model = VolumeControlModel(monitorDevices: false, appAudio: control)
                    models.append(model)
                    let discovered = WorkspaceApplicationProvider().applications(excluding: Bundle.main.bundleIdentifier).first { $0.bundleID == target.bundleID }
                    report["detectedPID"] = discovered?.processID
                    report["playbackDetected"] = discovered?.isPlayingAudio
                    report["targetStatus"] = model.apps.first { $0.id == target.id }?.capability.label
                    guard discovered?.processID == target.processID, discovered?.isPlayingAudio == true else {
                        throw AppAudioError.unavailable("应用尚未播放，自动恢复正在等待音频输出")
                    }
                    for _ in 0..<650 {
                        if model.apps.contains(where: { $0.id == target.id && $0.capability.isSupported }) { break }
                        if let error = model.lastError { throw AppAudioError.unavailable(error) }
                        try await Task.sleep(nanoseconds: 20_000_000)
                    }
                    guard model.apps.contains(where: { $0.id == target.id && $0.capability.isSupported }),
                          let session = factory.sessions[target] else { throw AppAudioError.unverifiedSignal }
                    try await Task.sleep(nanoseconds: 250_000_000)
                    try session.validate()
                    let levels = try session.levels()
                    guard levels.input > 0, levels.frames > 0, abs(levels.output / levels.input - 1) < 0.02 else {
                        throw AppAudioError.unavailable("自动恢复后原音量转发验证失败")
                    }
                    frames.append(levels.frames)
                    model.suspendAppAudioControl()
                    guard !control.isActive, storage.preferences.isEnabled else { throw AppAudioError.unavailable("退出未释放会话或丢失启用选择") }
                }
                guard try CoreAudioService().defaultOutputDevice() == original else { throw AppAudioError.unavailable("默认输出发生变化") }
                report = ["passed": true, "automaticRestorationCycles": 2, "realPlaybackDetection": true, "unityGainVerified": true, "outputFrames": frames, "enabledChoiceRetained": true, "defaultOutputPreserved": true]
            } catch { report["error"] = error.localizedDescription }
        } else { report["error"] = "需要 macOS 14.2+" }
        models.forEach { $0.suspendAppAudioControl() }
        if let cleanup = models.compactMap(\.lastError).last { report["passed"] = false; report["lastError"] = cleanup }
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic) }
        catch { NSLog("自动恢复验收报告写入失败：%@", error.localizedDescription) }
        NSApplication.shared.terminate(nil)
    }
}

private final class RestorationValidationPreferences: AppAudioPreferenceStoring {
    let bundleID: String
    var preferences = AppAudioPreferences(isEnabled: true)
    init(bundleID: String) { self.bundleID = bundleID }
    func load(_ bundleID: String) throws -> AppAudioPreferences { bundleID == self.bundleID ? preferences : AppAudioPreferences() }
    func save(_ preferences: AppAudioPreferences, for bundleID: String) throws {
        guard bundleID == self.bundleID else { throw AppAudioError.unavailable("验收只能操作指定应用") }
        self.preferences = preferences
    }
    func enabledBundleIDs() throws -> Set<String> { preferences.isEnabled ? [bundleID] : [] }
}

@available(macOS 14.2, *)
@MainActor
private final class RestorationValidationFactory: ProcessAudioSessionFactory {
    var availability: AppAudioCapability { .supported }
    var sessions: [AppAudioTarget: CoreAudioProcessSession] = [:]
    func makeSession(for target: AppAudioTarget) throws -> any ProcessAudioSession {
        let session = CoreAudioProcessSession(target: target)
        sessions[target] = session
        return session
    }
}
