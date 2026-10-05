import AppKit
import XCTest
@testable import VolumeControl

private final class RestorationApplications: ApplicationProvider {
    var values: [DiscoveredApplication] = []
    func applications(excluding bundleID: String?) -> [DiscoveredApplication] { values }
}

@MainActor
final class AppAudioRestorationTests: XCTestCase {
    private let target = AppAudioTarget(bundleID: "test.player", processID: 100)
    private func application(pid: pid_t = 100, playing: Bool = true) -> DiscoveredApplication {
        DiscoveredApplication(bundleID: target.bundleID, name: "Player", icon: NSImage(size: NSSize(width: 16, height: 16)), processID: pid, audioSessionStatus: .detected, isPlayingAudio: playing)
    }
    private func model(_ factory: TestProcessFactory, _ storage: MemoryAppAudioPreferences, _ provider: RestorationApplications, clock: @escaping () -> Date = Date.init) -> VolumeControlModel {
        VolumeControlModel(audio: FakeAudioService(), applicationProvider: provider, audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(), appAudio: ProcessTapVolumeController(factory: factory, storage: storage), restorationClock: clock)
    }
    private func settle() async throws { try await Task.sleep(nanoseconds: 30_000_000) }

    func testReopeningRestoresEnabledApplicationWithSavedVolumeAndMute() async throws {
        let storage = MemoryAppAudioPreferences()
        storage.values[target.bundleID] = AppAudioPreferences(volume: 0.35, isMuted: true, isEnabled: true)
        let provider = RestorationApplications()
        provider.values = [application()]
        let factory = TestProcessFactory()
        let first = model(factory, storage, provider)
        try await settle()
        XCTAssertTrue(first.apps[0].capability.isSupported)
        XCTAssertEqual(factory.sessions[target]?.applied.first?.gain, 0)
        first.suspendAppAudioControl()
        XCTAssertTrue(try storage.load(target.bundleID).isEnabled)
        let restartedFactory = TestProcessFactory()
        let restarted = model(restartedFactory, storage, provider)
        try await settle()
        XCTAssertTrue(restarted.apps[0].capability.isSupported)
        XCTAssertEqual(restarted.apps[0].volume, 0.35, accuracy: 0.0001)
        XCTAssertTrue(restarted.apps[0].isMuted)
        restarted.suspendAppAudioControl()
    }

    func testIdleApplicationWaitsForPlaybackAndNewPIDRestoresAutomatically() async throws {
        let storage = MemoryAppAudioPreferences()
        storage.values[target.bundleID] = AppAudioPreferences(isEnabled: true)
        let provider = RestorationApplications()
        provider.values = [application(playing: false)]
        let factory = TestProcessFactory()
        let value = model(factory, storage, provider)
        try await settle()
        XCTAssertTrue(factory.made.isEmpty)
        XCTAssertTrue(value.apps[0].capability.label.contains("播放音频后自动恢复"))
        provider.values = [application()]
        value.refresh()
        value.refresh()
        try await settle()
        XCTAssertEqual(factory.made, [target], "重复刷新不得创建多个捕获会话")
        provider.values = []
        value.refresh()
        provider.values = [application(pid: 101)]
        value.refresh()
        try await settle()
        XCTAssertEqual(factory.made.last?.processID, 101)
        XCTAssertTrue(value.apps[0].capability.isSupported)
        value.suspendAppAudioControl()
    }

    func testExplicitStopPreventsRestorationButKeepsVolume() async throws {
        let storage = MemoryAppAudioPreferences()
        storage.values[target.bundleID] = AppAudioPreferences(volume: 0.3, isEnabled: true)
        let provider = RestorationApplications()
        provider.values = [application()]
        let factory = TestProcessFactory()
        let value = model(factory, storage, provider)
        try await settle()
        value.disableAppVolume(id: target.id)
        value.refresh()
        try await settle()
        XCTAssertEqual(factory.made.count, 1)
        XCTAssertFalse(try storage.load(target.bundleID).isEnabled)
        XCTAssertEqual(try storage.load(target.bundleID).volume, 0.3)
        value.suspendAppAudioControl()
    }

    func testUnverifiedRestorationIsRateLimitedAndNeverPublishedSupported() async throws {
        var now = Date(timeIntervalSince1970: 100)
        let storage = MemoryAppAudioPreferences()
        storage.values[target.bundleID] = AppAudioPreferences(isEnabled: true)
        let provider = RestorationApplications()
        provider.values = [application()]
        let factory = TestProcessFactory()
        let failed = TestProcessSession()
        failed.prepareError = AppAudioError.unverifiedSignal
        factory.sessions[target] = failed
        let value = model(factory, storage, provider, clock: { now })
        try await settle()
        XCTAssertFalse(value.apps[0].capability.isSupported)
        XCTAssertNotNil(value.lastError)
        for _ in 0..<5 { value.refresh() }
        try await settle()
        XCTAssertEqual(factory.made.count, 1)
        now = now.addingTimeInterval(30)
        factory.sessions[target] = TestProcessSession()
        value.refresh()
        try await settle()
        XCTAssertEqual(factory.made.count, 2)
        XCTAssertTrue(value.apps[0].capability.isSupported)
        XCTAssertNil(value.lastError)
        value.suspendAppAudioControl()
    }

    func testNeverEnabledApplicationsAreNotAutomaticallyCaptured() async throws {
        let provider = RestorationApplications()
        provider.values = [application()]
        let factory = TestProcessFactory()
        let value = model(factory, MemoryAppAudioPreferences(), provider)
        try await settle()
        XCTAssertTrue(factory.made.isEmpty)
        XCTAssertFalse(value.apps[0].isRemembered)
        value.suspendAppAudioControl()
    }

    func testStoppingQueuedRestorationCannotStartItLater() async throws {
        let storage = MemoryAppAudioPreferences()
        storage.values[target.bundleID] = AppAudioPreferences(isEnabled: true)
        let provider = RestorationApplications()
        provider.values = [application()]
        let factory = TestProcessFactory()
        let value = model(factory, storage, provider)
        value.stopAppAudioControl()
        try await settle()
        XCTAssertTrue(factory.made.isEmpty)
        XCTAssertFalse(value.hasAppAudioControl)
        XCTAssertFalse(try storage.load(target.bundleID).isEnabled)
        value.suspendAppAudioControl()
    }
}

final class AppAudioPreferencesMigrationTests: XCTestCase {
    func testOldVolumeAndMuteDoNotImplicitlyEnableCapture() throws {
        let old = Data("{\"volume\":0.4,\"isMuted\":true}".utf8)
        let preferences = try JSONDecoder().decode(AppAudioPreferences.self, from: old)
        XCTAssertEqual(preferences.volume, 0.4)
        XCTAssertTrue(preferences.isMuted)
        XCTAssertFalse(preferences.isEnabled)
    }
    func testRememberedFlagSurvivesCoding() throws {
        let value = AppAudioPreferences(volume: 0.2, isMuted: true, isEnabled: true)
        XCTAssertEqual(try JSONDecoder().decode(AppAudioPreferences.self, from: JSONEncoder().encode(value)), value)
    }
}
