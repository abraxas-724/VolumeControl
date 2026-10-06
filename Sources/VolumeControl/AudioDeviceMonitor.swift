import CoreAudio
import Foundation
import OSLog

final class AudioDeviceMonitor {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let queue = DispatchQueue.main
    private var addresses: [AudioObjectPropertyAddress] = []
    private var deviceAddresses: [AudioDeviceID: [AudioObjectPropertyAddress]] = [:]
    private let listener: AudioObjectPropertyListenerBlock
    private let logger = Logger(subsystem: "com.volumecontrol.app", category: "output-devices")

    init(onChange: @escaping () -> Void) {
        listener = { _, _ in onChange() }
        // 默认输出变化和设备热插拔都需要更新菜单，回调在主队列合并 UI 状态。
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(mSelector: selector,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let status = AudioObjectAddPropertyListenerBlock(systemObject, &address, queue, listener)
            if status == noErr { addresses.append(address) }
            else {
                let error = AudioServiceError.operationFailed(operation: "监听输出设备变化", status: status)
                logger.error("\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    deinit {
        for (device, addresses) in deviceAddresses {
            for var address in addresses { remove(device, address: &address) }
        }
        for var address in addresses {
            let status = AudioObjectRemovePropertyListenerBlock(systemObject, &address, queue, listener)
            if status != noErr {
                let error = AudioServiceError.operationFailed(operation: "移除输出设备监听", status: status)
                logger.error("\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func updateDevices(_ devices: [OutputAudioDevice]) {
        let live = Set(devices.map(\.id))
        for device in Array(deviceAddresses.keys) where !live.contains(device) {
            for var address in deviceAddresses.removeValue(forKey: device) ?? [] { remove(device, address: &address) }
        }
        for device in live where deviceAddresses[device] == nil {
            var registered: [AudioObjectPropertyAddress] = []
            for selector in [kAudioDevicePropertyJackIsConnected, kAudioDevicePropertyDataSource, kAudioDevicePropertyStreams] {
                let elements: [AudioObjectPropertyElement] = selector == kAudioDevicePropertyJackIsConnected ? [0, 1, 2] : [0]
                for element in elements {
                    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
                    guard AudioObjectHasProperty(device, &address) else { continue }
                    let status = AudioObjectAddPropertyListenerBlock(device, &address, queue, listener)
                    if status == noErr { registered.append(address) }
                    else { logger.error("\(AudioServiceError.operationFailed(operation: "监听耳机接入", status: status).localizedDescription, privacy: .public)") }
                }
            }
            deviceAddresses[device] = registered
        }
    }

    private func remove(_ device: AudioDeviceID, address: inout AudioObjectPropertyAddress) {
        let status = AudioObjectRemovePropertyListenerBlock(device, &address, queue, listener)
        if status != noErr {
            logger.error("\(AudioServiceError.operationFailed(operation: "移除耳机接入监听", status: status).localizedDescription, privacy: .public)")
        }
    }
}
