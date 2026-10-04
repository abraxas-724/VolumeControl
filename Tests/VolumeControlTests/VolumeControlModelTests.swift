import AppKit
import XCTest
@testable import VolumeControl

final class FakeAudioService: AudioService {
    var volume = 0.42
    var muted = false
    var deviceName = "测试输出"
    var shouldFail = false
    var shouldFailVolume = false

    func readSystemVolume() throws -> Double {
        if shouldFail || shouldFailVolume { throw AudioServiceError.propertyUnavailable("测试音量") }
        return volume
    }

    func writeSystemVolume(_ value: Double) throws {
        if shouldFail { throw AudioServiceError.noDefaultOutputDevice }
        volume = CoreAudioService.clamped(value)
    }

    func readMuted() throws -> Bool {
        if shouldFail || shouldFailVolume { throw AudioServiceError.propertyUnavailable("测试静音") }
        return muted
    }

    func writeMuted(_ value: Bool) throws {
        if shouldFail { throw AudioServiceError.noDefaultOutputDevice }
        muted = value
    }

    func outputDeviceName() throws -> String {
        if shouldFail { throw AudioServiceError.noDefaultOutputDevice }
        return deviceName
    }
}

struct FakeApplicationProvider: ApplicationProvider {
    let values: [DiscoveredApplication]

    func applications(excluding bundleID: String?) -> [DiscoveredApplication] {
        values.filter { $0.bundleID != bundleID }
    }
}

@MainActor
final class VolumeControlModelTests: XCTestCase {
    private func makeModel(audio: any AudioService, applicationProvider: any ApplicationProvider) -> VolumeControlModel {
        VolumeControlModel(audio: audio, applicationProvider: applicationProvider, audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub())
    }

    func testLoginItemRegistrationStates() {
        XCTAssertTrue(LoginItemStatus.enabled.isRegistered)
        XCTAssertTrue(LoginItemStatus.requiresApproval.isRegistered)
        XCTAssertFalse(LoginItemStatus.disabled.isRegistered)
        XCTAssertFalse(LoginItemStatus.unavailable.isRegistered)
    }

    func testCapabilityLabels() {
        XCTAssertEqual(AppAudioCapability.supported.label, "可调节")
        XCTAssertEqual(AppAudioCapability.noAudioSession.label, "未检测到音频输出")
        XCTAssertFalse(AppAudioCapability.unsupported("需要权限").isSupported)
    }

    func testSystemVolumeIsClamped() {
        XCTAssertEqual(CoreAudioService.clamped(-0.2), 0)
        XCTAssertEqual(CoreAudioService.clamped(1.2), 1)
        XCTAssertEqual(CoreAudioService.clamped(0.4), 0.4)
    }

    func testModelUsesInjectedAudioService() {
        let audio = FakeAudioService()
        let model = makeModel(audio: audio, applicationProvider: FakeApplicationProvider(values: []))

        XCTAssertEqual(model.systemVolume, 0.42)
        XCTAssertEqual(model.outputDeviceName, "测试输出")
        model.systemVolume = 0.8
        model.commitSystemVolume()
        XCTAssertEqual(audio.volume, 0.8)
        model.toggleMute()
        XCTAssertTrue(audio.muted)
    }

    func testApplicationsExposeCapabilityWithoutFakingSupport() {
        let application = DiscoveredApplication(
            bundleID: "com.example.player",
            name: "Player",
            icon: NSImage(size: NSSize(width: 16, height: 16)),
            processID: 101,
            audioSessionStatus: .detected
        )
        let model = makeModel(
            audio: FakeAudioService(),
            applicationProvider: FakeApplicationProvider(values: [application])
        )

        XCTAssertEqual(model.apps.count, 1)
        XCTAssertEqual(model.apps[0].capability, .unsupported("系统接口不支持应用增益"))
        XCTAssertFalse(model.apps[0].capability.isSupported)
    }

    func testRoutingDoesNotEnablePerApplicationGainOrMute() async {
        let router = ModelRoutingStub()
        router.available = true
        let application = DiscoveredApplication(
            bundleID: "com.example.player", name: "Player",
            icon: NSImage(size: NSSize(width: 16, height: 16)),
            processID: 101, audioSessionStatus: .detected
        )
        let model = VolumeControlModel(
            audio: FakeAudioService(), applicationProvider: FakeApplicationProvider(values: [application]),
            audioRouter: router, monitorDevices: false, inputPermission: ModelPermissionStub()
        )
        await model.enableV2()
        XCTAssertTrue(model.isV2Enabled)
        XCTAssertEqual(model.apps[0].capability, .unsupported("系统接口不支持应用增益"))
        model.setAppVolume(id: model.apps[0].id, volume: 0.2)
        XCTAssertEqual(model.apps[0].volume, 1)
        model.toggleAppMute(id: model.apps[0].id)
        XCTAssertFalse(model.statusMessage.contains("已静音"))
        model.disableV2()
        XCTAssertFalse(model.isV2Enabled)
    }

