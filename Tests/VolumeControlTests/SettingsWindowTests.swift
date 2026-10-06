import AppKit
import SwiftUI
import XCTest
@testable import VolumeControl

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testSettingsWindowOpensReusesAndReopensAfterClose() {
        var activations = 0
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        let controller = SettingsWindowController(preferences: preferences, makeContent: { AnyView(Text("设置替身")) },
                                                  activateApplication: { activations += 1 })
        XCTAssertNil(controller.window)
        controller.showSettings()
        let first = controller.window
        XCTAssertTrue(first?.isVisible == true)
        XCTAssertEqual(first?.contentView?.bounds.size, NSSize(width: 500, height: 660))
        controller.showSettings()
        XCTAssertTrue(controller.window === first)
        first?.close()
        XCTAssertFalse(first?.isVisible == true)
        controller.showSettings()
        XCTAssertTrue(controller.window === first)
        XCTAssertTrue(first?.isVisible == true)
        XCTAssertEqual(activations, 3)
        preferences.options.theme = .dark
        XCTAssertEqual(first?.appearance?.name, .darkAqua)
        preferences.options.theme = .light
        XCTAssertEqual(first?.appearance?.name, .aqua)
        preferences.options.theme = .system
        XCTAssertNil(first?.appearance)
        first?.close()
    }

    func testSettingsContentHasUsableIntrinsicHeight() async throws {
        let host = NSHostingView(rootView: SettingsView(preferences: InterfacePreferences(storage: MemoryInterfacePreferences()), loginItemController: SettingsLoginStub()))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(host.fittingSize.height, 600, "设置窗口不能因 Form 缺少理想高度而收缩")
        XCTAssertLessThanOrEqual(host.fittingSize.height, 700)
        if let path = ProcessInfo.processInfo.environment["VOLUMECONTROL_SETTINGS_SNAPSHOT"] {
            let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
            preferences.options.motion = .off
            func capture(_ destination: String, page: Int = 0) async throws {
                let preview = NSHostingView(rootView: SettingsView(preferences: preferences,
                    loginItemController: SettingsLoginStub(), initialPage: page))
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 660),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = preview
                preview.appearance = NSAppearance(named: preferences.options.theme == .dark ? .darkAqua : .aqua)
                try await Task.sleep(nanoseconds: 50_000_000)
                preview.setFrameSize(preview.fittingSize)
                preview.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(preview.bitmapImageRepForCachingDisplay(in: preview.bounds))
                preview.cacheDisplay(in: preview.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: destination))

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
                window.contentView = nil
            }
            let base = URL(fileURLWithPath: path).deletingPathExtension().path
            try await capture(path)
            try await capture(base + "-general.png", page: 1)
            preferences.options.theme = .dark
            preferences.options.surface = .liquid
            preferences.options.accent = .teal
            try await capture(base + "-glass-dark.png")
        }
    }
}

@MainActor
private struct SettingsLoginStub: LoginItemControlling {
    var status: LoginItemStatus { .disabled }
    func setEnabled(_ enabled: Bool) throws {}
}
