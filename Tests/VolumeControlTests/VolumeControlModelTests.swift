import AppKit
import XCTest
@testable import VolumeControl

final class FakeAudioService: AudioService {
    var volume = 0.42
    var muted = false
    var deviceName = "测试输出"
    var shouldFail = false

    func readSystemVolume() throws -> Double {
        if shouldFail { throw AudioServiceError.noDefaultOutputDevice }
        return volume
    }

    func writeSystemVolume(_ value: Double) throws {
        if shouldFail { throw AudioServiceError.noDefaultOutputDevice }
        volume = CoreAudioService.clamped(value)
    }

    func readMuted() throws -> Bool {
        if shouldFail { throw AudioServiceError.noDefaultOutputDevice }
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
        let model = VolumeControlModel(audio: audio, applicationProvider: FakeApplicationProvider(values: []))

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
            hasAudioSession: true
        )
        let model = VolumeControlModel(
            audio: FakeAudioService(),
            applicationProvider: FakeApplicationProvider(values: [application])
        )

        XCTAssertEqual(model.apps.count, 1)
        XCTAssertEqual(model.apps[0].capability, .unsupported("系统接口不支持应用增益"))
        XCTAssertFalse(model.apps[0].capability.isSupported)
    }
}
