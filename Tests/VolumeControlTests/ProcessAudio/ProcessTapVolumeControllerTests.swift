import XCTest
@testable import VolumeControl

@MainActor
final class TestProcessSession: ProcessAudioSession {
    var prepareError: Error?
    var validateError: Error?
    var closeError: Error?
    var closes = 0
    var applied: [AppAudioPreferences] = []
    var onPrepare: (() async throws -> Void)?
    func prepare() async throws {
        if let prepareError { throw prepareError }
        try await onPrepare?()
    }
    func apply(_ preferences: AppAudioPreferences) { applied.append(preferences) }
    func validate() throws { if let validateError { throw validateError } }
    func close() throws { closes += 1; if let closeError { throw closeError } }
}

@MainActor
final class TestProcessFactory: ProcessAudioSessionFactory {
    var availability: AppAudioCapability = .supported
    var sessions: [AppAudioTarget: TestProcessSession] = [:]
    var made: [AppAudioTarget] = []
    func makeSession(for target: AppAudioTarget) throws -> any ProcessAudioSession {
        made.append(target)
        let session = sessions[target] ?? TestProcessSession()
        sessions[target] = session
        return session
    }
}

final class MemoryAppAudioPreferences: AppAudioPreferenceStoring {
    var values: [String: AppAudioPreferences] = [:]
    var saveError: Error?
    func enabledBundleIDs() throws -> Set<String> { Set(values.filter { $0.value.isEnabled }.keys) }
    func load(_ bundleID: String) throws -> AppAudioPreferences { values[bundleID] ?? AppAudioPreferences() }
    func save(_ preferences: AppAudioPreferences, for bundleID: String) throws {
        if let saveError { throw saveError }
        values[bundleID] = preferences
    }
}

@MainActor
final class ProcessTapVolumeControllerTests: XCTestCase {
    let player = AppAudioTarget(bundleID: "test.player", processID: 100)
    let browser = AppAudioTarget(bundleID: "test.browser", processID: 200)

