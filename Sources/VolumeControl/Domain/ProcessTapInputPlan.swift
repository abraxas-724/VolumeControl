import Foundation

/// 聚合设备可能保留耳机的麦克风流；只有已确认的 tap 输入可以启用。
struct ProcessTapInputPlan: Equatable {
    let enabledStreams: [Bool]

    init(physicalInputs: [UInt32], aggregateInputs: [UInt32], tapChannels: UInt32) throws {
        guard aggregateInputs.starts(with: physicalInputs) else {
            throw AppAudioError.unavailable("无法确认聚合设备中的麦克风与应用音频顺序")
        }
        let tapInputs = aggregateInputs.dropFirst(physicalInputs.count)
        guard !tapInputs.isEmpty, tapInputs.count <= 2,
              tapInputs.allSatisfy({ (1...2).contains($0) }),
              tapInputs.reduce(UInt64(0), { $0 + UInt64($1) }) == UInt64(tapChannels) else {
            throw AppAudioError.unavailable("聚合设备中的应用音频通道无法安全映射")
        }
        enabledStreams = Array(repeating: false, count: physicalInputs.count) + Array(repeating: true, count: tapInputs.count)
    }
}
