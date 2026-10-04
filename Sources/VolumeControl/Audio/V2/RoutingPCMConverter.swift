import AVFoundation

/// tap buffer 在回调返回后可被系统重用，必须先复制再交给异步转发队列。
final class RoutingPCMConverter {
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter?

    init(input: AVAudioFormat, output: AVAudioFormat) throws {
        guard input.sampleRate.isFinite, input.sampleRate > 0, input.channelCount > 0,
              output.sampleRate.isFinite, output.sampleRate > 0, output.channelCount > 0 else {
            throw AudioRoutingError.invalidFormat("采样率或通道数无效")
        }
        inputFormat = input
        outputFormat = output
        if input == output {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: input, to: output) else {
                throw AudioRoutingError.invalidFormat("不能转换输入和输出格式")
            }
            self.converter = converter
        }
    }

    static func copy(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            throw AudioRoutingError.invalidFormat("不能复制空音频缓冲")
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == destination.count else { throw AudioRoutingError.invalidFormat("缓冲布局不匹配") }
        for index in source.indices {
            guard let src = source[index].mData, let dst = destination[index].mData,
                  source[index].mDataByteSize <= destination[index].mDataByteSize else {
                throw AudioRoutingError.invalidFormat("音频缓冲数据无效")
            }
            memcpy(dst, src, Int(source[index].mDataByteSize))
        }
        return copy
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.format == inputFormat else { throw AudioRoutingError.invalidFormat("输入设备格式发生变化，请重新启动路由") }
        guard let converter else { return buffer }
        let capacity = ceil(Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate) + 32
        guard capacity > 0, capacity <= Double(UInt32.max),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(capacity)) else {
            throw AudioRoutingError.invalidFormat("不能分配输出缓冲")
        }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            guard !supplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, conversionError == nil else {
            throw AudioRoutingError.engineFailed(conversionError?.localizedDescription ?? "PCM 格式转换失败")
        }
        return output
    }
}
