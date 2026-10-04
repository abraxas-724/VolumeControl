import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

/// 两个引擎分别绑定设备，防止系统输出切到 BlackHole 后，转发输出也跟随默认设备形成回路。
final class AVAudioRoutingEngine: AudioRoutingEngine {
    private var inputEngine: AVAudioEngine?
    private var outputEngine: AVAudioEngine?
    private var forwarder: AudioBufferForwarder?
    private var tapInstalled = false
    private var observers: [NSObjectProtocol] = []

    func start(input: AudioDeviceID, output: AudioDeviceID, onFailure: @escaping (Error) -> Void) throws {
        stop()
        let capture = AVAudioEngine()
        let playback = AVAudioEngine()
        inputEngine = capture
        outputEngine = playback
        do {
            try bind(capture.inputNode.audioUnit, to: input, operation: "绑定 BlackHole 输入")
            try bind(playback.outputNode.audioUnit, to: output, operation: "绑定真实输出")
            let inputFormat = capture.inputNode.outputFormat(forBus: 0)
            let hardwareFormat = playback.outputNode.inputFormat(forBus: 0)
            guard inputFormat.sampleRate.isFinite, inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                  hardwareFormat.sampleRate.isFinite, hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0,
                  let outputFormat = AVAudioFormat(standardFormatWithSampleRate: hardwareFormat.sampleRate, channels: min(inputFormat.channelCount, hardwareFormat.channelCount)) else {
                throw AudioRoutingError.invalidFormat("真实输出设备没有有效通道")
            }
            let converter = try RoutingPCMConverter(input: inputFormat, output: outputFormat)
            let player = AVAudioPlayerNode()
            playback.attach(player)
            playback.connect(player, to: playback.mainMixerNode, format: outputFormat)
            let forwarder = AudioBufferForwarder(player: player, converter: converter, onFailure: onFailure)
            self.forwarder = forwarder
            capture.inputNode.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { buffer, _ in
                forwarder.enqueue(buffer)
            }
            tapInstalled = true
            playback.prepare()
            try playback.start()
            player.play()
            capture.prepare()
            try capture.start()
            // 监听在启动后安装，避免初始图配置通知被当成运行故障。
            for engine in [capture, playback] {
                observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
                    onFailure(AudioRoutingError.engineFailed("音频设备或格式发生变化，路由已停止"))
                })
            }
        } catch {
            stop()
            if let error = error as? AudioRoutingError { throw error }
            throw AudioRoutingError.engineFailed(error.localizedDescription)
        }
    }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        // 先使迟到的 tap 和播放完成回调失效，再拆音频图。
        forwarder?.stop()
        inputEngine?.stop()
        if tapInstalled { inputEngine?.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        outputEngine?.stop()
        inputEngine = nil
        outputEngine = nil
        forwarder = nil
    }

    deinit { stop() }

    private func bind(_ unit: AudioUnit?, to device: AudioDeviceID, operation: String) throws {
        guard let unit else { throw AudioRoutingError.engineFailed("\(operation)：Audio Unit 不可用") }
        var device = device
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw AudioRoutingError.operationFailed(operation, status) }
    }
}

private final class AudioBufferForwarder {
    private let queue = DispatchQueue(label: "com.volumecontrol.audio.forward", qos: .userInteractive)
    private let budget = AudioBufferBudget()
    private let player: AVAudioPlayerNode
    private let converter: RoutingPCMConverter
    private let onFailure: (Error) -> Void

    init(player: AVAudioPlayerNode, converter: RoutingPCMConverter, onFailure: @escaping (Error) -> Void) {
        self.player = player
        self.converter = converter
        self.onFailure = onFailure
    }

    func enqueue(_ buffer: AVAudioPCMBuffer) {
        guard let ticket = budget.reserve(duration: Double(buffer.frameLength) / buffer.format.sampleRate) else { return }
        do {
            let owned = try RoutingPCMConverter.copy(buffer)
            queue.async { [self] in
                guard budget.contains(ticket) else { return }
                do {
                    let output = try converter.convert(owned)
                    guard output.frameLength > 0 else {
                        budget.finish(ticket)
                        return
                    }
                    player.scheduleBuffer(output, completionCallbackType: .dataPlayedBack) { [budget] _ in
                        budget.finish(ticket)
                    }
                } catch { fail(error) }
            }
        } catch {
            queue.async { [self] in
                if budget.contains(ticket) { fail(error) }
            }
        }
    }

    func stop() {
        budget.close()
        queue.sync { player.stop() }
    }

    private func fail(_ error: Error) {
        budget.close()
        DispatchQueue.main.async { [onFailure] in onFailure(error) }
    }
}
