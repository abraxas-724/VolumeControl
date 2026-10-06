import CoreAudio
import XCTest
@testable import VolumeControl

final class AudioProcessFamilyTests: XCTestCase {
    let target = AppAudioTarget(bundleID: "test.browser", processID: 100)
    func testMainPIDExactBundleAndDescendantHelpersMatch() {
        let parents: [pid_t: pid_t] = [300: 200, 200: 100]
        XCTAssertTrue(AudioProcessFamily.matches(processID: 100, bundleID: nil, target: target, parent: { _ in nil }))
        XCTAssertTrue(AudioProcessFamily.matches(processID: 110, bundleID: "test.browser", target: target, parent: { _ in nil }))
        XCTAssertTrue(AudioProcessFamily.matches(processID: 300, bundleID: "helper", target: target, parent: { parents[$0] }))
    }
    func testSimilarBundleNamesUnknownParentsAndCyclesDoNotMatch() {
        XCTAssertFalse(AudioProcessFamily.matches(processID: 200, bundleID: "test.browser.other", target: target, parent: { _ in nil }))
        XCTAssertFalse(AudioProcessFamily.matches(processID: 200, bundleID: "helper", target: target, parent: { $0 == 200 ? 300 : 200 }))
    }
    func testErrorMappingPreservesPermissionsAndOperationStatus() {
        XCTAssertThrowsError(try ProcessAudioHAL.check(OSStatus(0x7065726D), "create")) { XCTAssertEqual($0 as? AppAudioError, .permissionRequired) }
        XCTAssertThrowsError(try ProcessAudioHAL.check(-50, "tap")) { XCTAssertEqual($0 as? AppAudioError, .operation("tap", -50)) }
    }
    func testPaddedFloat32LayoutIsRejectedBeforeReinterpretingSamples() {
        var format = AudioStreamBasicDescription()
        format.mFormatID = kAudioFormatLinearPCM
        format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        format.mBitsPerChannel = 32
        format.mChannelsPerFrame = 2
        format.mSampleRate = 48000
        format.mFramesPerPacket = 1
        format.mBytesPerFrame = 12
        format.mBytesPerPacket = 12
        XCTAssertThrowsError(try ProcessAudioHAL.validatePCM(format))
    }

    func testUnsupportedPCMFormatIsRejectedBeforeCallback() {
        var format = AudioStreamBasicDescription()
        format.mFormatID = kAudioFormatLinearPCM
        format.mFormatFlags = kAudioFormatFlagIsSignedInteger
        format.mBitsPerChannel = 16
        format.mChannelsPerFrame = 2
        format.mSampleRate = 48000
        XCTAssertThrowsError(try ProcessAudioHAL.validatePCM(format))
    }
}
