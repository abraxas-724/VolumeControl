import XCTest
@testable import VolumeControl

/// Core Audio PoC 测试
/// Week 1 Day 5-7 交付物
final class CoreAudioPOCTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["VOLUMECONTROL_HARDWARE_TESTS"] == "1" else {
            throw XCTSkip("真机音频测试须显式设置 VOLUMECONTROL_HARDWARE_TESTS=1")
        }
    }

    
    var sut: CoreAudioPOC!
    
    override func setUp() {
        super.setUp()
        guard ProcessInfo.processInfo.environment["VOLUMECONTROL_HARDWARE_TESTS"] == "1" else { return }
        sut = CoreAudioPOC()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Tests
    
    func testAudioEngineInitialization() {
        // Given & When
        let poc = CoreAudioPOC()
        
        // Then
        XCTAssertNotNil(poc, "PoC should be initialized")
    }
    
    func testSetVolume() {
        // Given
        let testPID: pid_t = 12345
        let targetVolume: Float = 0.75
        
        // When
        sut.setVolume(targetVolume, for: testPID)
        let actualVolume = sut.getVolume(for: testPID)
        
        // Then
        XCTAssertEqual(actualVolume, targetVolume, accuracy: 0.01)
    }
    
    func testVolumeClaming() {
        // Given
        let testPID: pid_t = 12345
        
        // When - 测试超出范围的音量
        sut.setVolume(-0.5, for: testPID)
        let minVolume = sut.getVolume(for: testPID)
        
        sut.setVolume(1.5, for: testPID)
        let maxVolume = sut.getVolume(for: testPID)
        
        // Then
        XCTAssertEqual(minVolume, 0.0, accuracy: 0.01, "Volume should be clamped to 0.0")
        XCTAssertEqual(maxVolume, 1.0, accuracy: 0.01, "Volume should be clamped to 1.0")
    }
    
    func testMuteUnmute() {
        // Given
        let testPID: pid_t = 12345
        sut.setVolume(0.8, for: testPID)
        
        // When - 静音
        sut.muteApp(testPID)
        let mutedVolume = sut.getVolume(for: testPID)
        
        // Then
        XCTAssertEqual(mutedVolume, 0.0, accuracy: 0.01, "Volume should be 0 when muted")
        
        // When - 取消静音
        sut.unmuteApp(testPID)
        let unmutedVolume = sut.getVolume(for: testPID)
        
        // Then
        XCTAssertGreaterThan(unmutedVolume, 0.0, "Volume should be > 0 when unmuted")
    }
    
    func testMultipleApps() {
        // Given
        let pid1: pid_t = 100
        let pid2: pid_t = 200
        let pid3: pid_t = 300
        
        // When
        sut.setVolume(0.3, for: pid1)
        sut.setVolume(0.6, for: pid2)
        sut.setVolume(0.9, for: pid3)
        
        // Then
        XCTAssertEqual(sut.getVolume(for: pid1), 0.3, accuracy: 0.01)
        XCTAssertEqual(sut.getVolume(for: pid2), 0.6, accuracy: 0.01)
        XCTAssertEqual(sut.getVolume(for: pid3), 0.9, accuracy: 0.01)
    }
    
    func testFeasibilityVerification() {
        // When
        let isFeasible = sut.verifyFeasibility()
        
        // Then
        XCTAssertTrue(isFeasible, "PoC should verify as feasible")
    }
    
    func testPrintStatus() {
        // Given
        sut.setVolume(0.5, for: 100)
        sut.setVolume(0.7, for: 200)
        
        // When
        sut.printStatus()
        
        // Then
        XCTAssertTrue(true, "Status printed successfully")
    }
}
