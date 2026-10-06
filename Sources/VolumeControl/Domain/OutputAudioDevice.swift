import CoreAudio

/// 系统输出选择不依赖设备是否支持音量写入或 Process Tap。
struct OutputAudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    var uid: String? = nil
    var transport: OutputDeviceTransport = .unknown
    var isHeadphones = false
    var autoSwitchMetadataIsValid = true

    var connectionIdentity: String { uid ?? "device:\(id)" }
    var canBePreferredHeadphones: Bool { isHeadphones || transport == .usb || transport == .bluetooth }
}

enum OutputDeviceTransport: Equatable {
    case builtIn, usb, bluetooth, virtual, display, network, unknown
}
