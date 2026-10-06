import AppKit
import SwiftUI
import XCTest
@testable import VolumeControl

@MainActor
final class LiquidGlassCardTests: XCTestCase {
    /// 在独立背景窗口上验证真实背景采样；离屏缓存和单独窗口 PNG 会丢失光学合成。
    func testLiquidCardSamplesBackdropAndRetainsMoreColorThanFrosted() async throws {
        guard let directory = ProcessInfo.processInfo.environment["VOLUMECONTROL_GLASS_CARD_SNAPSHOT"] else {
            throw XCTSkip("显式启用玻璃卡片屏幕合成验收")
        }
        guard #available(macOS 26.0, *) else { throw XCTSkip("原生玻璃需要 macOS 26+") }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
              !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast else {
            throw XCTSkip("系统无障碍设置要求降低透明度或增强对比度，跳过透色比较")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var options = InterfaceOptions()
        options.surface = .liquid
        options.theme = .light
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 240),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        func preview(_ options: InterfaceOptions) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("系统音量").font(.headline)
                Slider(value: .constant(0.37)).accessibilityLabel("测试音量")
            }
            .frame(width: 352, height: 88)
            .modifier(PanelCard())
            .frame(width: 480, height: 240)
            .modifier(InterfaceAppearance(options: options))
        }
        let hosting = NSHostingView(rootView: AnyView(preview(options)))
        window.contentView = hosting
        let backdrop = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let backdropView = NSHostingView(rootView: Color.red)
        backdrop.contentView = backdropView
        backdrop.orderFrontRegardless()
        window.orderFrontRegardless()
        backdrop.order(.below, relativeTo: window.windowNumber)
        defer { window.orderOut(nil); window.contentView = nil; backdrop.orderOut(nil); backdrop.contentView = nil }
        func sample(_ color: Color, name: String) async throws -> NSColor {
            backdropView.rootView = color
            try await Task.sleep(nanoseconds: 250_000_000)
            let rect = window.frame
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let path = "\(directory)/liquid-card-\(name).png"
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(top - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))", path]
            try capture.run()
            capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: URL(fileURLWithPath: path))))
            // 卡片内部的空白区域，避开文字和滑块；坐标换算支持 Retina。
            let sampled = try XCTUnwrap(bitmap.colorAt(x: 350 * bitmap.pixelsWide / 480,
                                                      y: 95 * bitmap.pixelsHigh / 240))
            return try XCTUnwrap(sampled.usingColorSpace(.sRGB))
        }
        let red = try await sample(.red, name: "red")
        let blue = try await sample(.blue, name: "blue")
        XCTAssertGreaterThan(red.redComponent - red.blueComponent, 0.04, "玻璃应采样窗口后面的红色")
        XCTAssertGreaterThan(blue.blueComponent - blue.redComponent, 0.04, "背景改变后玻璃应重新采样蓝色")
        options.surface = .frosted
        hosting.rootView = AnyView(preview(options))
        let frosted = try await sample(.blue, name: "frosted-reference")
        XCTAssertGreaterThan(blue.blueComponent - blue.redComponent,
                             frosted.blueComponent - frosted.redComponent + 0.04,
                             "本机浅色玻璃应保留更多背景颜色；液态与磨砂不能使用同一张平灰材质")
    }
}
