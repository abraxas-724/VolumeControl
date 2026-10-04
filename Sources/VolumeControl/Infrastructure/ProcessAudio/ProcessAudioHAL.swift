import CoreAudio
import Foundation

/// 把 HAL 属性读写失败保留为带操作上下文的错误，不把空句柄视为可用设备。
struct ProcessAudioHAL {
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            // Preserve explicit permission failures separately from generic HAL errors.
            if status == OSStatus(0x7065726D) { throw AppAudioError.permissionRequired }
            throw AppAudioError.operation(operation, status)
        }
    }
    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "读取音频标识 \(selector)")
        guard let value else { throw AppAudioError.unavailable("音频标识为空") }
        return value.takeRetainedValue() as String
    }
    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) throws -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "读取音频对象列表大小")
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !values.isEmpty else { return [] }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values), "读取音频对象列表")
        return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
    static func format(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> AudioStreamBasicDescription {
        var address = address(selector)
        var value = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "读取应用音频格式")
        return value
    }
    static func channelCount(_ object: AudioObjectID, scope: AudioObjectPropertyScope) throws -> UInt32 {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "读取应用音频通道配置大小")
        guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { data.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, data), "读取应用音频通道配置")
        return UnsafeMutableAudioBufferListPointer(data.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + $1.mNumberChannels }
    }
    static func processes(for target: AppAudioTarget) throws -> [AudioObjectID] {
        guard target.processID != getpid(), target.bundleID != Bundle.main.bundleIdentifier else {
            throw AppAudioError.unavailable("不能捕获 VolumeControl 自身的输出")
        }
        let processes = try AudioProcessDetector().processes().filter {
            $0.processID != getpid() && AudioProcessFamily.matches(processID: $0.processID, bundleID: $0.bundleID, target: target, parent: AudioProcessFamily.parentProcessID)
        }
        guard !processes.isEmpty else { throw AppAudioError.noSession }
        return processes.map(\.objectID).sorted()
    }
    static func validatePCM(_ format: AudioStreamBasicDescription) throws {
        // The render callback reads contiguous Float32 samples; padded PCM must be rejected.
        let noninterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let expectedFrameBytes = UInt64(MemoryLayout<Float>.size) * (noninterleaved ? 1 : UInt64(format.mChannelsPerFrame))
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mBitsPerChannel == 32,
              (1...2).contains(format.mChannelsPerFrame),
              format.mFramesPerPacket == 1,
              UInt64(format.mBytesPerFrame) == expectedFrameBytes,
              UInt64(format.mBytesPerPacket) == expectedFrameBytes,
              format.mSampleRate.isFinite, format.mSampleRate > 0 else {
            throw AppAudioError.unavailable("当前设备仅支持 1–2 通道、原生 Float32 PCM；请换用内建扬声器或立体声设备")
        }
    }
}
