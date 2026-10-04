import CoreAudio
import Foundation
import OSLog

/// 调用与故障通知均在主线程执行，音频回调必须先调度到主线程。
protocol AudioRouting {
    var isRouting: Bool { get }
    var onFailure: ((Error) -> Void)? { get set }
    func isBlackHoleAvailable() throws -> Bool
    func startRouting() throws
    func stopRouting() throws
}

protocol AudioRoutingDevices {
    func blackHoleDevice() throws -> AudioDeviceID?
    func defaultOutputDevice() throws -> AudioDeviceID
    func validatePhysicalOutput(_ device: AudioDeviceID) throws
    func setDefaultOutputDevice(_ device: AudioDeviceID) throws
}

protocol AudioRoutingEngine {
    func start(input: AudioDeviceID, output: AudioDeviceID, onFailure: @escaping (Error) -> Void) throws
    func stop()
}

enum AudioRoutingError: LocalizedError {
    case blackHoleNotFound
    case physicalOutputRequired
    case invalidFormat(String)
    case operationFailed(String, OSStatus)
    case engineFailed(String)
    case rollbackFailed(primary: String, recovery: String)

    var errorDescription: String? {
        switch self {
        case .blackHoleNotFound: return "未找到可用的 BlackHole 输入设备"
        case .physicalOutputRequired: return "请先选择真实输出设备，再启动音频路由验证"
        case .invalidFormat(let reason): return "音频格式不可用：\(reason)"
        case .operationFailed(let operation, let status): return "\(operation)失败（OSStatus \(status)）"
        case .engineFailed(let reason): return "音频转发失败：\(reason)"
        case .rollbackFailed(let primary, let recovery): return "\(primary)；恢复输出设备失败：\(recovery)"
        }
    }
}

/// 生命周期由主线程串行调用；先建立转发通道，再切换系统输出，避免启动失败导致静音。
final class AudioDeviceRouter: AudioRouting {
    private let devices: any AudioRoutingDevices
    private let engine: any AudioRoutingEngine
    private var route: (input: AudioDeviceID, output: AudioDeviceID)?
    private var generation = 0
    private(set) var isRouting = false
    var onFailure: ((Error) -> Void)?

    init(
        devices: any AudioRoutingDevices = CoreAudioRoutingDevices(),
        engine: any AudioRoutingEngine = AVAudioRoutingEngine()
    ) {
        self.devices = devices
        self.engine = engine
    }

    deinit {
        do { try stopRouting() }
        catch { Logger(subsystem: "com.volumecontrol.app", category: "routing").error("\(error.localizedDescription, privacy: .public)") }
    }

    func isBlackHoleAvailable() throws -> Bool {
        try devices.blackHoleDevice() != nil
    }

    func startRouting() throws {
        guard !isRouting else { return }
        // 未完成的恢复必须先重试，不能把 BlackHole 保存成原始设备。
        if route != nil { try stopRouting() }
        guard let input = try devices.blackHoleDevice() else { throw AudioRoutingError.blackHoleNotFound }
        let output = try devices.defaultOutputDevice()
        guard input != output else { throw AudioRoutingError.physicalOutputRequired }
        try devices.validatePhysicalOutput(output)
        generation += 1
        let session = generation
        do {
            try engine.start(input: input, output: output) { [weak self] error in
                guard let self, self.generation == session, self.isRouting else { return }
                var reportedError = error
                do { try self.stopRouting() }
                catch { reportedError = AudioRoutingError.rollbackFailed(primary: reportedError.localizedDescription, recovery: error.localizedDescription) }
                self.onFailure?(reportedError)
            }
            route = (input, output)
            try devices.setDefaultOutputDevice(input)
            isRouting = true
        } catch {
            let primary = error
            do { try stopRouting() }
            catch { throw AudioRoutingError.rollbackFailed(primary: primary.localizedDescription, recovery: error.localizedDescription) }
            throw primary
        }
    }

    func stopRouting() throws {
        generation += 1
        isRouting = false
        defer { engine.stop() }
        guard let route else { return }
        // 用户主动选择了其他输出时保留该选择。
        if try devices.defaultOutputDevice() == route.input {
            try devices.setDefaultOutputDevice(route.output)
        }
        self.route = nil
    }
}
