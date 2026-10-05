import Foundation
import OSLog

/// 只有完成捕获与输出验证的会话才可写入增益；退出、取消或设备变化先恢复原始播放。
@MainActor
final class ProcessTapVolumeController: AppAudioControlling {
    private struct Entry {
        let session: any ProcessAudioSession
        var preferences: AppAudioPreferences
        var ready = false
    }
    private let factory: any ProcessAudioSessionFactory
    private let storage: any AppAudioPreferenceStoring
    private var entries: [AppAudioTarget: Entry] = [:]
    private var failures: [AppAudioTarget: AppAudioCapability] = [:]
    private var cleanupPending: [any ProcessAudioSession] = []
    private var monitorTask: Task<Void, Never>?
    var onChange: (() -> Void)?
    var availability: AppAudioCapability { factory.availability }
    var isActive: Bool { !entries.isEmpty || !cleanupPending.isEmpty }

    init(factory: (any ProcessAudioSessionFactory)? = nil, storage: any AppAudioPreferenceStoring = UserDefaultsAppAudioPreferences()) {
        self.factory = factory ?? CoreAudioProcessSessionFactory()
        self.storage = storage
    }

    func state(for target: AppAudioTarget) -> AppAudioControlState {
        if let entry = entries[target] {
            return AppAudioControlState(preferences: entry.preferences, capability: entry.ready ? .supported : .unsupported("正在验证应用音频"))
        }
        do {
            return AppAudioControlState(preferences: try readPreferences(target.bundleID), capability: failures[target] ?? (availability.isSupported ? .unsupported("点击启用应用音量") : availability))
        } catch {
            return AppAudioControlState(capability: .unsupported("读取应用音量设置失败：\(error.localizedDescription)"))
        }
    }

    private func readPreferences(_ bundleID: String) throws -> AppAudioPreferences {
        var preferences = try storage.load(bundleID)
        preferences.volume = try AppAudioPreferences.validatedVolume(preferences.volume)
        return preferences
    }

    func activate(_ target: AppAudioTarget) async throws {
        if let entry = entries[target] {
            guard entry.ready else { throw AppAudioError.unavailable("该应用正在验证音频，请稍候") }
            return
        }
        guard availability.isSupported else { throw AppAudioError.unavailable(availability.label) }
        guard entries.count < 8 else {
            let error = AppAudioError.unavailable("最多同时控制 8 个应用")
            failures[target] = .unsupported(error.localizedDescription)
            onChange?()
            throw error
        }
        let preferences: AppAudioPreferences
        let session: any ProcessAudioSession
        do {
            try retryCleanup()
            preferences = try readPreferences(target.bundleID)
            session = try factory.makeSession(for: target)
        } catch {
            failures[target] = error as? AppAudioError == .permissionRequired ? .permissionRequired : .unsupported(error.localizedDescription)
            onChange?()
            throw error
        }
        session.apply(preferences)
        entries[target] = Entry(session: session, preferences: preferences)
        failures[target] = nil
        startMonitor()
        onChange?()
        do {
            try await session.prepare()
            try Task.checkCancellation()
            guard let entry = entries[target], ObjectIdentifier(entry.session) == ObjectIdentifier(session) else { throw CancellationError() }
            try session.validate()
            var remembered = preferences
            remembered.isEnabled = true
            try storage.save(remembered, for: target.bundleID)
            entries[target]?.preferences = remembered
            entries[target]?.ready = true
            onChange?()
        } catch {
            if let entry = entries[target], ObjectIdentifier(entry.session) == ObjectIdentifier(session) {
                entries[target] = nil
                do { try session.close() }
                catch {
                    cleanupPending.append(session)
                    failures[target] = .unsupported(error.localizedDescription)
                    onChange?()
                    throw error
                }
                if !(error is CancellationError) {
                    failures[target] = error as? AppAudioError == .permissionRequired ? .permissionRequired : .unsupported(error.localizedDescription)
                }
                onChange?()
            }
            if entries.isEmpty { monitorTask?.cancel(); monitorTask = nil }
            throw error
        }
    }

