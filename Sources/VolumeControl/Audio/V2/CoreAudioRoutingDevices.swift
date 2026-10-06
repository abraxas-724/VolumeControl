import CoreAudio
import Foundation

struct CoreAudioRoutingDevices: AudioRoutingDevices {
    func blackHoleDevice() throws -> AudioDeviceID? {
        var address = property(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size), "枚举路由设备大小")
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !devices.isEmpty else { return nil }
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices), "枚举路由设备")
        for device in devices {
            var nameAddress = property(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            try check(AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name), "读取路由设备名称")
            let deviceName = name?.takeRetainedValue() as String?
            if let deviceName, deviceName.contains("BlackHole"),
               try readUInt32(device, kAudioDevicePropertyDeviceIsAlive) != 0,
               try channelCount(device, scope: kAudioDevicePropertyScopeInput) > 0 {
                return device
            }
        }
        return nil
    }

    func defaultOutputDevice() throws -> AudioDeviceID {
        try CoreAudioService().defaultOutputDevice()
    }

    func validatePhysicalOutput(_ device: AudioDeviceID) throws {
        let transport = try readUInt32(device, kAudioDevicePropertyTransportType)
        guard device != kAudioObjectUnknown,
              transport != kAudioDeviceTransportTypeVirtual,
              transport != kAudioDeviceTransportTypeAggregate,
              try readUInt32(device, kAudioDevicePropertyDeviceIsAlive) != 0,
              try channelCount(device, scope: kAudioDevicePropertyScopeOutput) > 0 else {
            throw AudioRoutingError.physicalOutputRequired
        }
    }

    func setDefaultOutputDevice(_ device: AudioDeviceID) throws {
        var address = property(kAudioHardwarePropertyDefaultOutputDevice)
        var value = device
        try check(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value), "切换默认输出设备")
    }

    private func readUInt32(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var address = property(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value), "读取路由设备属性 \(selector)")
        return value
    }

    private func channelCount(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> UInt32 {
        var address = property(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size), "读取路由通道配置大小")
        guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        // AudioBufferList 是变长结构，必须按系统返回的字节数分配。
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, memory), "读取路由通道配置")
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + $1.mNumberChannels }
    }

    private func property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw AudioRoutingError.operationFailed(operation, status) }
    }
}
