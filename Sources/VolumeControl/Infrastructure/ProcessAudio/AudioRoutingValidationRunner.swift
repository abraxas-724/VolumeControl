import AppKit
import CoreAudio
import Foundation
import Darwin

/// 显式真机验收会临时切换默认输出到 BlackHole，并在完成或失败时恢复。
@MainActor
enum AudioRoutingValidationRunner {
    static func run(arguments: [String]) async {
        guard let index = arguments.firstIndex(of: "--verify-audio-routing"), arguments.count > index + 2 else { NSApplication.shared.terminate(nil); return }
        let reportURL = URL(fileURLWithPath: arguments[index + 1])
        let readyURL = URL(fileURLWithPath: arguments[index + 2])
        var report: [String: Any] = ["passed": false]
        let engine = HALAudioRoutingEngine()
        let router = AudioDeviceRouter(engine: engine)
        var runtimeError: Error?
        router.onFailure = { runtimeError = $0 }
        var original: AudioDeviceID?
        // The shell trap sends SIGTERM on Ctrl-C; restore the default before exiting.
        signal(SIGTERM, SIG_IGN)
        let cancellation = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        cancellation.setEventHandler {
            MainActor.assumeIsolated {
                var cancelled: [String: Any] = ["passed": false, "cancelled": true]
                do {
                    try router.stopRouting()
                    if let original { cancelled["outputRestored"] = try CoreAudioService().defaultOutputDevice() == original }
                } catch { cancelled["cleanupError"] = error.localizedDescription }
                write(cancelled, to: reportURL)
                NSApplication.shared.terminate(nil)
            }
        }
        cancellation.resume()
        defer { cancellation.cancel(); signal(SIGTERM, SIG_DFL) }
        do {
            guard try await AudioInputPermission().requestAccess() else { throw AudioRoutingError.engineFailed("BlackHole 路由没有音频输入权限") }
            original = try CoreAudioService().defaultOutputDevice()
            try router.startRouting()
            try Data().write(to: readyURL)
            for _ in 0..<300 {
                if let runtimeError { throw runtimeError }
                if try engine.levels().hasSignal { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard try engine.levels().hasSignal else { throw AudioRoutingError.engineFailed("未收到 BlackHole 验收信号") }
            let before = try engine.levels()
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if let runtimeError { throw runtimeError }
            try engine.validate()
            let after = try engine.levels()
            guard router.isRouting, after.frames > before.frames, after.input > 0, abs(after.output / after.input - 1) < 0.02 else { throw AudioRoutingError.engineFailed("切换默认输出后的固定回放验证失败") }
            try router.stopRouting()
            let restored = try CoreAudioService().defaultOutputDevice() == original
            guard restored else { throw AudioRoutingError.engineFailed("验收后默认输出未恢复") }
            report = ["passed": true, "gain": after.output / after.input, "frames": after.frames, "outputRestored": restored, "survivedDefaultOutputSwitch": true]
        } catch { report["error"] = error.localizedDescription }
        do { try router.stopRouting() }
        catch { report["passed"] = false; report["cleanupError"] = error.localizedDescription }
        if let original {
            do { report["outputRestored"] = try CoreAudioService().defaultOutputDevice() == original }
            catch { report["passed"] = false; report["restoreError"] = error.localizedDescription }
        }
        write(report, to: reportURL)
        NSApplication.shared.terminate(nil)
    }

    private static func write(_ report: [String: Any], to url: URL) {
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic) }
        catch { NSLog("路由验收报告写入失败：%@", error.localizedDescription) }
    }
}
