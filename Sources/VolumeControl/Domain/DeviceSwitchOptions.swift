import Foundation

/// 音频行为偏好独立于外观，重置界面不会更改耳机自动切换。
struct DeviceSwitchOptions: Equatable {
    var autoSwitchHeadphones = true
    var preferredHeadphoneUID: String? = nil
}

protocol DeviceSwitchPreferenceStoring {
    func load() -> DeviceSwitchOptions
    func save(_ options: DeviceSwitchOptions)
}
