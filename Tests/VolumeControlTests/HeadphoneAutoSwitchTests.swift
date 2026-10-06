import AppKit
import CoreAudio
import XCTest
@testable import VolumeControl

final class MemoryDeviceSwitchPreferences: DeviceSwitchPreferenceStoring {
    var options = DeviceSwitchOptions()
    var saves = 0
    func load() -> DeviceSwitchOptions { options }
    func save(_ options: DeviceSwitchOptions) { self.options = options; saves += 1 }
}

final class HeadphoneAutoSwitchPolicyTests: XCTestCase {
    private let speaker = OutputAudioDevice(id: 1, name: "Speaker", uid: "speaker", transport: .builtIn)
    private let headphones = OutputAudioDevice(id: 2, name: "Headphones", uid: "headphones", transport: .usb, isHeadphones: true)

    func testStartupDoesNotSwitchButInsertionAndReconnectionDo() {
        var policy = HeadphoneAutoSwitchPolicy()
        let options = DeviceSwitchOptions()
        XCTAssertNil(policy.newlyConnectedHeadphones(in: [speaker, headphones], selectedID: 1, options: options, switchingBlocked: false))
        XCTAssertNil(policy.newlyConnectedHeadphones(in: [speaker], selectedID: 1, options: options, switchingBlocked: false))
        XCTAssertEqual(policy.newlyConnectedHeadphones(in: [speaker, headphones], selectedID: 1, options: options, switchingBlocked: false)?.id, 2)
        XCTAssertNil(policy.newlyConnectedHeadphones(in: [speaker, headphones], selectedID: 1, options: options, switchingBlocked: false), "手动切回后不能抢回")
    }

    func testBuiltInJackCanBecomeHeadphonesWithoutChangingDeviceID() {
        var policy = HeadphoneAutoSwitchPolicy()
        let options = DeviceSwitchOptions()
        let jack = OutputAudioDevice(id: 3, name: "Built-in Output", uid: "jack", transport: .builtIn)
        var inserted = jack
        inserted.isHeadphones = true
        XCTAssertNil(policy.newlyConnectedHeadphones(in: [speaker, jack], selectedID: 1, options: options, switchingBlocked: false))
        XCTAssertEqual(policy.newlyConnectedHeadphones(in: [speaker, inserted], selectedID: 1, options: options, switchingBlocked: false)?.id, 3)
    }

    func testDisablingOrRoutingConsumesInsertionWithoutDelayedSwitch() {
        for blocked in [false, true] {
            var policy = HeadphoneAutoSwitchPolicy()
            let disabled = DeviceSwitchOptions(autoSwitchHeadphones: blocked)
            _ = policy.newlyConnectedHeadphones(in: [speaker], selectedID: 1, options: disabled, switchingBlocked: blocked)
            XCTAssertNil(policy.newlyConnectedHeadphones(in: [speaker, headphones], selectedID: 1, options: disabled, switchingBlocked: blocked))
            XCTAssertNil(policy.newlyConnectedHeadphones(in: [speaker, headphones], selectedID: 1, options: DeviceSwitchOptions(), switchingBlocked: false))
        }
    }

    func testPreferredUSBUsesStableUIDAndChangingPreferenceDoesNotSwitchExistingDevice() {
        let unknown = OutputAudioDevice(id: 4, name: "USB Audio", uid: "usb-custom", transport: .usb)
        var policy = HeadphoneAutoSwitchPolicy()
        var options = DeviceSwitchOptions()
        _ = policy.newlyConnectedHeadphones(in: [speaker, unknown], selectedID: 1, options: options, switchingBlocked: false)
        options.preferredHeadphoneUID = "usb-custom"
        XCTAssertNil(policy.newlyConnectedHeadphones(in: [speaker, unknown], selectedID: 1, options: options, switchingBlocked: false))
        _ = policy.newlyConnectedHeadphones(in: [speaker], selectedID: 1, options: options, switchingBlocked: false)
        let reconnected = OutputAudioDevice(id: 99, name: "USB Audio", uid: "usb-custom", transport: .usb)
        XCTAssertEqual(policy.newlyConnectedHeadphones(in: [speaker, reconnected, headphones], selectedID: 1, options: options, switchingBlocked: false)?.id, 99)
    }