    func testVerifiedActivationIsRememberedAndExplicitStopForgetsIt() async throws {
        let storage = MemoryAppAudioPreferences()
        let control = ProcessTapVolumeController(factory: TestProcessFactory(), storage: storage)
        try await control.activate(player)
        let saved = try XCTUnwrap(storage.values[player.bundleID])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        XCTAssertEqual(json["isEnabled"] as? Bool, true, "成功启用必须保存自动恢复意图")
        try control.deactivate(player)
        let stopped = try XCTUnwrap(storage.values[player.bundleID])
        let stoppedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(stopped)) as? [String: Any])
        XCTAssertEqual(stoppedJSON["isEnabled"] as? Bool, false)
    }

    func testIndependentVolumeAndMutePreserveTheOtherApplication() async throws {
        let factory = TestProcessFactory()
        let storage = MemoryAppAudioPreferences()
        let control = ProcessTapVolumeController(factory: factory, storage: storage)
        try await control.activate(player)
        try await control.activate(browser)
        try control.setVolume(0.25, for: player)
        try control.setVolume(0.8, for: browser)
        try control.setMuted(true, for: player)
        XCTAssertEqual(factory.sessions[player]?.applied.last?.gain, 0)
        XCTAssertEqual(factory.sessions[browser]?.applied.last?.gain, 0.8)
        XCTAssertEqual(control.state(for: player).preferences.volume, 0.25)
        try control.setMuted(false, for: player)
        XCTAssertEqual(factory.sessions[player]?.applied.last?.gain, 0.25)
        XCTAssertEqual(control.state(for: player).capability, .supported)
        try control.stopAll()
    }

    func testStoppingOneApplicationPreservesTheOtherRoute() async throws {
        let factory = TestProcessFactory()
        let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
        try await control.activate(player)
        try await control.activate(browser)
        try control.setVolume(0.4, for: browser)
        try control.deactivate(player)
        XCTAssertFalse(control.state(for: player).capability.isSupported)
        XCTAssertTrue(control.state(for: browser).capability.isSupported)
        XCTAssertEqual(factory.sessions[player]?.closes, 1)
        XCTAssertEqual(factory.sessions[browser]?.closes, 0)
        XCTAssertEqual(factory.sessions[browser]?.applied.last?.gain, 0.4)
        try control.stopAll()
    }

    func testInvalidStoredVolumeIsRejectedBeforeStartingCapture() async {
        let factory = TestProcessFactory()
        let storage = MemoryAppAudioPreferences()
        storage.values[player.bundleID] = AppAudioPreferences(volume: .nan)
        let control = ProcessTapVolumeController(factory: factory, storage: storage)
        do { try await control.activate(player); XCTFail("must fail") } catch {}
        XCTAssertTrue(factory.made.isEmpty)
        XCTAssertFalse(control.state(for: player).capability.isSupported)
    }

    func testUnverifiedOrDeniedCaptureNeverBecomesSupported() async {
        for error: AppAudioError in [.unverifiedSignal, .permissionRequired, .operation("start", -50)] {
            let factory = TestProcessFactory()
            let session = TestProcessSession()
            session.prepareError = error
            factory.sessions[player] = session
            let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
            do { try await control.activate(player); XCTFail("must fail") } catch {}
            XCTAssertFalse(control.state(for: player).capability.isSupported)
            XCTAssertEqual(session.closes, 1)
            XCTAssertThrowsError(try control.setVolume(0.5, for: player))
        }
    }

    func testPersistenceFailureRollsBackActualGainAndState() async throws {
        let factory = TestProcessFactory()
        let storage = MemoryAppAudioPreferences()
        let control = ProcessTapVolumeController(factory: factory, storage: storage)
        try await control.activate(player)
        storage.saveError = AppAudioError.unavailable("disk full")
        XCTAssertThrowsError(try control.setVolume(0.2, for: player))
        XCTAssertEqual(factory.sessions[player]?.applied.last?.volume, 1)
        XCTAssertEqual(control.state(for: player).preferences.volume, 1)
        XCTAssertThrowsError(try control.stopAll(), "停止也需要写入关闭自动恢复；失败必须可见")
        XCTAssertFalse(control.isActive, "设置写入失败仍须停止音频会话")
        storage.saveError = nil
        try control.stopAll()
    }

    func testFailedPersistenceDuringActivationClosesSessionWithoutRemembering() async {
        let storage = MemoryAppAudioPreferences()
        storage.saveError = AppAudioError.unavailable("disk full")
        let factory = TestProcessFactory()
        let control = ProcessTapVolumeController(factory: factory, storage: storage)
        do { try await control.activate(player); XCTFail("must fail") } catch {}
        XCTAssertFalse(control.state(for: player).capability.isSupported)
        XCTAssertEqual(factory.sessions[player]?.closes, 1)
        XCTAssertNil(storage.values[player.bundleID])
    }

    func testStoppingAllAlsoForgetsClosedApplications() async throws {
        let storage = MemoryAppAudioPreferences()
        storage.values[browser.bundleID] = AppAudioPreferences(volume: 0.6, isEnabled: true)
        let control = ProcessTapVolumeController(factory: TestProcessFactory(), storage: storage)
        try await control.activate(player)
        try control.stopAll()
        XCTAssertFalse(try storage.load(player.bundleID).isEnabled)
        XCTAssertFalse(try storage.load(browser.bundleID).isEnabled)
        XCTAssertEqual(try storage.load(browser.bundleID).volume, 0.6)
    }

    func testClampingAndNonFiniteValues() async throws {
        let factory = TestProcessFactory()
        let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
        try await control.activate(player)
        try control.setVolume(2, for: player)
        XCTAssertEqual(control.state(for: player).preferences.volume, 1)
        try control.setVolume(-1, for: player)
        XCTAssertEqual(control.state(for: player).preferences.volume, 0)
        XCTAssertThrowsError(try control.setVolume(.nan, for: player))
        XCTAssertThrowsError(try control.setVolume(.infinity, for: player))
        try control.stopAll()
    }

    func testSavedVolumeIsRestoredAcrossProcessRestart() async throws {
        let factory = TestProcessFactory()
        let storage = MemoryAppAudioPreferences()
        let control = ProcessTapVolumeController(factory: factory, storage: storage)
        try await control.activate(player)
        try control.setVolume(0.4, for: player)
        control.reconcile([])
        let newPlayer = AppAudioTarget(bundleID: player.bundleID, processID: 101)
        try await control.activate(newPlayer)
        XCTAssertEqual(factory.sessions[newPlayer]?.applied.first?.volume, 0.4)
        XCTAssertFalse(control.state(for: player).capability.isSupported)
        try control.stopAll()
    }

    func testOutputOrProcessChangeClosesRouteAndExposesReason() async throws {
        let factory = TestProcessFactory()
        let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
        try await control.activate(player)
        factory.sessions[player]?.validateError = AppAudioError.unavailable("output changed")
        control.reconcile([player])
        XCTAssertFalse(control.state(for: player).capability.isSupported)
        XCTAssertEqual(control.state(for: player).capability.label, "output changed")
        XCTAssertEqual(factory.sessions[player]?.closes, 1)
    }

    func testCancelOrExitWhilePreparingDoesNotPublishSupported() async throws {
        let factory = TestProcessFactory()
        let session = TestProcessSession()
        let waiting = expectation(description: "prepare started")
        var continuation: CheckedContinuation<Void, Never>?
        session.onPrepare = {
            await withCheckedContinuation { continuation = $0; waiting.fulfill() }
        }
        factory.sessions[player] = session
        let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
        let task = Task { try await control.activate(player) }
        await fulfillment(of: [waiting], timeout: 1)
        XCTAssertFalse(control.state(for: player).capability.isSupported)
        control.reconcile([])
        continuation?.resume()
        do { try await task.value; XCTFail("must cancel") } catch {}
        XCTAssertFalse(control.state(for: player).capability.isSupported)
        XCTAssertEqual(session.closes, 1)
    }

    func testCleanupFailuresAreVisibleAndRetried() async throws {
        let factory = TestProcessFactory()
        let control = ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences())
        try await control.activate(player)
        let session = try XCTUnwrap(factory.sessions[player])
        session.closeError = AppAudioError.cleanup("destroy tap")
        XCTAssertThrowsError(try control.stopAll())
        session.closeError = nil
        try control.stopAll()
        XCTAssertGreaterThanOrEqual(session.closes, 3)
    }
}
