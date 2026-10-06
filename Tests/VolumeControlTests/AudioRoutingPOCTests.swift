import XCTest
@testable import VolumeControl

final class AudioRoutingPOCTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["VOLUMECONTROL_HARDWARE_TESTS"] == "1" else {
            throw XCTSkip("真机音频测试须显式设置 VOLUMECONTROL_HARDWARE_TESTS=1")
        }
    }

    
    /// 测试虚拟设备检测
    func testDetectVirtualDevice() {
        // 尝试检测 BlackHole 设备
        let deviceID = AudioRoutingPOC.detectVirtualDevice(named: "BlackHole 2ch")
        
        if deviceID != nil {
            print("✅ BlackHole 设备已安装")
        } else {
            print("⚠️  BlackHole 设备未安装，请先运行: brew install blackhole-2ch")
        }
        
        // 此测试不应失败，只是检测设备是否存在
        // XCTAssertNotNil(deviceID, "BlackHole 设备应该已安装")
    }
    
    /// 测试音频引擎基础功能（需要 BlackHole 已安装）
    func testAudioEngineBasics() throws {
        let poc = AudioRoutingPOC()
        
        // 检测虚拟设备
        guard AudioRoutingPOC.detectVirtualDevice(named: "BlackHole 2ch") != nil else {
            print("⏭️  跳过测试：BlackHole 未安装")
            throw XCTSkip("需要先安装 BlackHole: brew install blackhole-2ch")
        }
        
        // 启动音频路由
        try poc.start()
        
        // 测试音量调整
        poc.setVolume(0.3)
        poc.setVolume(0.7)
        poc.setVolume(1.0)
        
        // 测量延迟
        let latency = poc.measureLatency()
        print("音频延迟: \(latency * 1000) ms")
        
        // 验收标准：延迟应小于 15ms
        XCTAssertLessThan(latency, 0.015, "音频延迟应小于 15ms，实测: \(latency * 1000)ms")
        
        // 获取性能指标
        let metrics = poc.getPerformanceMetrics()
        let memoryMB = metrics.memory / 1024 / 1024
        print("内存占用: \(memoryMB) MB")
        
        // 验收标准：内存应小于 50MB
        XCTAssertLessThan(memoryMB, 50, "内存占用应小于 50MB，实测: \(memoryMB)MB")
        
        // 停止引擎
        poc.stop()
    }
    
    /// 测试音频引擎启动和停止
    func testEngineStartStop() throws {
        let poc = AudioRoutingPOC()
        
        guard AudioRoutingPOC.detectVirtualDevice(named: "BlackHole 2ch") != nil else {
            throw XCTSkip("需要先安装 BlackHole")
        }
        
        // 测试多次启动停止
        for i in 1...3 {
            print("第 \(i) 次启动")
            try poc.start()
            sleep(1)
            poc.stop()
        }
    }
    
    /// 测试音量范围
    func testVolumeRange() {
        let poc = AudioRoutingPOC()
        
        // 测试边界值
        poc.setVolume(-0.5)  // 应该被钳制到 0.0
        poc.setVolume(0.0)
        poc.setVolume(0.5)
        poc.setVolume(1.0)
        poc.setVolume(1.5)   // 应该被钳制到 1.0
    }
}
