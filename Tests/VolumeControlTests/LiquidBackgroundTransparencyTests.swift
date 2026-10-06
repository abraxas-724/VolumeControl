import AppKit
import SwiftUI
import XCTest
@testable import VolumeControl

private struct BackdropPreview: View {
    @ObservedObject var preferences: InterfacePreferences
    var body: some View {
        Color.clear.frame(width: 480, height: 320).background(PanelBackdrop())
            .modifier(InterfaceAppearance(options: preferences.options))
    }
}

@MainActor
final class LiquidBackgroundTransparencyTests: XCTestCase {
    /// 在真正的原生弹出窗口中检查背景，避免仅验证卡片而漏掉整页磨砂遮挡。
    func testLiquidBackgroundRetainsContrastOfContentBehindPopover() async throws {
        guard let directory = ProcessInfo.processInfo.environment["VOLUMECONTROL_GLASS_BACKGROUND_SNAPSHOT"] else {
            throw XCTSkip("显式启用液态背景屏幕合成验收")
        }
        guard #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
              !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast else {
            throw XCTSkip("本项检查原生玻璃透明外观，不覆盖旧系统或无障碍实色模式")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let oldPolicy = NSApplication.shared.activationPolicy()
        NSApplication.shared.setActivationPolicy(.accessory)
        defer { NSApplication.shared.setActivationPolicy(oldPolicy) }
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        preferences.options.motion = .off
        preferences.options.theme = .light
        preferences.options.surface = .liquid
        let controller = MenuBarPopoverController(preferences: preferences, content: AnyView(BackdropPreview(preferences: preferences)))
        controller.start()
        defer { controller.stop() }
        let button = try XCTUnwrap(controller.statusButton)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(button.window)
        button.performClick(nil)
        try await Task.sleep(nanoseconds: 250_000_000)
        let window = try XCTUnwrap(controller.presentationWindow)
        let backdrop = NSWindow(contentRect: window.frame.insetBy(dx: -30, dy: -30),
            styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.contentView = NSHostingView(rootView: HStack(spacing: 0) {
            ForEach(0..<8) { index in (index.isMultiple(of: 2) ? Color.black : Color.white) }
        })
        backdrop.level = window.level
        backdrop.orderFrontRegardless()
        backdrop.order(.below, relativeTo: window.windowNumber)
        defer { backdrop.orderOut(nil); backdrop.contentView = nil }
        try await Task.sleep(nanoseconds: 250_000_000)
        let rect = window.frame
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        func contrast(name: String) async throws -> Double {
            try await Task.sleep(nanoseconds: 250_000_000)
            let path = "\(directory)/liquid-background-\(name).png"
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(top - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))", path]
            try capture.run()
            capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: URL(fileURLWithPath: path))))
            func luminance(stripe: Double) throws -> Double {
                let x = stripe * backdrop.frame.width / 8 - 30
                let color = try XCTUnwrap(bitmap.colorAt(x: Int(x * Double(bitmap.pixelsWide) / rect.width),
                                                         y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
            }
            let value = try luminance(stripe: 3.5) - luminance(stripe: 4.5)
            print("液态背景对比度 [\(name)]：\(value)")
            XCTAssertTrue(controller.isShown)
            XCTAssertTrue(controller.presentationWindow === window)
            return value
        }
        let clear = try await contrast(name: "default-clear")
        XCTAssertGreaterThan(clear, 0.7, "液态模式底层应保留大部分背景对比度，不能被浓磨砂盖住")
        preferences.options.glassBackgroundTransparency = 0
        let frosted = try await contrast(name: "minimum-transparency")
        XCTAssertLessThan(frosted, clear - 0.4, "透明度滑块必须实际改变背景遮挡")
        preferences.options.glassBackgroundTransparency = 1
        let maximum = try await contrast(name: "maximum-transparency")
        XCTAssertGreaterThan(maximum, clear + 0.05)
        preferences.options.glassStyle = .system
        let adaptive = try await contrast(name: "system-adaptive")
        XCTAssertLessThan(adaptive, clear - 0.4)
    }
}
