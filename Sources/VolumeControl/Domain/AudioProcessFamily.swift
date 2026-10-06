import Darwin
import Foundation

/// 只按精确 bundle ID 或可验证的父子进程关系归属，避免把名称相似的应用音频混在一起。
struct AudioProcessFamily {
    static func matches(processID: pid_t, bundleID: String?, target: AppAudioTarget, parent: (pid_t) -> pid_t?) -> Bool {
        if processID == target.processID || bundleID == target.bundleID { return true }
        var visited: Set<pid_t> = []
        var pid = processID
        for _ in 0..<32 {
            guard pid > 1, visited.insert(pid).inserted, let ancestor = parent(pid) else { return false }
            if ancestor == target.processID { return true }
            pid = ancestor
        }
        return false
    }

    static func parentProcessID(_ pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size == MemoryLayout<kinfo_proc>.size else { return nil }
        return info.kp_eproc.e_ppid
    }
}
