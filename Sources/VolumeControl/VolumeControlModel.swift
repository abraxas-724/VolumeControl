import AppKit
import Foundation
import OSLog

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
    var isMuted = false
    var canActivate = false
    var isPreparing = false
    var isRemembered = false

    static func == (lhs: AppVolume, rhs: AppVolume) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.volume == rhs.volume && lhs.capability == rhs.capability && lhs.isMuted == rhs.isMuted && lhs.canActivate == rhs.canActivate && lhs.isPreparing == rhs.isPreparing && lhs.isRemembered == rhs.isRemembered
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
    @Published private(set) var isEnablingRouting = false
    @Published private(set) var lastError: String?

    private let audio: any AudioService
    private let applicationProvider: any ApplicationProvider
    private var deviceMonitor: AudioDeviceMonitor?
    
    private let appAudio: any AppAudioControlling
    private var discoveredApplications: [DiscoveredApplication] = []
    private var preparingApps: Set<String> = []
    private var activationTasks: [String: Task<Void, Never>] = [:]
    private var routingTask: Task<Void, Never>?
    private var backgroundRefreshTask: Task<Void, Never>?
    private var restoreRememberedAudio: Bool
    private let restorationClock: () -> Date
    private var nextRestoreAttempt: [AppAudioTarget: Date] = [:]
    private var pausedRestoration: Set<String> = []
    private var audioRouter: any AudioRouting
    private let inputPermission: any AudioInputPermissionProviding
    private var enableRequestID = 0
    private var routingError: String?
    private var terminationObserver: NSObjectProtocol?
    let blackHoleInstallGuide = VirtualDeviceManager().getInstallationGuide()

    init(
        audio: any AudioService = CoreAudioService(),
        applicationProvider: any ApplicationProvider = WorkspaceApplicationProvider(),
        audioRouter: (any AudioRouting)? = nil,
        monitorDevices: Bool = true,
        inputPermission: any AudioInputPermissionProviding = AudioInputPermission(),
        appAudio: (any AppAudioControlling)? = nil,
        restoreRememberedAudio: Bool = true,
        restorationClock: @escaping () -> Date = Date.init
    ) {
        self.audio = audio
        self.applicationProvider = applicationProvider
        self.audioRouter = audioRouter ?? AudioDeviceRouter()
        self.inputPermission = inputPermission
        self.appAudio = appAudio ?? ProcessTapVolumeController()
        self.restoreRememberedAudio = restoreRememberedAudio
        self.restorationClock = restorationClock
        systemVolume = 0
        if monitorDevices {
            deviceMonitor = AudioDeviceMonitor { [weak self] in self?.refresh() }
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.disableV2()
                    self?.suspendAppAudioControl()
                }
            }
        }
        self.audioRouter.onFailure = { [weak self] error in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isV2Enabled = false
                self.routingError = error.localizedDescription
                self.report(error)
                self.refresh()
            }
        }
        self.appAudio.onChange = { [weak self] in self?.publishApplications() }
        refresh()
        if monitorDevices && restoreRememberedAudio {
            // 面板关闭时仍检测已记住应用的播放及重启；休眠期间不持有模型。
            backgroundRefreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                    self?.refresh()
                }
            }
        }
    }

    deinit {
        activationTasks.values.forEach { $0.cancel() }
        routingTask?.cancel()
        backgroundRefreshTask?.cancel()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    func refresh() {
        let audioError = refreshSystemAudio()
        discoveredApplications = applicationProvider.applications(excluding: Bundle.main.bundleIdentifier)
        appAudio.reconcile(Set(discoveredApplications.map { AppAudioTarget(bundleID: $0.bundleID, processID: $0.processID) }))
        publishApplications()
        restoreApplicationsIfNeeded()
        do { blackHoleAvailable = try audioRouter.isBlackHoleAvailable() }
        catch {
            blackHoleAvailable = false
            routingError = error.localizedDescription
        }
        if let routingError {
            statusMessage = routingError
        } else if isV2Enabled {
            statusMessage = "音频路由验证运行中；尚不支持应用独立音量"
        } else if let audioError {
            statusMessage = audioError
        } else if apps.contains(where: { $0.capability.isSupported }) {
            statusMessage = "已启用 \(apps.filter { $0.capability.isSupported }.count) 个应用的独立音量"
        } else if apps.isEmpty {
            statusMessage = "打开应用后点击刷新"
        } else {
            statusMessage = "已发现 \(apps.count) 个运行中的应用"
        }
    }

    private func publishApplications() {
        apps = discoveredApplications.map { application in
            let target = AppAudioTarget(bundleID: application.bundleID, processID: application.processID)
            let state = appAudio.state(for: target)
            let capability: AppAudioCapability
            switch application.audioSessionStatus {
            case .detected: capability = state.capability
            case .notDetected: capability = state.capability.isSupported ? state.capability : .noAudioSession
            case .unavailable(let reason): capability = .unsupported("无法检测音频会话：\(reason)")
            }
            let displayCapability: AppAudioCapability
            if state.preferences.isEnabled && state.capability == .unsupported("点击启用应用音量") && !application.isPlayingAudio && (application.audioSessionStatus == .detected || application.audioSessionStatus == .notDetected) {
                displayCapability = .unsupported("已记住，播放音频后自动恢复")
            } else { displayCapability = capability }
            return AppVolume(
                id: target.id, name: application.name, icon: application.icon,
                volume: Double(state.preferences.volume), capability: displayCapability,
                isMuted: state.preferences.isMuted,
                canActivate: application.audioSessionStatus == .detected && appAudio.availability.isSupported && !state.capability.isSupported && !isV2Enabled && !isEnablingRouting,
                isPreparing: preparingApps.contains(target.id),
                isRemembered: state.preferences.isEnabled
            )
        }
    }

    var hasAppAudioControl: Bool { appAudio.isActive || !preparingApps.isEmpty }

    private func restoreApplicationsIfNeeded() {
        guard restoreRememberedAudio, appAudio.availability.isSupported,
              !isV2Enabled, !isEnablingRouting, activationTasks.isEmpty,
              preparingApps.isEmpty, apps.filter({ $0.capability.isSupported }).count < 8 else { return }
        let targets = Set(discoveredApplications.map { AppAudioTarget(bundleID: $0.bundleID, processID: $0.processID) })
        nextRestoreAttempt = nextRestoreAttempt.filter { targets.contains($0.key) }
        let now = restorationClock()
        for application in discoveredApplications where application.isPlayingAudio && !pausedRestoration.contains(application.bundleID) {
            let target = AppAudioTarget(bundleID: application.bundleID, processID: application.processID)
            let state = appAudio.state(for: target)
            guard state.preferences.isEnabled, !state.capability.isSupported,
                  now >= (nextRestoreAttempt[target] ?? .distantPast) else { continue }
            // 无信号或设备暂不可用时限速重试，禁止每次刷新创建新 tap。
            nextRestoreAttempt[target] = now.addingTimeInterval(30)
            startAppVolume(id: target.id)
            break
        }
    }

    // Permission prompts dismiss MenuBarExtra; hiding a view must not cancel an explicit request.
    @discardableResult
    func startAppVolume(id: String) -> Task<Void, Never>? {
        guard activationTasks[id] == nil else { return nil }
        let task = Task { [weak self] in
            await self?.enableAppVolume(id: id)
            self?.activationTasks[id] = nil
        }
        activationTasks[id] = task
        return task
    }

    func cancelAppVolume(id: String) {
        activationTasks[id]?.cancel()
        disableAppVolume(id: id)
    }

    func startRoutingValidation() {
        guard routingTask == nil else { return }
        routingTask = Task { [weak self] in
            await self?.enableV2()
            self?.routingTask = nil
        }
    }

    func cancelRoutingValidation() { routingTask?.cancel(); disableV2() }

    func dismissError() { lastError = nil }

    private func report(_ error: Error) {
        lastError = error.localizedDescription
        statusMessage = error.localizedDescription
        Logger(subsystem: "com.volumecontrol.app", category: "audio-control").error("\(error.localizedDescription, privacy: .public)")
    }

    func enableAppVolume(id: String) async {
        guard !Task.isCancelled,
              let application = discoveredApplications.first(where: { "\($0.bundleID):\($0.processID)" == id }),
              !preparingApps.contains(id), !isV2Enabled, !isEnablingRouting else { return }
        let target = AppAudioTarget(bundleID: application.bundleID, processID: application.processID)
        pausedRestoration.remove(target.bundleID)
        preparingApps.insert(id)
        publishApplications()
        defer { preparingApps.remove(id); publishApplications() }
        do {
            try await appAudio.activate(target)
            lastError = nil
            statusMessage = "\(application.name) 应用音量已启用"
        } catch is CancellationError {
            statusMessage = "已取消启用应用音量"
        } catch { report(error) }
    }

    func disableAppVolume(id: String) {
        guard let target = target(for: id) else { return }
        pausedRestoration.insert(target.bundleID)
        activationTasks[id]?.cancel()
        do {
            try appAudio.deactivate(target)
            statusMessage = "已恢复该应用的原始播放"
        } catch { report(error) }
        publishApplications()
    }

    func stopAppAudioControl() {
        pausedRestoration.formUnion(discoveredApplications.map(\.bundleID))
        activationTasks.values.forEach { $0.cancel() }
        do {
            try appAudio.stopAll()
            routingError = nil
            lastError = nil
            statusMessage = "已停止应用音量控制，恢复原始播放"
        } catch { routingError = error.localizedDescription; report(error) }
        publishApplications()
    }

    func suspendAppAudioControl() {
        restoreRememberedAudio = false
        backgroundRefreshTask?.cancel()
        activationTasks.values.forEach { $0.cancel() }
        do { try appAudio.suspendAll() } catch { report(error) }
        publishApplications()
    }

    func commitSystemVolume() {
        do {
            try audio.writeSystemVolume(systemVolume)
            statusMessage = "系统音量已更新"
        } catch {
            statusMessage = error.localizedDescription
            lastError = error.localizedDescription
            systemVolume = (try? audio.readSystemVolume()) ?? systemVolume
        }
    }

    func toggleMute() {
        do {
            try audio.writeMuted(!isMuted)
            isMuted.toggle()
            statusMessage = isMuted ? "系统已静音" : "已取消静音"
        } catch {
            report(error)
        }
    }

    func setAppVolume(id: String, volume: Double) {
        guard let app = apps.first(where: { $0.id == id }), app.capability.isSupported,
              let target = target(for: id) else { return }
        do {
            guard volume.isFinite else { throw AppAudioError.invalidVolume }
            try appAudio.setVolume(Float(min(max(volume, 0), 1)), for: target)
            publishApplications()
            statusMessage = "\(app.name) 音量已更新"
        } catch { report(error) }
    }

    func toggleAppMute(id: String) {
        guard let app = apps.first(where: { $0.id == id }), app.capability.isSupported,
              let target = target(for: id) else { return }
        do {
            try appAudio.setMuted(!app.isMuted, for: target)
            publishApplications()
            statusMessage = app.isMuted ? "\(app.name) 已取消静音" : "\(app.name) 已静音"
        } catch { report(error) }
    }

    private func target(for id: String) -> AppAudioTarget? {
        discoveredApplications.map { AppAudioTarget(bundleID: $0.bundleID, processID: $0.processID) }.first { $0.id == id }
    }

    func enableV2() async {
        guard !isEnablingRouting, !isV2Enabled else { return }
        guard !hasAppAudioControl else { statusMessage = "请先停止应用音量控制，再验证 BlackHole 路由"; return }
        isEnablingRouting = true
        publishApplications()
        enableRequestID += 1
        let request = enableRequestID
        defer { isEnablingRouting = false; publishApplications() }
        do {
            guard try audioRouter.isBlackHoleAvailable() else { throw AudioRoutingError.blackHoleNotFound }
            let allowed = try await inputPermission.requestAccess()
            guard !Task.isCancelled, request == enableRequestID else { return }
            guard allowed else { throw AudioRoutingError.engineFailed("请在系统设置 → 隐私与安全性 → 麦克风中允许音频输入") }
            try audioRouter.startRouting()
            isV2Enabled = audioRouter.isRouting
            routingError = nil
            lastError = nil
        } catch {
            guard !Task.isCancelled, request == enableRequestID else { return }
            isV2Enabled = false
            routingError = "启用路由失败：\(error.localizedDescription)"
            report(error)
        }
        refresh()
    }

    func disableV2() {
        enableRequestID += 1
        do {
            try audioRouter.stopRouting()
            routingError = nil
        } catch {
            routingError = "停止路由失败：\(error.localizedDescription)"
            report(error)
        }
        isV2Enabled = false
        refresh()
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
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}
