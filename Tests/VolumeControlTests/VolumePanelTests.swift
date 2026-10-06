import AppKit
import SwiftUI
import XCTest
@testable import VolumeControl

@MainActor
final class VolumePanelTests: XCTestCase {
    func testSmallScreenCapsPanelWithLongNamesManyAppsAndInlineError() async throws {
        let audio = FakeAudioService()
        audio.deviceName = "很长的中文音频输出设备名称 — External Display Audio Device"
        let applications = (0..<40).map { index in
            DiscoveredApplication(bundleID: "test.\(index)", name: "长应用名称与中文混合 — Music Conference Application \(index)",
                icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!, processID: Int32(100 + index),
                audioSessionStatus: .detected, isPlayingAudio: true)
        }
        let model = VolumeControlModel(audio: audio, applicationProvider: FakeApplicationProvider(values: applications),
            audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(),
            appAudio: UnsupportedAppAudioControl(), restoreRememberedAudio: false, deviceSwitchStorage: MemoryDeviceSwitchPreferences())
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        preferences.options.motion = .off
        let host = NSHostingView(rootView: VolumePanel(model: model, preferences: preferences, openSettings: {})
            .environment(\.panelMaximumHeight, 520))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 520),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for fail in [false, true] {
            audio.shouldFailVolume = fail
            model.refresh()
            try await Task.sleep(nanoseconds: 100_000_000)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, 430, accuracy: 1)
            XCTAssertLessThanOrEqual(host.fittingSize.height, 521, "列表必须为错误和长名称让出屏幕空间")
            XCTAssertEqual(model.apps.count, 40)
        }
        XCTAssertEqual(audio.volumeWrites, 0)
        XCTAssertEqual(audio.selectionWrites, 0)
    }

    func testApplicationListKeepsUsableHeightAndRefreshDoesNotWriteSystemVolume() async throws {
        let audio = FakeAudioService()
        let names = ["腾讯会议", "Google Chrome", "Music", "Safari", "Visual Studio Code", "Slack"]
        let applications = names.enumerated().map { index, name in
            DiscoveredApplication(bundleID: "test.\(index)", name: name, icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!, processID: Int32(100 + index), audioSessionStatus: .detected, isPlayingAudio: true)
        }
        let control = ProcessTapVolumeController(factory: TestProcessFactory(), storage: MemoryAppAudioPreferences())
        let model = VolumeControlModel(audio: audio, applicationProvider: FakeApplicationProvider(values: applications), audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(), appAudio: control)
        await model.enableAppVolume(id: "test.0:100")
        model.setAppVolume(id: "test.0:100", volume: 0.4)
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        preferences.options.motion = .off
        let host = NSHostingView(rootView: VolumePanel(model: model, preferences: preferences, openSettings: {}))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        XCTAssertGreaterThanOrEqual(size.height, 500, "列表不能收缩到仅容纳一个应用")
        let sizing = NSHostingController(rootView: VolumePanel(model: model, preferences: preferences, openSettings: {}))
        let normal = sizing.sizeThatFits(in: NSSize(width: 430, height: 760))
        let oversized = sizing.sizeThatFits(in: NSSize(width: 430, height: 1100))
        XCTAssertEqual(normal.height, oversized.height, accuracy: 1, "面板不能拉伸成上下空白")
        XCTAssertEqual(normal.width, 430, accuracy: 1)
        preferences.options.density = .compact
        preferences.options.theme = .dark
        preferences.options.showPercentage = false
        preferences.options.defaultToEnabledApps = true
        preferences.options.showTips = false
        preferences.options.showAdvanced = false
        try await Task.sleep(nanoseconds: 50_000_000)
        let compact = sizing.sizeThatFits(in: NSSize(width: 430, height: 1100))
        XCTAssertLessThan(compact.height, normal.height)
        XCTAssertEqual(audio.volumeWrites, 0)
        XCTAssertEqual(audio.selectionWrites, 0)
        preferences.resetAppearance()
        preferences.options.motion = .off
        audio.volume = 0.7
        model.refresh()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(audio.volumeWrites, 0, "刷新系统音量不能触发 UI 反向写入")
        if let path = ProcessInfo.processInfo.environment["VOLUMECONTROL_PANEL_SNAPSHOT"] {
            func capture(_ destination: String, scheme: ColorScheme) async throws {
                let preview = NSHostingView(rootView: VolumePanel(model: model, preferences: preferences, openSettings: {}).environment(\.colorScheme, scheme))
                preview.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = preview
                try await Task.sleep(nanoseconds: 50_000_000)
                preview.setFrameSize(preview.fittingSize)
                preview.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(preview.bitmapImageRepForCachingDisplay(in: preview.bounds))
                preview.cacheDisplay(in: preview.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: destination))
                if ProcessInfo.processInfo.environment["VOLUMECONTROL_NATIVE_SCREENSHOT"] == "1" {
                    window.setContentSize(preview.fittingSize)
                    window.center()
                    window.orderFrontRegardless()
                    try await Task.sleep(nanoseconds: 150_000_000)
                    let capture = Process()
                    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    let screenPath = URL(fileURLWithPath: destination).deletingPathExtension().path + "-screen.png"
                    capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), screenPath]
                    try capture.run()
                    capture.waitUntilExit()
                    XCTAssertEqual(capture.terminationStatus, 0, "窗口截图需要屏幕录制许可")
                    window.orderOut(nil)
                }

            }
            let base = URL(fileURLWithPath: path).deletingPathExtension().path
            try await capture(path, scheme: .light)
            try await capture(base + "-dark.png", scheme: .dark)
            preferences.options.surface = .liquid
            preferences.options.theme = .dark
            preferences.options.accent = .teal
            try await capture(base + "-glass-dark.png", scheme: .dark)
            preferences.options.density = .compact
            try await capture(base + "-compact.png", scheme: .dark)
            preferences.resetAppearance()
            preferences.options.motion = .off
            audio.selectionError = AudioServiceError.operationFailed(operation: "切换默认输出设备", status: -50)
            model.selectOutputDevice(2)
            try await capture(base + "-error.png", scheme: .light)
        }
        window.contentView = nil
        model.stopAppAudioControl()
    }
}
