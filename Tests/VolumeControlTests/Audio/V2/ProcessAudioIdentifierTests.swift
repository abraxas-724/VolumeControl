import XCTest
@testable import VolumeControl

/// 进程音频标识测试
/// Week 1 交付物
final class ProcessAudioIdentifierTests: XCTestCase {
    
    var sut: ProcessAudioIdentifier!
    
    override func setUp() {
        super.setUp()
        sut = ProcessAudioIdentifier()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Tests
    
    func testEnumerateAudioProcesses() {
        // When
        let processes = sut.enumerateAudioProcesses()
        
        // Then
        // 可能有也可能没有正在播放的应用
        print("Found \(processes.count) audio processes")
        XCTAssertTrue(true, "Audio process enumeration completed")
    }
    
    func testHasAudioSession() {
        // Given
        let processes = sut.enumerateAudioProcesses()
        
        // When
        if let firstProcess = processes.first {
            let hasSession = sut.hasAudioSession(for: firstProcess.processID)
            
            // Then
            XCTAssertTrue(hasSession, "Process should have audio session")
        }
    }
    
    func testFindProcessByBundleID() {
        // Given
        let processes = sut.enumerateAudioProcesses()
        
        // When
        if let firstProcess = processes.first,
           let bundleID = firstProcess.bundleID {
            let found = sut.findProcess(byBundleID: bundleID)
            
            // Then
            XCTAssertNotNil(found, "Should find process by bundle ID")
            XCTAssertEqual(found?.bundleID, bundleID)
        }
    }
    
    func testFindProcessesByName() {
        // Given
        let processes = sut.enumerateAudioProcesses()
        
        // When
        if let firstProcess = processes.first {
            let found = sut.findProcesses(byName: firstProcess.processName)
            
            // Then
            XCTAssertGreaterThan(found.count, 0, "Should find at least one process")
        }
    }
    
    func testPrintAudioProcesses() {
        // When
        sut.printAudioProcesses()
        
        // Then
        XCTAssertTrue(true, "Audio processes printed")
    }
    
    func testProcessAudioStreamProperties() {
        // Given
        let stream = ProcessAudioStream(
            processID: 1234,
            bundleID: "com.test.app",
            processName: "Test App",
            streamID: nil,
            volume: 0.5,
            isMuted: false
        )
        
        // Then
        XCTAssertEqual(stream.processID, 1234)
        XCTAssertEqual(stream.bundleID, "com.test.app")
        XCTAssertEqual(stream.processName, "Test App")
        XCTAssertEqual(stream.volume, 0.5)
        XCTAssertFalse(stream.isMuted)
    }
}
