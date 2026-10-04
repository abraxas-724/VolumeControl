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
}

struct CoreAudioService: AudioService {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)

    func readSystemVolume() throws -> Double {
        let value = try readFloat(address: deviceProperty(kAudioDevicePropertyVolumeScalar))
        return Self.clamped(Double(value))
    }

    func writeSystemVolume(_ value: Double) throws {
        var volume = Float(Self.clamped(value))
        try writeFloat(&volume, address: deviceProperty(kAudioDevicePropertyVolumeScalar))
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
        return name.takeUnretainedValue() as String
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

    static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func deviceProperty(_ selector: AudioObjectPropertySelector) throws -> AudioObjectPropertyAddress {
        let device = try defaultOutputDevice()
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else {
            throw AudioServiceError.propertyUnavailable(String(selector))
        }
        return address
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

    private func writeFloat(_ value: inout Float, address: AudioObjectPropertyAddress) throws {
        var address = address
        let device = try defaultOutputDevice()
        let size = UInt32(MemoryLayout<Float>.size)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
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
