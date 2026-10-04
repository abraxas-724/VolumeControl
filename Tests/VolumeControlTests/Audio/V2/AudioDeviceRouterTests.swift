import CoreAudio
import XCTest
@testable import VolumeControl

private final class RoutingDevicesStub: AudioRoutingDevices {
    var blackHole: AudioDeviceID? = 10
    var output: AudioDeviceID = 20
    var rejectsOutput = false
    var failedWrites: Set<AudioDeviceID> = []
    var failAfterSwitch = false
    var changes: [AudioDeviceID] = []
    var onWrite: (() -> Void)?
    func blackHoleDevice() throws -> AudioDeviceID? { blackHole }
    func defaultOutputDevice() throws -> AudioDeviceID { output }
    func validatePhysicalOutput(_ device: AudioDeviceID) throws {
        if rejectsOutput { throw AudioRoutingError.physicalOutputRequired }
    }
    func setDefaultOutputDevice(_ device: AudioDeviceID) throws {
        onWrite?()
        changes.append(device)
        if failAfterSwitch { output = device }
        if failedWrites.contains(device) { throw AudioRoutingError.operationFailed("切换测试设备", -50) }
        output = device
    }
}

private final class RoutingEngineStub: AudioRoutingEngine {
    var starts: [(AudioDeviceID, AudioDeviceID)] = []
    var stops = 0
    var fails = false
    var failures: [(Error) -> Void] = []
    func start(input: AudioDeviceID, output: AudioDeviceID, onFailure: @escaping (Error) -> Void) throws {
        starts.append((input, output))
        failures.append(onFailure)
        if fails { throw AudioRoutingError.engineFailed("测试启动失败") }
    }
    func stop() { stops += 1 }
}

final class AudioDeviceRouterTests: XCTestCase {
    func testForwardingStartsBeforeDefaultOutputChangesAndStopRestoresOutput() throws {
        let devices = RoutingDevicesStub()
        let engine = RoutingEngineStub()
        let router = AudioDeviceRouter(devices: devices, engine: engine)
        devices.onWrite = { XCTAssertEqual(engine.starts.count, 1) }
        try router.startRouting()
        XCTAssertTrue(router.isRouting)
        XCTAssertEqual(engine.starts.first?.0, 10)
        XCTAssertEqual(engine.starts.first?.1, 20)
        try router.stopRouting()
        XCTAssertFalse(router.isRouting)
        XCTAssertEqual(devices.changes, [10, 20])
    }

    func testMissingBlackHoleDoesNotChangeOutput() {
        let devices = RoutingDevicesStub()
        devices.blackHole = nil
        let engine = RoutingEngineStub()
        let router = AudioDeviceRouter(devices: devices, engine: engine)
        XCTAssertThrowsError(try router.startRouting())
        XCTAssertTrue(engine.starts.isEmpty)
        XCTAssertTrue(devices.changes.isEmpty)
    }

    func testBlackHoleAndVirtualOutputCannotBeUsedAsPhysicalDestination() {
        for output: AudioDeviceID in [10, 30] {
            let devices = RoutingDevicesStub()
            devices.output = output
            devices.rejectsOutput = true
            let engine = RoutingEngineStub()
            let router = AudioDeviceRouter(devices: devices, engine: engine)
            XCTAssertThrowsError(try router.startRouting())
            XCTAssertTrue(engine.starts.isEmpty)
            XCTAssertTrue(devices.changes.isEmpty)
        }
    }

    func testPartialEngineStartFailureCleansUpWithoutSwitchingOutput() {
        let devices = RoutingDevicesStub()
        let engine = RoutingEngineStub()
        engine.fails = true
        let router = AudioDeviceRouter(devices: devices, engine: engine)
        XCTAssertThrowsError(try router.startRouting())
        XCTAssertEqual(engine.stops, 1)
        XCTAssertEqual(devices.output, 20)
        XCTAssertTrue(devices.changes.isEmpty)
        XCTAssertFalse(router.isRouting)
    }

    func testSwitchFailureStopsBothEngines() {
        let devices = RoutingDevicesStub()
        devices.failedWrites = [10]
        let engine = RoutingEngineStub()
        let router = AudioDeviceRouter(devices: devices, engine: engine)
        XCTAssertThrowsError(try router.startRouting())
        XCTAssertEqual(engine.stops, 1)
        XCTAssertEqual(devices.output, 20)
        XCTAssertFalse(router.isRouting)
    }

