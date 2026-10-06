import CoreAudio
import Foundation
import OSLog

final class AudioDeviceMonitor {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let queue = DispatchQueue.main
    private var addresses: [AudioObjectPropertyAddress] = []
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
        for var address in addresses {
            let status = AudioObjectRemovePropertyListenerBlock(systemObject, &address, queue, listener)
            if status != noErr {
                let error = AudioServiceError.operationFailed(operation: "移除输出设备监听", status: status)
                logger.error("\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
