import Foundation
import CoreAudio
import AppKit

/// 进程音频标识符 - 识别音频流对应的进程
/// Week 1 Day 3-4 交付物
struct ProcessAudioStream {
    let processID: pid_t
    let bundleID: String?
    let processName: String
    let streamID: AudioStreamID?
    var volume: Float = 1.0
    var isMuted: Bool = false
}

class ProcessAudioIdentifier {
    
    // MARK: - Properties
    
    private var processStreams: [ProcessAudioStream] = []
    
    // MARK: - Public Methods
    
    /// 枚举所有正在播放音频的进程
    func enumerateAudioProcesses() -> [ProcessAudioStream] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        
        // 获取进程列表大小
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard sizeStatus == noErr else {
            print("Failed to get process object list size: \(sizeStatus)")
            return []
        }
        
        // 获取进程对象列表
        let processCount = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        var processObjects = [AudioObjectID](repeating: 0, count: processCount)
        
        let getStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &processObjects
        )
        
        guard getStatus == noErr else {
            print("Failed to get process object list: \(getStatus)")
            return []
        }
        
        var streams: [ProcessAudioStream] = []
        
        for processObject in processObjects {
            if let stream = getProcessInfo(for: processObject) {
                streams.append(stream)
            }
        }
        
        self.processStreams = streams
        return streams
    }
    
    /// 获取进程信息
    private func getProcessInfo(for processObject: AudioObjectID) -> ProcessAudioStream? {
        // 获取进程 ID
        guard let pid = getProcessID(for: processObject) else {
            return nil
        }
        
        // 获取进程名称
        let processName = getProcessName(for: pid)
        
        // 获取 Bundle ID
        let bundleID = getBundleID(for: pid)
        
        return ProcessAudioStream(
            processID: pid,
            bundleID: bundleID,
            processName: processName,
            streamID: nil,
            volume: 1.0,
            isMuted: false
        )
    }
    
    /// 获取进程 ID
    private func getProcessID(for processObject: AudioObjectID) -> pid_t? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList, // 实际应该有专门的属性
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var pid: pid_t = 0
        var propertySize: UInt32 = UInt32(MemoryLayout<pid_t>.size)
        
        let status = AudioObjectGetPropertyData(
            processObject,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &pid
        )
        
        guard status == noErr else {
            return nil
        }
        
        return pid
    }
    
    /// 获取进程名称
    private func getProcessName(for pid: pid_t) -> String {
        // 使用 NSRunningApplication 获取应用信息
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.localizedName ?? "Unknown"
        }
        
        // 备选：使用 sysctl
        var name = [CChar](repeating: 0, count: 1024)
        var len = name.count
        
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        
        if sysctl(&mib, u_int(mib.count), &name, &len, nil, 0) == 0 {
            return String(cString: name)
        }
        
        return "Unknown Process (\(pid))"
    }
    
    /// 获取 Bundle ID
    private func getBundleID(for pid: pid_t) -> String? {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.bundleIdentifier
        }
        return nil
    }
    
    /// 检查进程是否有音频会话
    func hasAudioSession(for pid: pid_t) -> Bool {
        return processStreams.contains { $0.processID == pid }
    }
    
    /// 根据 Bundle ID 查找进程
    func findProcess(byBundleID bundleID: String) -> ProcessAudioStream? {
        return processStreams.first { $0.bundleID == bundleID }
    }
    
    /// 根据进程名称查找进程
    func findProcesses(byName name: String) -> [ProcessAudioStream] {
        return processStreams.filter { $0.processName.contains(name) }
    }
    
    // MARK: - Debug
    
    /// 打印所有音频进程
    func printAudioProcesses() {
        print("\n=== Audio Processes ===")
        let processes = enumerateAudioProcesses()
        
        if processes.isEmpty {
            print("No audio processes found")
        } else {
            for process in processes {
                print("\nProcess: \(process.processName)")
                print("  PID: \(process.processID)")
                if let bundleID = process.bundleID {
                    print("  Bundle ID: \(bundleID)")
                }
                print("  Volume: \(Int(process.volume * 100))%")
                print("  Muted: \(process.isMuted)")
            }
        }
        
        print("=======================\n")
    }
}