    func testFailedWriteThatChangedDeviceStillRestoresOriginalOutput() {
        let devices = RoutingDevicesStub()
        devices.failedWrites = [10]
        devices.failAfterSwitch = true
        let engine = RoutingEngineStub()
        let router = AudioDeviceRouter(devices: devices, engine: engine)
        XCTAssertThrowsError(try router.startRouting())
        XCTAssertEqual(devices.output, 20)
        XCTAssertEqual(devices.changes, [10, 20])
        XCTAssertFalse(router.isRouting)
    }

    func testRuntimeAndRestoreFailureAreBothReportedAndPendingRestoreBlocksRestart() throws {
        let devices = RoutingDevicesStub()
        let engine = RoutingEngineStub()
        let router = AudioDeviceRouter(devices: devices, engine: engine)
        var reported: String?
        router.onFailure = { reported = $0.localizedDescription }
        try router.startRouting()
        devices.failedWrites = [20]
        engine.failures[0](AudioRoutingError.engineFailed("输入断开"))
        XCTAssertTrue(reported?.contains("输入断开") == true)
        XCTAssertTrue(reported?.contains("恢复输出设备失败") == true)
        XCTAssertFalse(router.isRouting)
        XCTAssertThrowsError(try router.startRouting())
        XCTAssertEqual(engine.starts.count, 1)
        devices.failedWrites = []
        try router.stopRouting()
        XCTAssertEqual(devices.output, 20)
    }

    func testRepeatedStartAndStopDoNotRegisterAnotherPipeline() throws {
        let devices = RoutingDevicesStub()
        let engine = RoutingEngineStub()
        let router = AudioDeviceRouter(devices: devices, engine: engine)
        try router.startRouting()
        try router.startRouting()
        try router.stopRouting()
        try router.stopRouting()
        XCTAssertEqual(engine.starts.count, 1)
        XCTAssertEqual(devices.changes, [10, 20])
    }

    func testUserSelectedOutputIsPreservedOnStop() throws {
        let devices = RoutingDevicesStub()
        let router = AudioDeviceRouter(devices: devices, engine: RoutingEngineStub())
        try router.startRouting()
        devices.output = 30
        try router.stopRouting()
        XCTAssertEqual(devices.output, 30)
        XCTAssertEqual(devices.changes, [10])
    }

    func testFailedRestoreIsReportedAndCanBeRetried() throws {
        let devices = RoutingDevicesStub()
        let engine = RoutingEngineStub()
        let router = AudioDeviceRouter(devices: devices, engine: engine)
        try router.startRouting()
        devices.failedWrites = [20]
        XCTAssertThrowsError(try router.stopRouting())
        XCTAssertFalse(router.isRouting)
        XCTAssertEqual(engine.stops, 1)
        devices.failedWrites = []
        try router.stopRouting()
        XCTAssertEqual(devices.output, 20)
    }

    func testRuntimeFailureRestoresDeviceAndReportsReason() throws {
        let devices = RoutingDevicesStub()
        let engine = RoutingEngineStub()
        let router = AudioDeviceRouter(devices: devices, engine: engine)
        var reported: String?
        router.onFailure = { reported = $0.localizedDescription }
        try router.startRouting()
        engine.failures[0](AudioRoutingError.engineFailed("格式变化"))
        XCTAssertEqual(devices.output, 20)
        XCTAssertFalse(router.isRouting)
        XCTAssertTrue(reported?.contains("格式变化") == true)
    }

    func testOldSessionFailureDoesNotStopNewRoute() throws {
        let devices = RoutingDevicesStub()
        let engine = RoutingEngineStub()
        let router = AudioDeviceRouter(devices: devices, engine: engine)
        try router.startRouting()
        try router.stopRouting()
        try router.startRouting()
        engine.failures[0](AudioRoutingError.engineFailed("旧回调"))
        XCTAssertTrue(router.isRouting)
        XCTAssertEqual(devices.output, 10)
        try router.stopRouting()
    }

    func testOperationErrorsIncludeContextAndStatus() {
        let error = AudioRoutingError.operationFailed("绑定 BlackHole 输入", -50)
        XCTAssertTrue(error.localizedDescription.contains("绑定 BlackHole 输入"))
        XCTAssertTrue(error.localizedDescription.contains("-50"))
    }
}