    func testSpeakersVirtualDisplaysAndAlreadySelectedHeadphonesDoNotSwitch() {
        var policy = HeadphoneAutoSwitchPolicy()
        let options = DeviceSwitchOptions()
        _ = policy.newlyConnectedHeadphones(in: [speaker], selectedID: 1, options: options, switchingBlocked: false)
        let devices = [speaker, headphones,
            OutputAudioDevice(id: 3, name: "USB Speakers", transport: .usb),
            OutputAudioDevice(id: 4, name: "Headphones Virtual", transport: .virtual, isHeadphones: true),
            OutputAudioDevice(id: 5, name: "HDMI Headphones", transport: .display, isHeadphones: true)]
        XCTAssertNil(policy.newlyConnectedHeadphones(in: devices, selectedID: 2, options: options, switchingBlocked: false))
    }

    func testMetadataFailureDoesNotSimulateDisconnection() {
        var policy = HeadphoneAutoSwitchPolicy()
        let options = DeviceSwitchOptions()
        _ = policy.newlyConnectedHeadphones(in: [speaker, headphones], selectedID: 1, options: options, switchingBlocked: false)
        var failed = headphones
        failed.isHeadphones = false
        failed.uid = nil
        failed.autoSwitchMetadataIsValid = false
        XCTAssertNil(policy.newlyConnectedHeadphones(in: [speaker, failed], selectedID: 1, options: options, switchingBlocked: false))
        XCTAssertNil(policy.newlyConnectedHeadphones(in: [speaker, headphones], selectedID: 1, options: options, switchingBlocked: false))
    }

    func testClassificationUsesTerminalsJackOrExplicitNamesWithoutTreatingEveryExternalDeviceAsHeadphones() {
        XCTAssertTrue(OutputDeviceMetadata.isHeadphones(name: "Generic", transport: .usb, headphoneTerminal: true, jackConnected: nil))
        XCTAssertTrue(OutputDeviceMetadata.isHeadphones(name: "Built-in Output", transport: .builtIn, headphoneTerminal: false, jackConnected: true))
        XCTAssertTrue(OutputDeviceMetadata.isHeadphones(name: "AirPods Pro", transport: .bluetooth, headphoneTerminal: false, jackConnected: nil))
        XCTAssertFalse(OutputDeviceMetadata.isHeadphones(name: "USB Speakers", transport: .usb, headphoneTerminal: false, jackConnected: nil))
        XCTAssertFalse(OutputDeviceMetadata.isHeadphones(name: "Bluetooth Speakers", transport: .bluetooth, headphoneTerminal: false, jackConnected: nil))
        XCTAssertFalse(OutputDeviceMetadata.isHeadphones(name: "Headphones", transport: .builtIn, headphoneTerminal: true, jackConnected: false))
        XCTAssertFalse(OutputDeviceMetadata.isHeadphones(name: "Headphones", transport: .virtual, headphoneTerminal: true, jackConnected: true))
        XCTAssertEqual(OutputDeviceMetadata.transport(kAudioDeviceTransportTypeBluetoothLE), .bluetooth)
        XCTAssertEqual(OutputDeviceMetadata.transport(kAudioDeviceTransportTypeAggregate), .virtual)
    }

    func testReadOnlyConnectedDeviceMetadata() throws {
        guard ProcessInfo.processInfo.environment["VOLUMECONTROL_READONLY_DEVICES"] == "1" else {
            throw XCTSkip("显式启用只读真机设备分类验收")
        }
        let devices = try CoreAudioService().outputDevices()
        XCTAssertFalse(devices.isEmpty)
        for device in devices {
            XCTAssertTrue(device.autoSwitchMetadataIsValid, "\(device.name) 的设备分类读取失败")
            print("输出分类：\(device.name)，\(device.transport)，耳机=\(device.isHeadphones)，UID=\(device.uid != nil)")
        }
    }
}

@MainActor
final class HeadphoneAutoSwitchModelTests: XCTestCase {
    private let headphones = OutputAudioDevice(id: 3, name: "Headphones", uid: "headphones", transport: .usb, isHeadphones: true)
    private func model(_ audio: FakeAudioService, store: MemoryDeviceSwitchPreferences,
                       factory: TestProcessFactory? = nil, router: ModelRoutingStub? = nil) -> VolumeControlModel {
        VolumeControlModel(audio: audio, applicationProvider: FakeApplicationProvider(values: []),
            audioRouter: router ?? ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(),
            appAudio: ProcessTapVolumeController(factory: factory ?? TestProcessFactory(), storage: MemoryAppAudioPreferences()),
            restoreRememberedAudio: false, deviceSwitchStorage: store)
    }

