import Foundation

/// 固定 BlackHole 输入与真实设备输出的缓冲位置，排除麦克风和 BlackHole 回放以避免反馈。
struct AudioRoutingBufferPlan {
    let inputStart: UInt32
    let inputCount: UInt32
    let outputCount: UInt32
    let inputStreams: [Bool]
    let outputStreams: [Bool]

    init(physicalInputs: [UInt32], physicalOutputs: [UInt32], virtualInputs: [UInt32], virtualOutputs: [UInt32], aggregateInputs: [UInt32], aggregateOutputs: [UInt32]) throws {
        let channels = physicalOutputs.reduce(UInt64(0), { $0 + UInt64($1) })
        guard aggregateInputs == physicalInputs + virtualInputs,
              aggregateOutputs == physicalOutputs + virtualOutputs,
              (1...2).contains(channels),
              virtualInputs.reduce(UInt64(0), { $0 + UInt64($1) }) == channels,
              !physicalOutputs.isEmpty, !virtualInputs.isEmpty else {
            throw AudioRoutingError.invalidFormat("无法确认 BlackHole 输入与真实输出的通道映射")
        }
        inputStart = UInt32(physicalInputs.count)
        inputCount = UInt32(virtualInputs.count)
        outputCount = UInt32(physicalOutputs.count)
        inputStreams = physicalInputs.map { _ in false } + virtualInputs.map { _ in true }
        outputStreams = physicalOutputs.map { _ in true } + virtualOutputs.map { _ in false }
    }
}
