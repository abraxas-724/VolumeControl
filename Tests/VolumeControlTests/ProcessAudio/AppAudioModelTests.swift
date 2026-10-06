import AppKit
import XCTest
@testable import VolumeControl

@MainActor
final class AppAudioModelTests: XCTestCase {
    private let player = AppAudioTarget(bundleID: "test.player", processID: 100)
    private func provider() -> FakeApplicationProvider {
        FakeApplicationProvider(values: [DiscoveredApplication(bundleID: player.bundleID, name: "Player", icon: NSImage(size: NSSize(width: 16, height: 16)), processID: player.processID, audioSessionStatus: .detected, isPlayingAudio: true)])
    }
    func testUIOnlyEnablesAfterVerifiedSessionAndRetainsSettingsOnRefresh() async {
        let audio = FakeAudioService()
        let factory = TestProcessFactory()
        let storage = MemoryAppAudioPreferences()
        let control = ProcessTapVolumeController(factory: factory, storage: storage)
        let model = VolumeControlModel(audio: audio, applicationProvider: provider(), audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(), appAudio: control)
        XCTAssertFalse(model.apps[0].capability.isSupported)
        XCTAssertTrue(model.apps[0].canActivate)
        await model.enableAppVolume(id: player.id)
        XCTAssertTrue(model.apps[0].capability.isSupported)
        model.setAppVolume(id: player.id, volume: 0.25)
        model.toggleAppMute(id: player.id)
        model.refresh()
        XCTAssertEqual(model.apps[0].volume, 0.25)
        XCTAssertTrue(model.apps[0].isMuted)
        XCTAssertEqual(audio.volume, 0.42)
        XCTAssertFalse(audio.muted)
        model.toggleAppMute(id: player.id)
        XCTAssertFalse(model.apps[0].isMuted)
        XCTAssertEqual(factory.sessions[player]?.applied.last?.gain, 0.25)
        model.stopAppAudioControl()
        XCTAssertFalse(model.apps[0].capability.isSupported)
        XCTAssertFalse(model.hasAppAudioControl)
    }

    func testFailedActivationKeepsSlidersDisabledAndReasonVisible() async {
        let factory = TestProcessFactory()
        let session = TestProcessSession()
        session.prepareError = AppAudioError.unverifiedSignal
        factory.sessions[player] = session
        let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
        let model = VolumeControlModel(audio: FakeAudioService(), applicationProvider: provider(), audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(), appAudio: control)
        await model.enableAppVolume(id: player.id)
        model.refresh()
        XCTAssertFalse(model.apps[0].capability.isSupported)
        XCTAssertTrue(model.apps[0].capability.label.contains("未收到可验证音频"))
        model.setAppVolume(id: player.id, volume: 0.2)
        XCTAssertEqual(model.apps[0].volume, 1)
    }

    func testBlackHoleRoutingCannotOverlapActiveApplicationAudio() async {
        let factory = TestProcessFactory()
        let router = ModelRoutingStub()
        router.available = true
        let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
        let model = VolumeControlModel(audio: FakeAudioService(), applicationProvider: provider(), audioRouter: router, monitorDevices: false, inputPermission: ModelPermissionStub(), appAudio: control)
        await model.enableAppVolume(id: player.id)
        await model.enableV2()
        XCTAssertFalse(router.isRouting)
        XCTAssertTrue(model.hasAppAudioControl)
        model.stopAppAudioControl()
        await model.enableV2()
        XCTAssertTrue(router.isRouting)
        XCTAssertFalse(model.apps[0].canActivate)
        model.disableV2()
    }

    func testRoutingPermissionWaitBlocksApplicationAudioActivation() async {
        let permission = DeferredPermissionStub()
        let requested = expectation(description: "routing permission requested")
        permission.onRequest = { requested.fulfill() }
        let factory = TestProcessFactory()
        let router = ModelRoutingStub()
        router.available = true
        let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
        let model = VolumeControlModel(audio: FakeAudioService(), applicationProvider: provider(), audioRouter: router, monitorDevices: false, inputPermission: permission, appAudio: control)
        let routing = Task { await model.enableV2() }
        await fulfillment(of: [requested], timeout: 1)
        model.refresh()
        XCTAssertFalse(model.apps[0].canActivate)
        await model.enableAppVolume(id: player.id)
        XCTAssertFalse(model.hasAppAudioControl)
        permission.resume()
        await routing.value
        XCTAssertTrue(router.isRouting)
        model.disableV2()
    }

    func testCleanupFailureLeavesStopActionAvailableForRetry() async {
        let factory = TestProcessFactory()
        let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
        let model = VolumeControlModel(audio: FakeAudioService(), applicationProvider: provider(), audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(), appAudio: control)
        await model.enableAppVolume(id: player.id)
        factory.sessions[player]?.closeError = AppAudioError.cleanup("tap busy")
        model.stopAppAudioControl()
        XCTAssertTrue(model.hasAppAudioControl)
        XCTAssertTrue(model.statusMessage.contains("tap busy"))
        factory.sessions[player]?.closeError = nil
        model.stopAppAudioControl()
        XCTAssertFalse(model.hasAppAudioControl)
        model.refresh()
        XCTAssertFalse(model.statusMessage.contains("tap busy"))
        XCTAssertNil(model.lastError)
    }

    func testModelOwnedActivationCanBeCancelledAndFailureSurvivesRefresh() async throws {
        let factory = TestProcessFactory()
        let session = TestProcessSession()
        let started = expectation(description: "activation started")
        var continuation: CheckedContinuation<Void, Never>?
        session.onPrepare = { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        factory.sessions[player] = session
        let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
        let model = VolumeControlModel(audio: FakeAudioService(), applicationProvider: provider(), audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(), appAudio: control)
        let task = try XCTUnwrap(model.startAppVolume(id: player.id))
        await fulfillment(of: [started], timeout: 1)
        XCTAssertTrue(model.apps[0].isPreparing)
        model.stopAppAudioControl()
        continuation?.resume()
        await task.value
        XCTAssertFalse(model.hasAppAudioControl)
        XCTAssertFalse(model.apps[0].capability.isSupported)
        XCTAssertEqual(session.closes, 1)
        let failed = TestProcessSession()
        failed.prepareError = AppAudioError.unverifiedSignal
        factory.sessions[player] = failed
        await model.enableAppVolume(id: player.id)
        let error = model.lastError
        XCTAssertNotNil(error)
        model.refresh()
        XCTAssertEqual(model.lastError, error)
        model.dismissError()
        XCTAssertNil(model.lastError)
    }
}