    func testInsertionSwitchesOnceAndManualChoiceIsRespected() {
        let audio = FakeAudioService()
        let store = MemoryDeviceSwitchPreferences()
        let value = model(audio, store: store)
        audio.devices.append(headphones)
        value.refresh()
        XCTAssertEqual(audio.selectedDevice, 3)
        XCTAssertEqual(audio.selectionWrites, 1)
        XCTAssertEqual(value.selectedOutputDeviceID, 3)
        value.selectOutputDevice(1)
        value.refresh()
        XCTAssertEqual(audio.selectedDevice, 1)
        XCTAssertEqual(audio.selectionWrites, 2)
        XCTAssertEqual(audio.volumeWrites, 0)
        XCTAssertEqual(store.saves, 0)
    }

    func testOffPreferencePersistsAndInterfaceResetDoesNotChangeIt() {
        let audio = FakeAudioService()
        let store = MemoryDeviceSwitchPreferences()
        let value = model(audio, store: store)
        value.deviceSwitchOptions.autoSwitchHeadphones = false
        value.deviceSwitchOptions.autoSwitchHeadphones = false
        audio.devices.append(headphones)
        value.refresh()
        XCTAssertEqual(audio.selectionWrites, 0)
        XCTAssertEqual(store.saves, 1)
        XCTAssertFalse(model(audio, store: store).deviceSwitchOptions.autoSwitchHeadphones)
        InterfacePreferences(storage: MemoryInterfacePreferences()).resetAppearance()
        XCTAssertFalse(value.deviceSwitchOptions.autoSwitchHeadphones)
    }

    func testQueryFailureAndRecoveryDoNotTreatExistingHeadphonesAsNew() {
        let audio = FakeAudioService()
        audio.devices.append(headphones)
        let value = model(audio, store: MemoryDeviceSwitchPreferences())
        audio.shouldFail = true
        value.refresh()
        audio.shouldFail = false
        value.refresh()
        XCTAssertEqual(audio.selectionWrites, 0)
    }

    func testFailedSwitchIsReportedAndNotRepeatedOnEveryRefresh() {
        let audio = FakeAudioService()
        let value = model(audio, store: MemoryDeviceSwitchPreferences())
        audio.selectionError = AudioServiceError.operationFailed(operation: "耳机切换", status: -50)
        audio.devices.append(headphones)
        value.refresh()
        XCTAssertTrue(value.lastError?.contains("耳机切换") == true)
        value.refresh()
        XCTAssertEqual(audio.selectionWrites, 1)
        XCTAssertEqual(value.selectedOutputDeviceID, 1)
    }

    func testAutoSwitchAbortsWhenOldApplicationSessionCannotClose() async throws {
        let audio = FakeAudioService()
        let store = MemoryDeviceSwitchPreferences()
        let factory = TestProcessFactory()
        let target = AppAudioTarget(bundleID: "Player", processID: 100)
        let application = DiscoveredApplication(bundleID: target.bundleID, name: "Player", icon: NSImage(size: NSSize(width: 16, height: 16)),
            processID: target.processID, audioSessionStatus: .detected, isPlayingAudio: true)
        let value = VolumeControlModel(audio: audio, applicationProvider: FakeApplicationProvider(values: [application]),
            audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(),
            appAudio: ProcessTapVolumeController(factory: factory, storage: MemoryAppAudioPreferences()),
            restoreRememberedAudio: false, deviceSwitchStorage: store)
        await value.enableAppVolume(id: target.id)
        let session = try XCTUnwrap(factory.sessions[target])
        session.closeError = AppAudioError.cleanup("旧会话清理失败")
        audio.devices.append(headphones)
        value.refresh()
        XCTAssertEqual(audio.selectionWrites, 0)
        XCTAssertTrue(value.lastError?.contains("旧会话清理失败") == true)
        session.closeError = nil
        value.stopAppAudioControl()
    }

    func testAdvancedRoutingDoesNotSwitchWhenHeadphonesConnect() async {
        let audio = FakeAudioService()
        let router = ModelRoutingStub()
        router.available = true
        let value = model(audio, store: MemoryDeviceSwitchPreferences(), router: router)
        await value.enableV2()
        audio.devices.append(headphones)
        value.refresh()
        XCTAssertEqual(audio.selectionWrites, 0)
        value.disableV2()
        value.refresh()
        XCTAssertEqual(audio.selectionWrites, 0)
    }
}
