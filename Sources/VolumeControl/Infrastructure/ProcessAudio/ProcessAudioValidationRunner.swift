import AppKit
import CoreAudio
import Foundation

/// 显式命令行验收使用两个人造信号进程，不写系统音量、默认设备或用户音量偏好。
@MainActor
enum ProcessAudioValidationRunner {
    static func runTarget(arguments: [String]) async {
        guard let index = arguments.firstIndex(of: "--verify-target-audio"), arguments.count > index + 3,
              let pid = pid_t(arguments[index + 1]) else { NSApplication.shared.terminate(nil); return }
        let target = AppAudioTarget(bundleID: arguments[index + 2], processID: pid)
        let url = URL(fileURLWithPath: arguments[index + 3])
        var report: [String: Any] = ["passed": false]
        if #available(macOS 14.2, *) {
            let session = CoreAudioProcessSession(target: target)
            do {
                let original = try CoreAudioService().defaultOutputDevice()
                // Unity gain verifies a real app without changing its volume preference.
                try await session.prepare()
                try await Task.sleep(nanoseconds: 250_000_000)
                try session.validate()
                let levels = try session.levels()
                report = ["passed": true, "capturedSignalVerified": true, "sourceMuteBehaviorVerified": true, "outputFrames": levels.frames, "sampleRate": session.sampleRate, "channels": session.channelCount, "liveInputDetected": levels.input > 0, "defaultOutputPreserved": try CoreAudioService().defaultOutputDevice() == original]
                if levels.input > 0 {
                    let ratio = levels.output / levels.input
                    guard ratio.isFinite, abs(ratio - 1) < 0.02 else { throw AppAudioError.unavailable("原音量转发验证失败") }
                    report["gain"] = ratio
                }
            } catch { report["passed"] = false; report["error"] = error.localizedDescription }
            do { try session.close() }
            catch { report["passed"] = false; report["cleanupError"] = error.localizedDescription }
        } else { report["error"] = "需要 macOS 14.2+" }
        do { try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic) }
        catch { NSLog("目标应用验收报告写入失败：%@", error.localizedDescription) }
        NSApplication.shared.terminate(nil)
    }

    static func run(arguments: [String]) async {
        guard let index = arguments.firstIndex(of: "--verify-process-audio"), arguments.count > index + 3,
              let pidA = pid_t(arguments[index + 1]), let pidB = pid_t(arguments[index + 2]) else {
            NSApplication.shared.terminate(nil)
            return
        }
        let url = URL(fileURLWithPath: arguments[index + 3])
        var report: [String: Any] = ["passed": false]
        if #available(macOS 14.2, *) {
            let a = CoreAudioProcessSession(target: AppAudioTarget(bundleID: "com.volumecontrol.validation.toneA", processID: pidA))
            let b = CoreAudioProcessSession(target: AppAudioTarget(bundleID: "com.volumecontrol.validation.toneB", processID: pidB))
            do {
                let original = try CoreAudioService().defaultOutputDevice()
                try await a.prepare()
                try await b.prepare()
                a.apply(AppAudioPreferences(volume: 0.25))
                b.apply(AppAudioPreferences(volume: 0.8))
                try await Task.sleep(nanoseconds: 300_000_000)
                let firstA = try a.levels(), firstB = try b.levels()
                let ratioA = firstA.output / firstA.input, ratioB = firstB.output / firstB.input
                guard ratioA.isFinite, ratioB.isFinite, abs(ratioA - 0.25) < 0.02, abs(ratioB - 0.8) < 0.02 else {
                    throw AppAudioError.unavailable("两个真实进程的输出增益验证失败：\(ratioA), \(ratioB)")
                }
                a.apply(AppAudioPreferences(volume: 0.25, isMuted: true))
                try await Task.sleep(nanoseconds: 300_000_000)
                let muteA = try a.levels(), unchangedB = try b.levels()
                guard muteA.output < 0.000001, abs(unchangedB.output / unchangedB.input - 0.8) < 0.02 else {
                    throw AppAudioError.unavailable("独立静音验证失败")
                }
                a.apply(AppAudioPreferences(volume: 0.25))
                try await Task.sleep(nanoseconds: 300_000_000)
                let restored = try a.levels()
                guard abs(restored.output / restored.input - 0.25) < 0.02 else { throw AppAudioError.unavailable("取消静音恢复验证失败") }
                for _ in 0..<10 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    try a.validate(); try b.validate()
                }
                try a.close(); try b.close()
                for _ in 0..<3 {
                    let repeated = CoreAudioProcessSession(target: AppAudioTarget(bundleID: "com.volumecontrol.validation.toneA", processID: pidA))
                    do { try await repeated.prepare(); try repeated.validate(); try repeated.close() }
                    catch {
                        let primary = error
                        do { try repeated.close() }
                        catch { throw AppAudioError.cleanup("\(primary.localizedDescription)；\(error.localizedDescription)") }
                        throw primary
                    }
                }
                guard try CoreAudioService().defaultOutputDevice() == original else { throw AppAudioError.unavailable("默认输出发生变化") }
                report = ["sampleRate": a.sampleRate, "channels": a.channelCount, "passed": true, "gainA": ratioA, "gainB": ratioB, "mutedOutputA": muteA.output, "unmutedGainA": restored.output / restored.input, "outputFramesA": firstA.frames, "outputFramesB": firstB.frames, "defaultOutputPreserved": true, "repeatedStartStopCycles": 3, "steadyStateSeconds": 5, "sourceMuteBehaviorVerified": true]
            } catch { report["error"] = error.localizedDescription }
            var cleanupErrors: [String] = []
            for session in [a, b] {
                do { try session.close() }
                catch { cleanupErrors.append(error.localizedDescription) }
            }
            if !cleanupErrors.isEmpty { report["passed"] = false; report["cleanupErrors"] = cleanupErrors }
        } else { report["error"] = "需要 macOS 14.2+" }
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch { NSLog("应用音频验收报告写入失败：%@", error.localizedDescription) }
        NSApplication.shared.terminate(nil)
    }
}
