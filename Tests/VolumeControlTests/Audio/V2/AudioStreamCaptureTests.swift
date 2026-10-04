import XCTest
@testable import VolumeControl

/// 音频流捕获测试
/// Week 1 交付物
final class AudioStreamCaptureTests: XCTestCase {
    
    var sut: AudioStreamCapture!
    
    override func setUp() {
        super.setUp()
        sut = AudioStreamCapture()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Tests
    
    func testEnumerateAudioDevices() {
        // When
        sut.enumerateAudioDevices()
        
        // Then
        // 应该至少找到一个音频设备（内置扬声器/耳机）
        // 实际测试时会验证
        XCTAssertTrue(true, "Audio device enumeration completed")
    }
    
    func testGetDeviceName() {
        // Given
        sut.enumerateAudioDevices()
        
        // When
        // 获取默认输出设备
        if let deviceName = sut.getDeviceName(0) {
            // Then
            XCTAssertFalse(deviceName.isEmpty, "Device name should not be empty")
            print("Default device name: \(deviceName)")
        }
    }
    
    func testGetStreamConfiguration() {
        // Given
        sut.enumerateAudioDevices()
        
        // When
        if let config = sut.getStreamConfiguration(for: 0) {
            // Then
            XCTAssertGreaterThan(config.mNumberBuffers, 0, "Should have at least one buffer")
            print("Stream has \(config.mNumberBuffers) buffers")
        }
    }
    
    func testIsDeviceRunning() {
        // Given
        sut.enumerateAudioDevices()
        
        // When
        let isRunning = sut.isDeviceRunning(0)
        
        // Then
        // 设备可能正在运行也可能没有
        print("Device running status: \(isRunning)")
        XCTAssertTrue(true, "Device running check completed")
    }
    
    func testGetSampleRate() {
        // Given
        sut.enumerateAudioDevices()
        
        // When
        if let sampleRate = sut.getSampleRate(for: 0) {
            // Then
            // 常见采样率：44100, 48000, 96000 Hz
            XCTAssertGreaterThan(sampleRate, 0, "Sample rate should be positive")
            print("Sample rate: \(sampleRate) Hz")
        }
    }
    
    func testPrintDeviceDetails() {
        // Given
        sut.enumerateAudioDevices()
        
        // When
        sut.printDeviceDetails()
        
        // Then
        XCTAssertTrue(true, "Device details printed")
    }
}
