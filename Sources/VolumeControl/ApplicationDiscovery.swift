import AppKit
import CoreAudio
import Foundation

struct DiscoveredApplication {
    let bundleID: String
    let name: String
    let icon: NSImage
    let processID: pid_t
    let hasAudioSession: Bool
}

protocol ApplicationProvider {
    func applications(excluding bundleID: String?) -> [DiscoveredApplication]
}

struct WorkspaceApplicationProvider: ApplicationProvider {
    private let detector = AudioProcessDetector()

    func applications(excluding bundleID: String?) -> [DiscoveredApplication] {
        let audioProcesses = Set(detector.processes().map(\.processID))
        return NSWorkspace.shared.runningApplications
            .filter { application in
                application.activationPolicy == .regular && application.bundleIdentifier != bundleID
            }
            .compactMap { application in
                guard let bundleID = application.bundleIdentifier else { return nil }
                return DiscoveredApplication(
                    bundleID: bundleID,
                    name: application.localizedName ?? bundleID,
                    icon: application.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                    processID: application.processIdentifier,
                    hasAudioSession: audioProcesses.contains(application.processIdentifier)
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

    func processes() -> [AudioProcess] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.stride
        guard count > 0 else { return [] }
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &objectIDs) == noErr else { return [] }
        return objectIDs.compactMap(process(from:))
    }

    private func process(from objectID: AudioObjectID) -> AudioProcess? {
        var pidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processID = pid_t(0)
        var pidSize = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(objectID, &pidAddress, 0, nil, &pidSize, &processID) == noErr else { return nil }

        var bundleAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundleID: Unmanaged<CFString>?
        var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let bundleStatus = AudioObjectGetPropertyData(objectID, &bundleAddress, 0, nil, &bundleSize, &bundleID)
        let bundle = bundleStatus == noErr ? bundleID?.takeUnretainedValue() as String? : nil
        return AudioProcess(processID: processID, bundleID: bundle)
    }
}