    func deactivate(_ target: AppAudioTarget) throws {
        // 保存失败仍须释放音频会话，避免把停止操作变成继续播放。
        let persistence = Result {
            var preferences = try readPreferences(target.bundleID)
            preferences.isEnabled = false
            try storage.save(preferences, for: target.bundleID)
        }
        discard(target, reason: nil)
        failures[target] = nil
        defer { onChange?() }
        try retryCleanup()
        try persistence.get()
    }

    func setVolume(_ value: Float, for target: AppAudioTarget) throws {
        var preferences = try readyEntry(target).preferences
        preferences.volume = try AppAudioPreferences.validatedVolume(value)
        try update(preferences, for: target)
    }

    func setMuted(_ muted: Bool, for target: AppAudioTarget) throws {
        var preferences = try readyEntry(target).preferences
        preferences.isMuted = muted
        try update(preferences, for: target)
    }

    private func update(_ preferences: AppAudioPreferences, for target: AppAudioTarget) throws {
        let entry = try readyEntry(target)
        do { try entry.session.validate() }
        catch {
            discard(target, reason: error.localizedDescription)
            onChange?()
            throw error
        }
        entry.session.apply(preferences)
        do { try storage.save(preferences, for: target.bundleID) }
        catch {
            entry.session.apply(entry.preferences)
            throw AppAudioError.unavailable("保存应用音量失败，已恢复之前设置：\(error.localizedDescription)")
        }
        entries[target]?.preferences = preferences
        onChange?()
    }

    private func readyEntry(_ target: AppAudioTarget) throws -> Entry {
        guard let entry = entries[target], entry.ready else { throw AppAudioError.noSession }
        return entry
    }

    func reconcile(_ targets: Set<AppAudioTarget>) {
        var changed = false
        for target in Array(entries.keys) where !targets.contains(target) {
            discard(target, reason: nil)
            changed = true
        }
        failures = failures.filter { targets.contains($0.key) }
        changed = checkHealth() || changed
        if changed { onChange?() }
    }

    func stopAll() throws {
        defer { onChange?() }
        var errors: [String] = []
        do { try suspendAll() } catch { errors.append(error.localizedDescription) }
        do {
            for bundleID in try storage.enabledBundleIDs() {
                do {
                    var preferences = try readPreferences(bundleID)
                    preferences.isEnabled = false
                    try storage.save(preferences, for: bundleID)
                } catch { errors.append(error.localizedDescription) }
            }
        } catch { errors.append(error.localizedDescription) }
        if !errors.isEmpty { throw AppAudioError.unavailable(errors.joined(separator: "；")) }
    }

    /// 退出只释放会话；用户选择的自动恢复与音量设置继续保留。
    func suspendAll() throws {
        monitorTask?.cancel()
        monitorTask = nil
        for target in Array(entries.keys) { discard(target, reason: nil) }
        failures.removeAll()
        try retryCleanup()
        onChange?()
    }

    private func discard(_ target: AppAudioTarget, reason: String?) {
        guard let entry = entries.removeValue(forKey: target) else { return }
        if let reason { failures[target] = .unsupported(reason) }
        do { try entry.session.close() }
        catch {
            cleanupPending.append(entry.session)
            failures[target] = .unsupported(error.localizedDescription)
        }
    }

    private func retryCleanup() throws {
        let pending = cleanupPending
        cleanupPending.removeAll()
        var errors: [String] = []
        for session in pending {
            do { try session.close() }
            catch { cleanupPending.append(session); errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { throw AppAudioError.cleanup(errors.joined(separator: "；")) }
    }

    private func checkHealth() -> Bool {
        var changed = false
        for target in Array(entries.keys) {
            guard let entry = entries[target], entry.ready else { continue }
            do { try entry.session.validate() }
            catch { discard(target, reason: error.localizedDescription); changed = true }
        }
        if entries.isEmpty { monitorTask?.cancel(); monitorTask = nil }
        return changed
    }

    private func startMonitor() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
                guard let self else { return }
                if self.checkHealth() { self.onChange?() }
            }
        }
    }

    deinit {
        monitorTask?.cancel()
        MainActor.assumeIsolated {
            do { try suspendAll() }
            catch { Logger(subsystem: "com.volumecontrol.app", category: "process-audio").error("\(error.localizedDescription, privacy: .public)") }
        }
    }
}
