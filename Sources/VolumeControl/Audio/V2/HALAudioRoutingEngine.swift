import CoreAudio
import Foundation
import OSLog
import VolumeControlDSP

/// 私有聚合设备固定端点；切换系统默认输出不会使回放跟随 BlackHole。
final class HALAudioRoutingEngine: AudioRoutingEngine {
    private var aggregate: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var renderer: OpaquePointer?
    private var monitor: DispatchSourceTimer?
    private var inputDevice: AudioDeviceID = 0
    private var outputDevice: AudioDeviceID = 0
    private var inputStream: AudioObjectID = 0
    private var outputStream: AudioObjectID = 0
    private var inputFormat = AudioStreamBasicDescription()
    private var outputFormat = AudioStreamBasicDescription()
    private var onFailure: ((Error) -> Void)?
    private var lastFrames: UInt64 = 0
    private var lastProgress = Date()

    func start(input: AudioDeviceID, output: AudioDeviceID, onFailure: @escaping (Error) -> Void) throws {
        try stop()
        inputDevice = input; outputDevice = output
        self.onFailure = onFailure
        do {
            let sourceStreams = try ProcessAudioHAL.objects(input, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
            let destinationStreams = try ProcessAudioHAL.objects(output, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            guard sourceStreams.count == 1, destinationStreams.count == 1 else {
                throw AudioRoutingError.invalidFormat("路由测试当前要求单输入流与单输出流")
            }
            inputStream = sourceStreams[0]; outputStream = destinationStreams[0]
            inputFormat = try ProcessAudioHAL.format(inputStream, kAudioStreamPropertyVirtualFormat)
            outputFormat = try ProcessAudioHAL.format(outputStream, kAudioStreamPropertyVirtualFormat)
            try ProcessAudioHAL.validatePCM(inputFormat); try ProcessAudioHAL.validatePCM(outputFormat)
            guard inputFormat.mSampleRate == outputFormat.mSampleRate,
                  inputFormat.mChannelsPerFrame == outputFormat.mChannelsPerFrame else {
                throw AudioRoutingError.invalidFormat("请在音频 MIDI 设置中为 BlackHole 和真实输出选择相同采样率及通道数")
            }
            let sourceUID = try ProcessAudioHAL.string(input, kAudioDevicePropertyDeviceUID)
            let destinationUID = try ProcessAudioHAL.string(output, kAudioDevicePropertyDeviceUID)
            let config: [String: Any] = [
                kAudioAggregateDeviceNameKey: "VolumeControl Route Test",
                kAudioAggregateDeviceUIDKey: "com.volumecontrol.route.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: destinationUID,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: destinationUID],
                    [kAudioSubDeviceUIDKey: sourceUID, kAudioSubDeviceDriftCompensationKey: true]
                ]
            ]
            try ProcessAudioHAL.check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "创建固定音频路由")
            let plan = try AudioRoutingBufferPlan(
                physicalInputs: ProcessAudioHAL.bufferChannels(output, scope: kAudioDevicePropertyScopeInput),
                physicalOutputs: ProcessAudioHAL.bufferChannels(output, scope: kAudioDevicePropertyScopeOutput),
                virtualInputs: ProcessAudioHAL.bufferChannels(input, scope: kAudioDevicePropertyScopeInput),
                virtualOutputs: ProcessAudioHAL.bufferChannels(input, scope: kAudioDevicePropertyScopeOutput),
                aggregateInputs: ProcessAudioHAL.bufferChannels(aggregate, scope: kAudioDevicePropertyScopeInput),
                aggregateOutputs: ProcessAudioHAL.bufferChannels(aggregate, scope: kAudioDevicePropertyScopeOutput))
            guard let renderer = VCGainCreate(outputFormat.mChannelsPerFrame) else { throw AudioRoutingError.engineFailed("不能分配路由处理器") }
            self.renderer = renderer
            guard VCGainSetBufferRanges(renderer, plan.inputStart, plan.inputCount, 0, plan.outputCount) else { throw AudioRoutingError.invalidFormat("缓冲数量超出安全范围") }
            VCGainArm(renderer, true)
            try ProcessAudioHAL.check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil) { _, input, _, output, _ in
                VCGainRender(renderer, input, output)
            }, "注册固定路由回调")
            guard let ioProc else { throw AudioRoutingError.engineFailed("未获得路由回调句柄") }
            try ProcessAudioHAL.setInputUsage(aggregate, ioProc: ioProc, enabled: plan.inputStreams)
            try ProcessAudioHAL.setStreamUsage(aggregate, scope: kAudioDevicePropertyScopeOutput, ioProc: ioProc, enabled: plan.outputStreams)
            try ProcessAudioHAL.check(AudioDeviceStart(aggregate, ioProc), "启动固定音频路由")
            lastFrames = VCGainOutputFrames(renderer); lastProgress = Date()
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                do { try self.validate() }
                catch { self.onFailure?(error) }
            }
            monitor = timer
            timer.resume()
        } catch {
            let primary = error
            do { try stop() }
            catch { throw AudioRoutingError.rollbackFailed(primary: primary.localizedDescription, recovery: error.localizedDescription) }
            throw primary
        }
    }

    func levels() throws -> (input: Float, output: Float, frames: UInt64, hasSignal: Bool) {
        guard let renderer else { throw AudioRoutingError.engineFailed("路由尚未运行") }
        return (VCGainInputLevel(renderer), VCGainOutputLevel(renderer), VCGainOutputFrames(renderer), VCGainHasSignal(renderer))
    }

    func validate() throws {
        guard let renderer, aggregate != 0 else { throw AudioRoutingError.engineFailed("路由已停止") }
        guard !VCGainHasInvalidLayout(renderer) else { throw AudioRoutingError.invalidFormat("路由缓冲布局发生变化") }
        guard try ProcessAudioHAL.integer(inputDevice, kAudioDevicePropertyDeviceIsAlive) != 0,
              try ProcessAudioHAL.integer(outputDevice, kAudioDevicePropertyDeviceIsAlive) != 0 else { throw AudioRoutingError.engineFailed("路由设备已断开") }
        let source = try ProcessAudioHAL.format(inputStream, kAudioStreamPropertyVirtualFormat)
        let destination = try ProcessAudioHAL.format(outputStream, kAudioStreamPropertyVirtualFormat)
        guard sameFormat(source, inputFormat), sameFormat(destination, outputFormat) else { throw AudioRoutingError.invalidFormat("路由设备采样率或格式发生变化") }
        let frames = VCGainOutputFrames(renderer)
        if frames != lastFrames { lastFrames = frames; lastProgress = Date() }
        else if Date().timeIntervalSince(lastProgress) > 3 { throw AudioRoutingError.engineFailed("路由输出回调已停止") }
    }

    private func sameFormat(_ a: AudioStreamBasicDescription, _ b: AudioStreamBasicDescription) -> Bool {
        a.mSampleRate == b.mSampleRate && a.mFormatID == b.mFormatID && a.mFormatFlags == b.mFormatFlags && a.mChannelsPerFrame == b.mChannelsPerFrame && a.mBytesPerFrame == b.mBytesPerFrame && a.mBytesPerPacket == b.mBytesPerPacket && a.mFramesPerPacket == b.mFramesPerPacket && a.mBitsPerChannel == b.mBitsPerChannel
    }

    func stop() throws {
        monitor?.cancel(); monitor = nil
        onFailure = nil
        if let renderer { VCGainArm(renderer, false) }
        var failures: [String] = []
        func checked(_ status: OSStatus, _ operation: String) -> Bool {
            if status == noErr || status == kAudioHardwareBadObjectError { return true }
            failures.append("\(operation)（OSStatus \(status)）"); return false
        }
        if let ioProc, aggregate != 0 {
            _ = checked(AudioDeviceStop(aggregate, ioProc), "停止路由回调")
            if checked(AudioDeviceDestroyIOProcID(aggregate, ioProc), "销毁路由回调") { self.ioProc = nil }
        }
        if aggregate != 0, checked(AudioHardwareDestroyAggregateDevice(aggregate), "销毁路由聚合设备") { aggregate = 0; ioProc = nil }
        if ioProc == nil, let renderer { VCGainDestroy(renderer); self.renderer = nil }
        if !failures.isEmpty { throw AudioRoutingError.engineFailed(failures.joined(separator: "；")) }
    }

    deinit {
        do { try stop() }
        catch { Logger(subsystem: "com.volumecontrol.app", category: "routing").error("\(error.localizedDescription, privacy: .public)") }
    }
}
