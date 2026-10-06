import CoreAudio
import Foundation
import OSLog

/// 设备类型用于自动切换；缺少分类属性时保留手动输出菜单，不猜测所有 USB/蓝牙都是耳机。
struct OutputDeviceMetadata {
    private let logger = Logger(subsystem: "com.volumecontrol.app", category: "output-devices")

    func device(_ id: AudioDeviceID, name: String) -> OutputAudioDevice {
        do {
            let uid = try string(id, selector: kAudioDevicePropertyDeviceUID)
            let transport = Self.transport(try integer(id, selector: kAudioDevicePropertyTransportType) ?? 0)
            var headphoneTerminal = false
            if transport != .virtual && transport != .display && transport != .network {
                var address = property(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
                if AudioObjectHasProperty(id, &address) {
                    let streams = try ProcessAudioHAL.objects(id, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
                    for stream in streams {
                        if try integer(stream, selector: kAudioStreamPropertyTerminalType) == kAudioStreamTerminalTypeHeadphones {
                            headphoneTerminal = true
                        }
                    }
                }
            }
            var jackStates: [Bool] = []
            for element in [kAudioObjectPropertyElementMain, 1, 2] {
                if let jack = try integer(id, selector: kAudioDevicePropertyJackIsConnected,
                                          scope: kAudioDevicePropertyScopeOutput, element: element) {
                    jackStates.append(jack != 0)
                }
            }
            let jackConnected = jackStates.isEmpty ? nil : jackStates.contains(true)
            let headphones = Self.isHeadphones(name: name, transport: transport,
                                               headphoneTerminal: headphoneTerminal, jackConnected: jackConnected)
            return OutputAudioDevice(id: id, name: name, uid: uid, transport: transport, isHeadphones: headphones)
        } catch {
            logger.error("\(error.localizedDescription, privacy: .public)")
            return OutputAudioDevice(id: id, name: name, autoSwitchMetadataIsValid: false)
        }
    }

    static func transport(_ value: UInt32) -> OutputDeviceTransport {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: return .virtual
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
        case kAudioDeviceTransportTypeAirPlay, kAudioDeviceTransportTypeAVB: return .network
        default: return .unknown
        }
    }

    static func isHeadphones(name: String, transport: OutputDeviceTransport,
                             headphoneTerminal: Bool, jackConnected: Bool?) -> Bool {
        guard transport != .virtual, transport != .display, transport != .network, jackConnected != false else { return false }
        if headphoneTerminal || (transport == .builtIn && jackConnected == true) { return true }
        // 无终端类型的驱动可用明确名称兜底；其他外接设备需要用户指定，避免误切音箱。
        return ["headphone", "headset", "earphone", "earbud", "airpods", "耳机"].contains { name.localizedCaseInsensitiveContains($0) }
    }

    private func property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func integer(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws -> UInt32? {
        var address = property(selector, scope: scope, element: element)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr else { throw AudioServiceError.operationFailed(operation: "读取耳机识别属性 \(selector)", status: status) }
        return value
    }

    private func string(_ object: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String? {
        var address = property(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        guard status == noErr else { throw AudioServiceError.operationFailed(operation: "读取耳机设备标识", status: status) }
        return value?.takeRetainedValue() as String?
    }
}
