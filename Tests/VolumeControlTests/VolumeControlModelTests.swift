import XCTest
@testable import VolumeControl

final class VolumeControlModelTests: XCTestCase {
    func testCapabilityLabel() {
        XCTAssertEqual(AppAudioCapability.supported.label, "可调节")
        XCTAssertFalse(AppAudioCapability.unsupported("需要权限").isSupported)
    }

    func testSystemVolumeIsClamped() {
        XCTAssertEqual(SystemAudioService.clamped(-0.2), 0)
        XCTAssertEqual(SystemAudioService.clamped(1.2), 1)
        XCTAssertEqual(SystemAudioService.clamped(0.4), 0.4)
    }
}
