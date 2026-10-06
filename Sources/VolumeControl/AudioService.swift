import CoreAudio
import Foundation

enum AudioServiceError: LocalizedError, Equatable {
    case noDefaultOutputDevice
    case propertyUnavailable(String)
    case operationFailed(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .noDefaultOutputDevice:
            return "没有可用的输出设备"
        case .propertyUnavailable(let property):
            return "音频属性不可用：\(property)"
        case .operationFailed(let operation, let status):
            return "音频操作失败：\(operation)（OSStatus \(status)）"
        }
    }
}

protocol AudioService {
    func readSystemVolume() throws -> Double
    func writeSystemVolume(_ value: Double) throws
    func readMuted() throws -> Bool
    func writeMuted(_ muted: Bool) throws
    func outputDeviceName() throws -> String
    func outputDevices() throws -> [OutputAudioDevice]
    func defaultOutputDevice() throws -> AudioDeviceID
    func selectOutputDevice(_ device: AudioDeviceID) throws
}

struct CoreAudioService: AudioService {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)

    func readSystemVolume() throws -> Double {
        let value = try readFloat(address: deviceProperty(kAudioDevicePropertyVolumeScalar))
        return Self.clamped(Double(value))
    }

    func writeSystemVolume(_ value: Double) throws {
        var volume = Float(Self.clamped(value))
        let device = try defaultOutputDevice()
        let addresses = try volumePropertyAddresses(for: device)
        for address in addresses {
            try writeFloat(&volume, address: address, device: device)
        }
    }

    func readMuted() throws -> Bool {
        try readUInt32(address: deviceProperty(kAudioDevicePropertyMute)) != 0
    }

    func writeMuted(_ muted: Bool) throws {
        var value: UInt32 = muted ? 1 : 0
        try writeUInt32(&value, address: deviceProperty(kAudioDevicePropertyMute))
    }

    func outputDeviceName() throws -> String {
        let device = try defaultOutputDevice()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let name else {
            throw AudioServiceError.operationFailed(operation: "读取输出设备名称", status: status)
        }
        return name.takeRetainedValue() as String
    }

    func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device)
        guard status == noErr, device != 0 else {
            if status == noErr { throw AudioServiceError.noDefaultOutputDevice }
            throw AudioServiceError.operationFailed(operation: "读取默认输出设备", status: status)
        }
        return device
    }

    func outputDevices() throws -> [OutputAudioDevice] {
        var address = systemProperty(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size), "读取输出设备列表大小")
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !devices.isEmpty else { return [] }
        try check(AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &devices), "读取输出设备列表")
        return try devices.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size).compactMap { device in
            guard try isAvailableOutput(device) else { return nil }
            var nameAddress = systemProperty(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            try check(AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &name), "读取输出设备名称")
            guard let name else { throw AudioServiceError.propertyUnavailable("输出设备名称") }
            return OutputDeviceMetadata().device(device, name: name.takeRetainedValue() as String)
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func selectOutputDevice(_ device: AudioDeviceID) throws {
        // 点击菜单和写入之间设备可能断开，必须重新确认它仍可输出。
        guard try outputDevices().contains(where: { $0.id == device }) else {
            throw AudioServiceError.propertyUnavailable("所选输出设备已断开或不可用")
        }
        var address = systemProperty(kAudioHardwarePropertyDefaultOutputDevice)
        var settable = DarwinBoolean(false)
        try check(AudioObjectIsPropertySettable(systemObject, &address, &settable), "检查输出设备切换权限")
        guard settable.boolValue else { throw AudioServiceError.propertyUnavailable("默认输出设备不可切换") }
        var value = device
        try check(AudioObjectSetPropertyData(systemObject, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value), "切换默认输出设备")
        guard try defaultOutputDevice() == device else {
            throw AudioServiceError.propertyUnavailable("默认输出设备切换未生效，请重试")
        }
    }

    private func isAvailableOutput(_ device: AudioDeviceID) throws -> Bool {
        var aliveAddress = systemProperty(kAudioDevicePropertyDeviceIsAlive)
        var alive: UInt32 = 0
        var aliveSize = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(device, &aliveAddress, 0, nil, &aliveSize, &alive), "读取输出设备在线状态")
        guard alive != 0 else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size), "读取输出通道配置大小")
        guard size >= MemoryLayout<AudioBufferList>.size else { return false }
        // HAL 返回变长缓冲列表，不能只分配一个固定大小的 AudioBufferList。
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { data.deallocate() }
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, data), "读取输出通道配置")
        return UnsafeMutableAudioBufferListPointer(data.assumingMemoryBound(to: AudioBufferList.self)).contains { $0.mNumberChannels > 0 }
    }

    private func systemProperty(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw AudioServiceError.operationFailed(operation: operation, status: status) }
    }

    static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func deviceProperty(_ selector: AudioObjectPropertySelector) throws -> AudioObjectPropertyAddress {
        let device = try defaultOutputDevice()
        let addresses = [kAudioObjectPropertyElementMain, 1, 2].map { element in
            AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
        }
        for candidate in addresses {
            var address = candidate
            if AudioObjectHasProperty(device, &address) {
                return candidate
            }
        }
        throw AudioServiceError.propertyUnavailable(String(selector))
    }

    private func volumePropertyAddresses(for device: AudioDeviceID) throws -> [AudioObjectPropertyAddress] {
        let addresses = [kAudioObjectPropertyElementMain, 1, 2].map { element in
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
        }.filter { candidate in
            var address = candidate
            return AudioObjectHasProperty(device, &address)
        }
        guard !addresses.isEmpty else {
            throw AudioServiceError.propertyUnavailable(String(kAudioDevicePropertyVolumeScalar))
        }
        return addresses
    }

    private func readFloat(address: AudioObjectPropertyAddress) throws -> Float {
        var address = address
        let device = try defaultOutputDevice()
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw AudioServiceError.operationFailed(operation: "读取音频属性", status: status)
        }
        return value
    }

    private func readUInt32(address: AudioObjectPropertyAddress) throws -> UInt32 {
        var address = address
        let device = try defaultOutputDevice()
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw AudioServiceError.operationFailed(operation: "读取音频属性", status: status)
        }
        return value
    }

    private func writeFloat(
        _ value: inout Float,
        address: AudioObjectPropertyAddress,
        device: AudioDeviceID? = nil
    ) throws {
        var address = address
        let targetDevice = try device ?? defaultOutputDevice()
        let size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectSetPropertyData(targetDevice, &address, 0, nil, size, &value)
        guard status == noErr else {
            throw AudioServiceError.operationFailed(operation: "写入音频属性", status: status)
        }
    }

    private func writeUInt32(_ value: inout UInt32, address: AudioObjectPropertyAddress) throws {
        var address = address
        let device = try defaultOutputDevice()
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        guard status == noErr else {
            throw AudioServiceError.operationFailed(operation: "写入音频属性", status: status)
        }
    }
}
