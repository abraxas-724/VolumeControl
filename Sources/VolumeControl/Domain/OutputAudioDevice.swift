import CoreAudio

/// 系统输出选择不依赖设备是否支持音量写入或 Process Tap。
struct OutputAudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}
