import CoreAudio
import Foundation
import OSLog
import VolumeControlDSP

@MainActor
struct CoreAudioProcessSessionFactory: ProcessAudioSessionFactory {
    var availability: AppAudioCapability {
        if #available(macOS 14.2, *) { return .supported }
        return .unsupported("应用独立音量需要 macOS 14.2 或更新系统")
    }
    func makeSession(for target: AppAudioTarget) throws -> any ProcessAudioSession {
        if #available(macOS 14.2, *) { return CoreAudioProcessSession(target: target) }
        throw AppAudioError.unavailable(availability.label)
    }
}

/// 私有 aggregate 把进程 tap 和真实输出放在同一时钟上；默认输出设备保持不变。
@available(macOS 14.2, *)
@MainActor
final class CoreAudioProcessSession: ProcessAudioSession {
    private let target: AppAudioTarget
    private var outputDevice: AudioDeviceID = 0
    private var processObjects: [AudioObjectID] = []
    private var streamFormat = AudioStreamBasicDescription()
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var renderer: OpaquePointer?
    private var description: CATapDescription?
    private var preferences = AppAudioPreferences()
    private var closed = false
    private var started = false
    private var verifiedOutput = false
    private var lastFrames: UInt64 = 0
    private var lastProgress = Date()

    init(target: AppAudioTarget) { self.target = target }

