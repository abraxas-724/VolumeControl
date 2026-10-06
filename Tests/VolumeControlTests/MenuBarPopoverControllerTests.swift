import AppKit
import SwiftUI
import XCTest
@testable import VolumeControl

@MainActor
final class MenuBarPopoverControllerTests: XCTestCase {
    func testNativeAnimationFollowsPreferenceAndReducedMotion() {
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        var reducedMotion = false
        let controller = MenuBarPopoverController(preferences: preferences,
            content: AnyView(Text("Panel")), reduceMotion: { reducedMotion })
        XCTAssertTrue(controller.animates)
        preferences.options.motion = .off
        XCTAssertFalse(controller.animates)
        preferences.options.motion = .subtle
        XCTAssertTrue(controller.animates)
        reducedMotion = true
        preferences.options.accent = .teal
        XCTAssertFalse(controller.animates)
        controller.stop()
    }

    func testPopoverCanOpenCloseAndReopenWithoutRefreshingOnClose() async throws {
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        preferences.options.motion = .off
        var openings = 0
        let controller = MenuBarPopoverController(preferences: preferences,
            content: AnyView(Text("Panel").frame(width: 480, height: 200)),
            beforeOpening: { openings += 1 })
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 40, height: 40),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        window.contentView = anchor
        window.orderFront(nil)
        defer { controller.stop(); window.orderOut(nil); window.contentView = nil }
        for index in 1...3 {
            controller.toggle(relativeTo: anchor)
            XCTAssertTrue(controller.isShown)
            XCTAssertEqual(openings, index)
            controller.toggle(relativeTo: anchor)
            XCTAssertFalse(controller.isShown)
            XCTAssertEqual(openings, index)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// 显式启用的真窗口验收：点击本测试拥有的状态栏按钮，不修改真实音频或用户偏好。
    func testNativeStatusItemGlassTransitionsAndReopening() async throws {
        guard let directory = ProcessInfo.processInfo.environment["VOLUMECONTROL_POPOVER_SNAPSHOT"] else {
            throw XCTSkip("设置 VOLUMECONTROL_POPOVER_SNAPSHOT 可验收真实状态栏弹出窗口")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let oldPolicy = NSApplication.shared.activationPolicy()
        NSApplication.shared.setActivationPolicy(.accessory)
        defer { NSApplication.shared.setActivationPolicy(oldPolicy) }
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        let model = VolumeControlModel(audio: FakeAudioService(), applicationProvider: FakeApplicationProvider(values: []),
            audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(),
            appAudio: UnsupportedAppAudioControl())
        let controller = MenuBarPopoverController(preferences: preferences,
            content: AnyView(VolumePanel(model: model, preferences: preferences, openSettings: {})))
        controller.start()
        defer { controller.stop() }
        let button = try XCTUnwrap(controller.statusButton)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(button.window)
        func waitForVisibility(_ visible: Bool) async throws {
            for _ in 0..<120 {
                if controller.isShown == visible { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertEqual(controller.isShown, visible, "等待原生窗口动效完成")
        }
        button.performClick(nil)
        try await waitForVisibility(true)
        try await Task.sleep(nanoseconds: 350_000_000)
        for (index, surface) in [InterfaceSurface.standard, .liquid, .frosted, .liquid, .standard].enumerated() {
            preferences.options.surface = surface
            preferences.options.theme = index.isMultiple(of: 2) ? .light : .dark
            try await Task.sleep(nanoseconds: 250_000_000)
            XCTAssertTrue(controller.isShown)
            let window = try XCTUnwrap(controller.presentationWindow)
            let path = "\(directory)/\(index)-\(surface.rawValue).png"
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try capture.run()
            capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0)
            XCTAssertNotNil(NSImage(contentsOfFile: path))
        }
        for _ in 0..<3 {
            button.performClick(nil)
            try await waitForVisibility(false)
            button.performClick(nil)
            try await waitForVisibility(true)
            try await Task.sleep(nanoseconds: 350_000_000)
        }
    }
}
