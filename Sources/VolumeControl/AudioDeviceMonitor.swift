import CoreAudio
import Foundation

final class AudioDeviceMonitor {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private let queue = DispatchQueue.main
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private let listener: AudioObjectPropertyListenerBlock
    private let isRegistered: Bool

    init(onChange: @escaping () -> Void) {
        let listener: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        self.listener = listener
        isRegistered = AudioObjectAddPropertyListenerBlock(systemObject, &address, queue, listener) == noErr
    }

    deinit {
        guard isRegistered else { return }
        _ = AudioObjectRemovePropertyListenerBlock(systemObject, &address, queue, listener)
    }
}