    func prepare() async throws {
        guard Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") != nil else {
            throw AppAudioError.unavailable("请从打包的 VolumeControl.app 启用应用音量，以提供系统音频录制权限说明")
        }
        outputDevice = try CoreAudioService().defaultOutputDevice()
        try CoreAudioRoutingDevices().validatePhysicalOutput(outputDevice)
        let uid = try ProcessAudioHAL.string(outputDevice, kAudioDevicePropertyDeviceUID)
        let outputStreams = try ProcessAudioHAL.objects(outputDevice, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        guard outputStreams.count == 1, let stream = outputStreams.first else {
            throw AppAudioError.unavailable("当前设备包含多个输出流，尚不支持应用音量")
        }
        streamFormat = try ProcessAudioHAL.format(stream, kAudioStreamPropertyVirtualFormat)
        try ProcessAudioHAL.validatePCM(streamFormat)
        processObjects = try ProcessAudioHAL.processes(for: target)
        let description = CATapDescription(processes: processObjects, deviceUID: uid, stream: 0)
        description.name = "VolumeControl \(target.bundleID)"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        self.description = description
        try ProcessAudioHAL.check(AudioHardwareCreateProcessTap(description, &tap), "创建应用 Process Tap")
        let tapUID = try ProcessAudioHAL.string(tap, kAudioTapPropertyUID)
        let tapFormat = try ProcessAudioHAL.format(tap, kAudioTapPropertyFormat)
        try ProcessAudioHAL.validatePCM(tapFormat)
        guard sameFormat(tapFormat, streamFormat) else { throw AppAudioError.unavailable("应用捕获与输出格式不一致") }
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VolumeControl App Audio",
            kAudioAggregateDeviceUIDKey: "com.volumecontrol.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid, kAudioSubDeviceInputChannelsKey: 0]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]
        try ProcessAudioHAL.check(AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate), "创建应用音频聚合设备")
        try await Task.sleep(nanoseconds: 100_000_000)
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        let inputPlan = try ProcessTapInputPlan(
            physicalInputs: ProcessAudioHAL.bufferChannels(outputDevice, scope: kAudioDevicePropertyScopeInput),
            aggregateInputs: ProcessAudioHAL.bufferChannels(aggregate, scope: kAudioDevicePropertyScopeInput),
            tapChannels: tapFormat.mChannelsPerFrame)
        guard try ProcessAudioHAL.channelCount(aggregate, scope: kAudioDevicePropertyScopeOutput) == tapFormat.mChannelsPerFrame else {
            throw AppAudioError.unavailable("聚合设备包含额外输出通道，无法安全映射应用音频")
        }
        guard let renderer = VCGainCreate(tapFormat.mChannelsPerFrame) else { throw AppAudioError.unavailable("无法分配应用增益处理器") }
        self.renderer = renderer
        let inputStart = inputPlan.enabledStreams.prefix(while: { !$0 }).count
        let inputCount = inputPlan.enabledStreams.count - inputStart
        let outputCount = try ProcessAudioHAL.bufferChannels(aggregate, scope: kAudioDevicePropertyScopeOutput).count
        guard VCGainSetBufferRanges(renderer, UInt32(inputStart), UInt32(inputCount), 0, UInt32(outputCount)) else {
            throw AppAudioError.unavailable("音频缓冲数量超出安全映射范围")
        }
        VCGainSet(renderer, preferences.gain)
        // HAL owns the block; the C state is released only after the IOProc is destroyed.
        try ProcessAudioHAL.check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, nil) { _, input, _, output, _ in
            VCGainRender(renderer, input, output)
        }, "注册应用音频回调")
        guard let ioProc else { throw AppAudioError.unavailable("未获得应用音频回调句柄") }
        try ProcessAudioHAL.setInputUsage(aggregate, ioProc: ioProc, enabled: inputPlan.enabledStreams)
        try ProcessAudioHAL.check(AudioDeviceStart(aggregate, ioProc), "启动应用音频捕获")
        started = true
        try await waitFor(renderer, output: false)
        try validate()
        // 原始播放保留到捕获验证成功；不把静音 tap 的存在误报为获得录制权限。
        description.muteBehavior = .mutedWhenTapped
        try setDescription(description)
        VCGainArm(renderer, true)
        try await waitFor(renderer, output: true)
        verifiedOutput = true
        lastFrames = VCGainOutputFrames(renderer)
        lastProgress = Date()
    }

    private func waitFor(_ renderer: OpaquePointer, output: Bool) async throws {
        for _ in 0..<(output ? 150 : 500) {
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            if VCGainHasInvalidLayout(renderer) { throw AppAudioError.unavailable("运行时音频缓冲布局不受支持（输入 \(VCGainActiveInputChannels(renderer))、输出 \(VCGainActiveOutputChannels(renderer)) 个有效通道）") }
            if output ? VCGainOutputFrames(renderer) > 0 : VCGainHasSignal(renderer) { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw AppAudioError.unverifiedSignal
    }

    func apply(_ preferences: AppAudioPreferences) {
        self.preferences = preferences
        if let renderer { VCGainSet(renderer, preferences.gain) }
    }

    var sampleRate: Double { streamFormat.mSampleRate }
    var channelCount: UInt32 { streamFormat.mChannelsPerFrame }

    func levels() throws -> (input: Float, output: Float, frames: UInt64) {
        guard let renderer, !closed else { throw AppAudioError.noSession }
        return (VCGainInputLevel(renderer), VCGainOutputLevel(renderer), VCGainOutputFrames(renderer))
    }

    func validate() throws {
        guard !closed, started, let renderer else { throw AppAudioError.noSession }
        guard !VCGainHasInvalidLayout(renderer) else { throw AppAudioError.unavailable("音频缓冲布局发生变化，请重新启用") }
        if verifiedOutput {
            try verifyMuteBehavior()
            let frames = VCGainOutputFrames(renderer)
            if frames != lastFrames { lastFrames = frames; lastProgress = Date() }
            else if Date().timeIntervalSince(lastProgress) > 3 { throw AppAudioError.unavailable("应用音频输出回调已停止，请重新启用") }
        }
        guard AudioProcessFamily.parentProcessID(target.processID) != nil else { throw AppAudioError.noSession }
        guard try CoreAudioService().defaultOutputDevice() == outputDevice else { throw AppAudioError.unavailable("输出设备已变化，请重新启用应用音量") }
        guard try ProcessAudioHAL.processes(for: target) == processObjects else { throw AppAudioError.unavailable("应用音频进程已变化，请重新启用应用音量") }
        let format = try ProcessAudioHAL.format(tap, kAudioTapPropertyFormat)
        try ProcessAudioHAL.validatePCM(format)
        guard sameFormat(format, streamFormat) else { throw AppAudioError.unavailable("设备采样率或格式已变化，请重新启用") }
    }

    func close() throws {
        closed = true
        started = false
        if let renderer { VCGainArm(renderer, false) }
        var failures: [String] = []
        func checked(_ status: OSStatus, _ operation: String) -> Bool {
            if status == noErr || status == kAudioHardwareBadObjectError { return true }
            failures.append("\(operation)（OSStatus \(status)）")
            return false
        }
        if tap != 0, let description {
            description.muteBehavior = .unmuted
            do { try setDescription(description) }
            catch { failures.append(error.localizedDescription) }
        }
        if let ioProc, aggregate != 0 {
            _ = checked(AudioDeviceStop(aggregate, ioProc), "停止应用音频回调")
            if checked(AudioDeviceDestroyIOProcID(aggregate, ioProc), "销毁应用音频回调") { self.ioProc = nil }
        }
        if aggregate != 0, checked(AudioHardwareDestroyAggregateDevice(aggregate), "销毁应用聚合设备") {
            aggregate = 0
            ioProc = nil
        }
        if tap != 0, checked(AudioHardwareDestroyProcessTap(tap), "销毁应用 Process Tap") { tap = 0 }
        if ioProc == nil, let renderer {
            VCGainDestroy(renderer)
            self.renderer = nil
        }
        if !failures.isEmpty { throw AppAudioError.cleanup(failures.joined(separator: "；")) }
    }

    private func verifyMuteBehavior() throws {
        var address = ProcessAudioHAL.address(kAudioTapPropertyDescription)
        var value: Unmanaged<CATapDescription>?
        var size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
        try ProcessAudioHAL.check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &value), "验证应用原始播放行为")
        guard let value else { throw AppAudioError.unavailable("不能读取应用捕获状态") }
        let current = value.takeRetainedValue()
        guard current.muteBehavior == .mutedWhenTapped else { throw AppAudioError.unavailable("未能验证原始播放静音，已停止增益重放") }
    }

    private func setDescription(_ description: CATapDescription) throws {
        var address = ProcessAudioHAL.address(kAudioTapPropertyDescription)
        var reference = Unmanaged.passUnretained(description)
        try ProcessAudioHAL.check(AudioObjectSetPropertyData(tap, &address, 0, nil, UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size), &reference), "设置应用原始播放行为")
    }

    private func sameFormat(_ lhs: AudioStreamBasicDescription, _ rhs: AudioStreamBasicDescription) -> Bool {
        lhs.mSampleRate == rhs.mSampleRate && lhs.mChannelsPerFrame == rhs.mChannelsPerFrame && lhs.mFormatID == rhs.mFormatID && lhs.mFormatFlags == rhs.mFormatFlags && lhs.mBitsPerChannel == rhs.mBitsPerChannel
    }

    deinit {
        // MainActor 生命周期之外仍需恢复原始播放；通过独立清理函数在主线程执行。
        MainActor.assumeIsolated {
            do { try close() }
            catch { Logger(subsystem: "com.volumecontrol.app", category: "process-audio").error("\(error.localizedDescription, privacy: .public)") }
        }
    }
}
