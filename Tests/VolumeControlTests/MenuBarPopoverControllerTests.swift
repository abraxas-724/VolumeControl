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

    func testGlassBackgroundTransitionsPreserveWindowAndRespectReducedTransparency() {
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        preferences.options.motion = .off
        var reducedTransparency = false
        let controller = MenuBarPopoverController(preferences: preferences,
            content: AnyView(Text("Readable content").frame(width: 480, height: 200)),
            reduceTransparency: { reducedTransparency })
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 40, height: 40),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        window.contentView = anchor
        window.orderFront(nil)
        defer { controller.stop(); window.orderOut(nil); window.contentView = nil }
        controller.toggle(relativeTo: anchor)
        let first = controller.presentationWindow
        XCTAssertTrue(first?.isOpaque == true)
        for surface in [InterfaceSurface.liquid, .frosted, .liquid, .standard] {
            preferences.options.surface = surface
            XCTAssertTrue(controller.isShown)
            XCTAssertTrue(controller.presentationWindow === first)
            XCTAssertEqual(first?.isOpaque, surface == .standard)
        }
        preferences.options.surface = .liquid
        reducedTransparency = true
        preferences.options.accent = .teal
        XCTAssertTrue(first?.isOpaque == true)
        XCTAssertEqual(first?.backgroundColor, NSColor.windowBackgroundColor)
    }

    func testAccessibilityNotificationUpdatesOpenGlassWithoutChangingPreferences() {
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        preferences.options.surface = .liquid
        preferences.options.motion = .off
        let originalOptions = preferences.options
        let notifications = NotificationCenter()
        var reducedTransparency = false
        let controller = MenuBarPopoverController(preferences: preferences,
            content: AnyView(Text("Readable content").frame(width: 480, height: 200)),
            reduceTransparency: { reducedTransparency }, workspaceNotifications: notifications)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 40, height: 40),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        window.contentView = anchor
        window.orderFront(nil)
        defer { controller.stop(); window.orderOut(nil); window.contentView = nil }
        controller.toggle(relativeTo: anchor)
        let first = controller.presentationWindow
        for reduced in [true, false, true, false] {
            reducedTransparency = reduced
            notifications.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            XCTAssertTrue(controller.isShown)
            XCTAssertTrue(controller.presentationWindow === first)
            XCTAssertEqual(first?.isOpaque, reduced)
            XCTAssertEqual(first?.backgroundColor, reduced ? NSColor.windowBackgroundColor : NSColor.clear)
            XCTAssertEqual(preferences.options, originalOptions)
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
        let audio = FakeAudioService()
        audio.volume = 0.37
        let application = DiscoveredApplication(bundleID: "test.chrome", name: "Google Chrome",
            icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!, processID: 100,
            audioSessionStatus: .detected, isPlayingAudio: true)
        let appAudio = ProcessTapVolumeController(factory: TestProcessFactory(), storage: MemoryAppAudioPreferences())
        let model = VolumeControlModel(audio: audio, applicationProvider: FakeApplicationProvider(values: [application]),
            audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(),
            appAudio: appAudio)
        await model.enableAppVolume(id: "test.chrome:100")
        model.setAppVolume(id: "test.chrome:100", volume: 0.83)
        defer { model.stopAppAudioControl() }
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
        // 用自己的彩色窗口检验背景采样，截图不依赖桌面壁纸和其他应用内容。
        let panelWindow = try XCTUnwrap(controller.presentationWindow)
        let backdrop = NSWindow(contentRect: panelWindow.frame.insetBy(dx: -30, dy: -30),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let backdropView = NSHostingView(rootView: AnyView(HStack(spacing: 0) { Color.red; Color.green; Color.blue }))
        backdrop.contentView = backdropView
        backdrop.level = panelWindow.level
        backdrop.orderFrontRegardless()
        backdrop.order(.below, relativeTo: panelWindow.windowNumber)
        XCTAssertTrue(backdrop.isVisible)
        defer { backdrop.orderOut(nil); backdrop.contentView = nil }
        func captureComposite(_ window: NSWindow, name: String) throws {
            let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
            let rect = window.frame
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            let path = "\(directory)/\(name)-composite.png"
            capture.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(screenTop - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))", path]
            try capture.run()
            capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0)
            XCTAssertNotNil(NSImage(contentsOfFile: path))
        }
        let appearances: [(InterfaceSurface, InterfaceTheme)] = [(.standard, .light), (.liquid, .light),
            (.frosted, .light), (.liquid, .dark), (.standard, .dark)]
        for (index, (surface, theme)) in appearances.enumerated() {
            preferences.options.surface = surface
            preferences.options.theme = theme
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
            if surface == .liquid || surface == .frosted {
                try captureComposite(window, name: "\(index)-\(surface.rawValue)")
            }
        }
        // 与控制中心参考图类似的中性背景；颜色模式由本机系统提供。
        backdropView.rootView = AnyView(LinearGradient(colors: [.white, .gray],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        preferences.options.theme = .system
        preferences.options.surface = .liquid
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(controller.isShown)
        XCTAssertNil(controller.presentationWindow?.appearance)
        try captureComposite(try XCTUnwrap(controller.presentationWindow), name: "system-liquid")
        for theme in [InterfaceTheme.light, .dark] {
            preferences.options.theme = theme
            try await Task.sleep(nanoseconds: 250_000_000)
            try captureComposite(try XCTUnwrap(controller.presentationWindow), name: "neutral-liquid-\(theme.rawValue)")
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
