import AppKit
import CoreAudio
import Foundation

struct DiscoveredApplication {
    let bundleID: String
    let name: String
    let icon: NSImage
    let processID: pid_t
    let audioSessionStatus: AudioSessionStatus
}

enum AudioSessionStatus: Equatable {
    case detected
    case notDetected
    case unavailable(String)
}

protocol ApplicationProvider {
    func applications(excluding bundleID: String?) -> [DiscoveredApplication]
}

struct WorkspaceApplicationProvider: ApplicationProvider {
    private let detector = AudioProcessDetector()

    func applications(excluding bundleID: String?) -> [DiscoveredApplication] {
        let processResult = Result { Set(try detector.processes().map(\.processID)) }
        return NSWorkspace.shared.runningApplications
            .filter { application in
                application.activationPolicy == .regular && application.bundleIdentifier != bundleID
            }
            .compactMap { application in
                guard let bundleID = application.bundleIdentifier else { return nil }
                let audioSessionStatus: AudioSessionStatus
                switch processResult {
                case .success(let processIDs):
                    audioSessionStatus = processIDs.contains(application.processIdentifier) ? .detected : .notDetected
                case .failure(let error):
                    audioSessionStatus = .unavailable(error.localizedDescription)
                }
                return DiscoveredApplication(
                    bundleID: bundleID,
                    name: application.localizedName ?? bundleID,
                    icon: application.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                    processID: application.processIdentifier,
                    audioSessionStatus: audioSessionStatus
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct AudioProcess {
    let processID: pid_t
    let bundleID: String?
}

struct AudioProcessDetector {
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)

    func processes() throws -> [AudioProcess] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size)
        guard sizeStatus == noErr else {
            throw AudioServiceError.operationFailed(operation: "读取进程音频会话列表大小", status: sizeStatus)
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return [] }
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        let dataStatus = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &objectIDs)
        guard dataStatus == noErr else {
            throw AudioServiceError.operationFailed(operation: "读取进程音频会话列表", status: dataStatus)
        }
        return try objectIDs.map(process(from:))
    }

    private func process(from objectID: AudioObjectID) throws -> AudioProcess {
        var pidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processID = pid_t(0)
        var pidSize = UInt32(MemoryLayout<pid_t>.size)
        let pidStatus = AudioObjectGetPropertyData(objectID, &pidAddress, 0, nil, &pidSize, &processID)
        guard pidStatus == noErr else {
            throw AudioServiceError.operationFailed(operation: "读取进程音频会话 PID", status: pidStatus)
        }

        var bundleAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundleID: Unmanaged<CFString>?
        var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let bundleStatus = AudioObjectGetPropertyData(objectID, &bundleAddress, 0, nil, &bundleSize, &bundleID)
        guard bundleStatus == noErr else {
            throw AudioServiceError.operationFailed(operation: "读取进程音频会话 Bundle ID", status: bundleStatus)
        }
        let bundle = bundleID?.takeUnretainedValue() as String?
        return AudioProcess(processID: processID, bundleID: bundle)
    }
}
