import CoreAudio

/// 只响应接入边沿；刷新、手动改输出及偏好修改都不能把现有耳机重新抢回来。
struct HeadphoneAutoSwitchPolicy {
    private var previousConnections: [String: Bool]?

    mutating func newlyConnectedHeadphones(in devices: [OutputAudioDevice], selectedID: AudioDeviceID?,
                                          options: DeviceSwitchOptions, switchingBlocked: Bool) -> OutputAudioDevice? {
        // 热插拔读取失败不能伪装成断开，再在下一次刷新误判为新接入。
        guard devices.allSatisfy(\.autoSwitchMetadataIsValid) else { return nil }
        let previous = previousConnections
        previousConnections = Dictionary(devices.map { ($0.connectionIdentity, $0.isHeadphones) },
                                         uniquingKeysWith: { $0 || $1 })
        guard let previous, options.autoSwitchHeadphones, !switchingBlocked, let selectedID else { return nil }
        let candidates = devices.filter { device in
            guard device.id != selectedID, device.transport != .virtual,
                  device.transport != .display, device.transport != .network else { return false }
            let preferred = device.uid != nil && device.uid == options.preferredHeadphoneUID && device.canBePreferredHeadphones
            let appeared = previous[device.connectionIdentity] == nil
            let jackInserted = device.isHeadphones && previous[device.connectionIdentity] == false
            return (device.isHeadphones || preferred) && (appeared || jackInserted)
        }
        return candidates.sorted { lhs, rhs in
            let leftPreferred = lhs.uid != nil && lhs.uid == options.preferredHeadphoneUID
            let rightPreferred = rhs.uid != nil && rhs.uid == options.preferredHeadphoneUID
            return leftPreferred == rightPreferred ? lhs.id < rhs.id : leftPreferred
        }.first
    }
}
