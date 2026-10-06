import AVFoundation
import XCTest
@testable import VolumeControl

final class RoutingPCMConverterTests: XCTestCase {
    private func signal(rate: Double = 48000, channels: AVAudioChannelCount = 2, interleaved: Bool = false) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: interleaved))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480
        let data = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<Int(channels) {
            for frame in 0..<480 {
                data[interleaved ? 0 : channel][interleaved ? frame * Int(channels) + channel : frame] = channel == 0 ? 0.25 : -0.25
            }
        }
        return buffer
    }

    func testTapBufferIsCopiedBeforeReuseForBothPCMLayouts() throws {
        for interleaved in [false, true] {
            let input = try signal(interleaved: interleaved)
            let copy = try RoutingPCMConverter.copy(input)
            input.floatChannelData![0][0] = 0
            XCTAssertEqual(copy.floatChannelData![0][0], 0.25)
            XCTAssertEqual(copy.frameLength, input.frameLength)
            XCTAssertEqual(copy.format, input.format)
        }
    }

    func testResamplingPreservesNonSilentStereoSignal() throws {
        let input = try signal()
        let outputFormat = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let converter = try RoutingPCMConverter(input: input.format, output: outputFormat)
        var frames: AVAudioFrameCount = 0
        for _ in 0..<4 {
            let output = try converter.convert(input)
            frames += output.frameLength
            if output.frameLength > 100 {
                XCTAssertEqual(output.floatChannelData![0][100], 0.25, accuracy: 0.01)
                XCTAssertEqual(output.floatChannelData![1][100], -0.25, accuracy: 0.01)
            }
        }
        XCTAssertGreaterThan(frames, 1000)
        XCTAssertLessThan(frames, 2000)
    }

    func testChannelConversionAndSameFormatPassthrough() throws {
        let input = try signal(channels: 1)
        let passthrough = try RoutingPCMConverter(input: input.format, output: input.format)
        XCTAssertTrue(try passthrough.convert(input) === input)
        let stereo = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        let converter = try RoutingPCMConverter(input: input.format, output: stereo)
        let output = try converter.convert(input)
        XCTAssertEqual(output.format.channelCount, 2)
        XCTAssertGreaterThan(output.frameLength, 0)
    }

    func testChangedFormatAndEmptyBufferFailExplicitly() throws {
        let input = try signal()
        let converter = try RoutingPCMConverter(input: input.format, output: input.format)
        let changed = try signal(rate: 44100)
        XCTAssertThrowsError(try converter.convert(changed))
        input.frameLength = 0
        XCTAssertThrowsError(try RoutingPCMConverter.copy(input))
    }
}
