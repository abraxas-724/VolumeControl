import AVFoundation
import VolumeControlDSP
import XCTest
@testable import VolumeControl

final class ProcessAudioDSPTests: XCTestCase {
    private func buffer(channels: AVAudioChannelCount = 2, interleaved: Bool = false, value: Float) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: channels, interleaved: interleaved))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
        buffer.frameLength = 256
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for entry in list {
            let data = try XCTUnwrap(entry.mData).assumingMemoryBound(to: Float.self)
            for i in 0..<Int(entry.mDataByteSize) / 4 { data[i] = value }
        }
        return buffer
    }

    func testTwoIndependentRealDSPStatesDoNotShareGainOrMute() throws {
        let a = try XCTUnwrap(VCGainCreate(2)), b = try XCTUnwrap(VCGainCreate(2))
        defer { VCGainDestroy(a); VCGainDestroy(b) }
        let input = try buffer(value: 0.4)
        let outA = try buffer(value: 0), outB = try buffer(value: 0)
        VCGainArm(a, true); VCGainArm(b, true)
        VCGainSet(a, 0.25); VCGainSet(b, 0.75)
        VCGainRender(a, input.audioBufferList, outA.mutableAudioBufferList)
        VCGainRender(b, input.audioBufferList, outB.mutableAudioBufferList)
        XCTAssertEqual(outA.floatChannelData![0][255], 0.1, accuracy: 0.0001)
        XCTAssertEqual(outB.floatChannelData![0][255], 0.3, accuracy: 0.0001)
        VCGainSet(a, 0)
        VCGainRender(a, input.audioBufferList, outA.mutableAudioBufferList)
        VCGainRender(b, input.audioBufferList, outB.mutableAudioBufferList)
        XCTAssertEqual(outA.floatChannelData![0][255], 0)
        XCTAssertEqual(outB.floatChannelData![0][255], 0.3, accuracy: 0.0001)
    }

    func testInterleavedInputCanRenderToNonInterleavedOutput() throws {
        let state = try XCTUnwrap(VCGainCreate(2))
        defer { VCGainDestroy(state) }
        let input = try buffer(interleaved: true, value: 0.3), output = try buffer(value: 0)
        VCGainArm(state, true)
        VCGainRender(state, input.audioBufferList, output.mutableAudioBufferList)
        XCTAssertEqual(output.floatChannelData![0][128], 0.3)
        XCTAssertEqual(output.floatChannelData![1][128], 0.3)
        XCTAssertTrue(VCGainHasSignal(state))
        XCTAssertGreaterThan(VCGainOutputFrames(state), 0)
    }

    func testUnarmedProbeDoesNotReplayOrModifyCapturedAudio() throws {
        let state = try XCTUnwrap(VCGainCreate(2))
        defer { VCGainDestroy(state) }
        let input = try buffer(value: 0.4), output = try buffer(value: 0.5)
        VCGainRender(state, input.audioBufferList, output.mutableAudioBufferList)
        XCTAssertEqual(output.floatChannelData![0][255], 0)
        XCTAssertEqual(input.floatChannelData![0][255], 0.4)
        XCTAssertTrue(VCGainHasSignal(state))
        XCTAssertEqual(VCGainOutputFrames(state), 0)
    }

    func testDisabledMicrophoneBufferDoesNotBlockOrEnterProcessTap() throws {
        let state = try XCTUnwrap(VCGainCreate(2))
        defer { VCGainDestroy(state) }
        let tap = try buffer(interleaved: true, value: 0.3)
        let output = try buffer(value: 0)
        let mixed = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(mixed.unsafeMutablePointer) }
        mixed.count = 2
        mixed[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 1024, mData: nil)
        mixed[1] = UnsafeMutableAudioBufferListPointer(tap.mutableAudioBufferList)[0]
        VCGainArm(state, true)
        VCGainRender(state, mixed.unsafePointer, output.mutableAudioBufferList)
        XCTAssertFalse(VCGainHasInvalidLayout(state))
        XCTAssertTrue(VCGainHasSignal(state))
        XCTAssertEqual(output.floatChannelData![0][255], 0.3)
    }

    func testInvalidLayoutFailsClosedAndNonFiniteSamplesAreSanitized() throws {
        let state = try XCTUnwrap(VCGainCreate(2))
        defer { VCGainDestroy(state) }
        let wrong = try buffer(channels: 1, value: 0.4), output = try buffer(value: 0.5)
        VCGainArm(state, true)
        VCGainRender(state, wrong.audioBufferList, output.mutableAudioBufferList)
        XCTAssertTrue(VCGainHasInvalidLayout(state))
        XCTAssertEqual(output.floatChannelData![0][255], 0)
        let input = try buffer(value: .nan)
        VCGainRender(state, input.audioBufferList, output.mutableAudioBufferList)
        XCTAssertEqual(output.floatChannelData![0][255], 0)
    }

    func testVerifiedRangesExcludeActiveMicrophoneAndBlackHoleOutput() throws {
        let state = try XCTUnwrap(VCGainCreate(2))
        defer { VCGainDestroy(state) }
        let microphone = try buffer(channels: 1, value: 0.9)
        let tap = try buffer(interleaved: true, value: 0.3)
        let physical = try buffer(interleaved: true, value: 0)
        let virtual = try buffer(interleaved: true, value: 0.7)
        let input = AudioBufferList.allocate(maximumBuffers: 2)
        let output = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(input.unsafeMutablePointer); free(output.unsafeMutablePointer) }
        input.count = 2; output.count = 2
        input[0] = UnsafeMutableAudioBufferListPointer(microphone.mutableAudioBufferList)[0]
        input[1] = UnsafeMutableAudioBufferListPointer(tap.mutableAudioBufferList)[0]
        output[0] = UnsafeMutableAudioBufferListPointer(physical.mutableAudioBufferList)[0]
        output[1] = UnsafeMutableAudioBufferListPointer(virtual.mutableAudioBufferList)[0]
        XCTAssertTrue(VCGainSetBufferRanges(state, 1, 1, 0, 1))
        VCGainArm(state, true)
        VCGainRender(state, input.unsafePointer, output.unsafeMutablePointer)
        XCTAssertFalse(VCGainHasInvalidLayout(state))
        XCTAssertEqual(physical.floatChannelData![0][0], 0.3)
        XCTAssertEqual(virtual.floatChannelData![0][0], 0.7)
    }

    func testMissingMappedInputClearsOutputAndFailsClosed() throws {
        let state = try XCTUnwrap(VCGainCreate(2))
        defer { VCGainDestroy(state) }
        let input = try buffer(interleaved: true, value: 0.3)
        let output = try buffer(interleaved: true, value: 0.7)
        XCTAssertTrue(VCGainSetBufferRanges(state, 1, 1, 0, 1))
        VCGainArm(state, true)
        VCGainRender(state, input.audioBufferList, output.mutableAudioBufferList)
        XCTAssertTrue(VCGainHasInvalidLayout(state))
        XCTAssertEqual(output.floatChannelData![0][0], 0)
    }

    func testGainTransitionIsRampedAndClamped() throws {
        let state = try XCTUnwrap(VCGainCreate(2))
        defer { VCGainDestroy(state) }
        let input = try buffer(value: 1), output = try buffer(value: 0)
        VCGainArm(state, true); VCGainSet(state, -1)
        VCGainRender(state, input.audioBufferList, output.mutableAudioBufferList)
        XCTAssertGreaterThan(output.floatChannelData![0][0], 0.9)
        XCTAssertEqual(output.floatChannelData![0][255], 0)
        VCGainSet(state, .nan)
        VCGainRender(state, input.audioBufferList, output.mutableAudioBufferList)
        XCTAssertEqual(output.floatChannelData![0][255], 0)
    }
}
