import AppKit
import XCTest
@testable import VolumeControl

final class AudioListApplications: ApplicationProvider {
    var values: [DiscoveredApplication] = []
    func applications(excluding bundleID: String?) -> [DiscoveredApplication] { values }
}

@MainActor
final class AudioApplicationListTests: XCTestCase {
    private func application(_ bundle: String, pid: pid_t = 100, playing: Bool = false,
                             session: AudioSessionStatus = .detected) -> DiscoveredApplication {
        DiscoveredApplication(bundleID: bundle, name: bundle, icon: NSImage(size: NSSize(width: 16, height: 16)),
            processID: pid, audioSessionStatus: session, isPlayingAudio: playing)
    }

    private func model(_ provider: AudioListApplications, storage: MemoryAppAudioPreferences = MemoryAppAudioPreferences(),
                       factory: TestProcessFactory? = nil) -> VolumeControlModel {
        VolumeControlModel(audio: FakeAudioService(), applicationProvider: provider, audioRouter: ModelRoutingStub(),
            monitorDevices: false, inputPermission: ModelPermissionStub(),
            appAudio: ProcessTapVolumeController(factory: factory ?? TestProcessFactory(), storage: storage), restoreRememberedAudio: false)
    }

    func testOnlyOutputApplicationsAppearAndInputOrUnknownSessionsStayHidden() {
        let provider = AudioListApplications()
        provider.values = [application("Finder", session: .notDetected), application("InputOnly"),
            application("Unknown", session: .unavailable("暂不可用")), application("Music", playing: true)]
        let factory = TestProcessFactory()
        let value = model(provider, factory: factory)
        XCTAssertEqual(value.apps.map(\.name), ["Music"])
        XCTAssertEqual(value.statusMessage, "已发现 1 个音频应用")
        XCTAssertFalse(value.apps[0].capability.isSupported, "音频输出不等于通过独立音量验证")
        XCTAssertTrue(factory.made.isEmpty, "筛选不得自动捕获未启用应用")
    }

    func testPlaybackAddsApplicationAndPauseKeepsItUntilProcessExits() {
        let provider = AudioListApplications()
        provider.values = [application("Music")]
        let value = model(provider)
        XCTAssertTrue(value.apps.isEmpty)
        provider.values = [application("Music", playing: true)]
        value.refresh()
        XCTAssertEqual(value.apps.count, 1)
        provider.values = [application("Music", session: .notDetected)]
        value.refresh()
        XCTAssertEqual(value.apps.count, 1)
        XCTAssertEqual(value.apps[0].capability, .noAudioSession)
        provider.values = []
        value.refresh()
        XCTAssertTrue(value.apps.isEmpty)
        provider.values = [application("Music")]
        value.refresh()
        XCTAssertTrue(value.apps.isEmpty, "退出后的进程不能继承旧的输出记录")
    }

    func testNewPIDDoesNotInheritOldOutputAndRememberedApplicationRemainsAccessible() {
        let provider = AudioListApplications()
        provider.values = [application("Music", playing: true)]
        let storage = MemoryAppAudioPreferences()
        storage.values["SavedPlayer"] = AppAudioPreferences(isEnabled: true)
        let value = model(provider, storage: storage)
        provider.values = [application("Music", pid: 101), application("SavedPlayer", pid: 102, session: .notDetected)]
        value.refresh()
        XCTAssertEqual(value.apps.map(\.name), ["SavedPlayer"])
        XCTAssertTrue(value.apps[0].isRemembered)
        XCTAssertFalse(value.apps[0].capability.isSupported)
        XCTAssertEqual(AppListFilter.enabled.applications(from: value.apps, matching: "Saved").count, 1)
    }

    func testKnownOutputDetectionFailureShowsReasonWithoutAddingUnrelatedApps() {
        let provider = AudioListApplications()
        provider.values = [application("Music", playing: true)]
        let value = model(provider)
        provider.values = [application("Music", session: .unavailable("设备变化")),
            application("Notes", pid: 101, session: .unavailable("设备变化"))]
        value.refresh()
        XCTAssertEqual(value.apps.map(\.name), ["Music"])
        XCTAssertEqual(value.apps[0].capability, .unsupported("无法检测音频会话：设备变化"))
    }

    func testDetectionFailureRemainsVisibleWhenNoAudioApplicationsAreKnown() {
        let provider = AudioListApplications()
        provider.values = [application("Unknown", session: .unavailable("Core Audio 查询失败"))]
        let value = model(provider)
        XCTAssertTrue(value.apps.isEmpty)
        XCTAssertEqual(value.statusMessage, "无法检测应用音频输出：Core Audio 查询失败")
    }
}