    func testRoutingStartAndRestoreErrorsSurviveRefresh() async {
        let router = ModelRoutingStub()
        router.available = true
        router.startError = AudioRoutingError.engineFailed("启动失败")
        let model = VolumeControlModel(
            audio: FakeAudioService(), applicationProvider: FakeApplicationProvider(values: []),
            audioRouter: router, monitorDevices: false, inputPermission: ModelPermissionStub()
        )
        await model.enableV2()
        model.refresh()
        XCTAssertFalse(model.isV2Enabled)
        XCTAssertTrue(model.statusMessage.contains("启动失败"))
        router.startError = nil
        await model.enableV2()
        router.stopError = AudioRoutingError.operationFailed("恢复输出", -50)
        model.disableV2()
        model.refresh()
        XCTAssertFalse(model.isV2Enabled)
        XCTAssertTrue(model.statusMessage.contains("恢复输出"))
    }

    func testDeniedPermissionDoesNotStartRouting() async {
        let router = ModelRoutingStub()
        router.available = true
        let model = VolumeControlModel(
            audio: FakeAudioService(), applicationProvider: FakeApplicationProvider(values: []),
            audioRouter: router, monitorDevices: false, inputPermission: ModelPermissionStub(allowed: false)
        )
        await model.enableV2()
        XCTAssertFalse(router.isRouting)
        XCTAssertTrue(model.statusMessage.contains("麦克风"))
        XCTAssertFalse(model.isEnablingRouting)
    }

    func testCancellingPermissionWaitCannotStartRoutingLater() async {
        let router = ModelRoutingStub()
        router.available = true
        let permission = DeferredPermissionStub()
        let requested = expectation(description: "permission requested")
        permission.onRequest = { requested.fulfill() }
        let model = VolumeControlModel(
            audio: FakeAudioService(), applicationProvider: FakeApplicationProvider(values: []),
            audioRouter: router, monitorDevices: false, inputPermission: permission
        )
        let task = Task { await model.enableV2() }
        await fulfillment(of: [requested], timeout: 1)
        XCTAssertTrue(model.isEnablingRouting)
        task.cancel()
        model.disableV2()
        permission.resume()
        await task.value
        XCTAssertFalse(router.isRouting)
        XCTAssertFalse(model.isV2Enabled)
        XCTAssertFalse(model.isEnablingRouting)
    }

    func testRuntimeFailureUpdatesModelImmediatelyBeforeRestart() async {
        let router = ModelRoutingStub()
        router.available = true
        let model = VolumeControlModel(
            audio: FakeAudioService(), applicationProvider: FakeApplicationProvider(values: []),
            audioRouter: router, monitorDevices: false, inputPermission: ModelPermissionStub()
        )
        await model.enableV2()
        router.isRouting = false
        router.onFailure?(AudioRoutingError.engineFailed("设备断开"))
        XCTAssertFalse(model.isV2Enabled)
        XCTAssertTrue(model.statusMessage.contains("设备断开"))
        await model.enableV2()
        XCTAssertTrue(model.isV2Enabled)
    }

    func testAudioSessionDetectionFailureIsNotReportedAsNoSession() {
        let application = DiscoveredApplication(
            bundleID: "com.example.player",
            name: "Player",
            icon: NSImage(size: NSSize(width: 16, height: 16)),
            processID: 101,
            audioSessionStatus: .unavailable("Core Audio 查询失败")
        )
        let model = makeModel(
            audio: FakeAudioService(),
            applicationProvider: FakeApplicationProvider(values: [application])
        )

        XCTAssertEqual(model.apps[0].capability, .unsupported("无法检测音频会话：Core Audio 查询失败"))
    }

    func testAudioFailureRemainsVisibleWhenApplicationListIsEmpty() {
        let audio = FakeAudioService()
        audio.shouldFail = true
        let model = makeModel(
            audio: audio,
            applicationProvider: FakeApplicationProvider(values: [])
        )

        XCTAssertEqual(model.statusMessage, "没有可用的输出设备")
    }

    func testDeviceNameRemainsVisibleWhenVolumePropertyIsUnavailable() {
        let audio = FakeAudioService()
        audio.shouldFailVolume = true
        let model = makeModel(
            audio: audio,
            applicationProvider: FakeApplicationProvider(values: [])
        )

        XCTAssertEqual(model.outputDeviceName, "测试输出")
        XCTAssertEqual(model.statusMessage, "音频属性不可用：测试音量")
    }
}

final class ModelRoutingStub: AudioRouting {
    var isRouting = false
    var onFailure: ((Error) -> Void)?
    var available = false
    var startError: Error?
    var stopError: Error?
    func isBlackHoleAvailable() throws -> Bool { available }
    func startRouting() throws {
        if let startError { throw startError }
        isRouting = true
    }
    func stopRouting() throws {
        isRouting = false
        if let stopError { throw stopError }
    }
}

struct ModelPermissionStub: AudioInputPermissionProviding {
    var allowed = true
    func requestAccess() async throws -> Bool { allowed }
}

final class DeferredPermissionStub: AudioInputPermissionProviding {
    var onRequest: (() -> Void)?
    private var continuation: CheckedContinuation<Bool, Never>?
    func requestAccess() async throws -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onRequest?()
        }
    }
    func resume() {
        continuation?.resume(returning: true)
        continuation = nil
    }
}
