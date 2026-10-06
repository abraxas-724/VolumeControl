import AppKit
import SwiftUI
import XCTest
@testable import VolumeControl

@MainActor
final class PanelAccessibilityTests: XCTestCase {
    /// AX 从独立进程访问真实窗口，避免 NSHostingView 的进程内虚拟节点尚未实例化。
    func testNormalRowRetainsStopActionInNativeAccessibilityTree() async throws {
        guard ProcessInfo.processInfo.environment["VOLUMECONTROL_ACCESSIBILITY_AUDIT"] == "1" else {
            throw XCTSkip("显式启用真实窗口 Accessibility 验收")
        }
        let oldPolicy = NSApplication.shared.activationPolicy()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        defer { NSApplication.shared.setActivationPolicy(oldPolicy) }
        let application = DiscoveredApplication(bundleID: "test.music", name: "Music",
            icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!, processID: 100,
            audioSessionStatus: .detected, isPlayingAudio: true)
        let audio = FakeAudioService()
        let model = VolumeControlModel(audio: audio, applicationProvider: FakeApplicationProvider(values: [application]),
            audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(),
            appAudio: ProcessTapVolumeController(factory: TestProcessFactory(), storage: MemoryAppAudioPreferences()),
            restoreRememberedAudio: false, deviceSwitchStorage: MemoryDeviceSwitchPreferences())
        await model.enableAppVolume(id: "test.music:100")
        defer { model.stopAppAudioControl() }
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        preferences.options.motion = .off
        let host = NSHostingView(rootView: VolumePanel(model: model, preferences: preferences, openSettings: {}))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 520),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "VolumeControl Accessibility Test"
        window.contentView = host
        defer { window.orderOut(nil); window.contentView = nil }
        window.orderFrontRegardless()
        window.makeKey()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scriptURL = directory.appendingPathComponent("probe.swift")
        let resultURL = directory.appendingPathComponent("result.json")
        try Self.probe.write(to: scriptURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [scriptURL.path, String(ProcessInfo.processInfo.processIdentifier), resultURL.path]
        try process.run()
        for _ in 0..<200 {
            if !process.isRunning { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if process.isRunning { process.terminate(); XCTFail("AX 验收超时"); return }
        XCTAssertEqual(process.terminationStatus, 0)
        let report = try JSONDecoder().decode(AccessibilityReport.self, from: Data(contentsOf: resultURL))
        guard report.windowFound else { throw XCTSkip("AX 服务未暴露 xctest 的真实窗口；需在应用进程中验收旁白") }
        let labels = report.labels
        for label in ["搜索应用", "系统音量", "筛选应用", "设置", "Music 音量", "停止 Music 应用音量控制", "静音 Music"] {
            XCTAssertTrue(labels.contains(label), "缺少无障碍控件：\(label)")
        }
        XCTAssertEqual(audio.volumeWrites, 0)
        XCTAssertEqual(audio.selectionWrites, 0)
    }

    private struct AccessibilityReport: Decodable {
        let windowFound: Bool
        let labels: [String]
    }

    private static let probe = #"""
    import Foundation
    import ApplicationServices
    guard AXIsProcessTrusted() else { exit(2) }
    let application = AXUIElementCreateApplication(pid_t(CommandLine.arguments[1])!)
    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if status != .success { return nil }
        return value
    }
    var labels: [String] = []
    var visited: [AXUIElement] = []
    func collect(_ element: AXUIElement, depth: Int) {
        guard depth < 20, !visited.contains(where: { CFEqual($0, element) }) else { return }
        visited.append(element)
        if attribute(element, kAXRoleAttribute) as? String == kAXMenuBarRole { return }
        for name in [kAXDescriptionAttribute, kAXTitleAttribute] {
            if let label = attribute(element, name) as? String { labels.append(label) }
        }
        for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { collect(child, depth: depth + 1) }
    }
    let windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
    var windowFound = false
    for window in windows {
        let title = attribute(window, kAXTitleAttribute) as? String ?? ""
        if title == "VolumeControl Accessibility Test", attribute(window, kAXRoleAttribute) as? String == kAXWindowRole {
            windowFound = true
            collect(window, depth: 0)
        }
    }
    struct Report: Encodable { let windowFound: Bool; let labels: [String] }
    try JSONEncoder().encode(Report(windowFound: windowFound, labels: labels)).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    """#
}
