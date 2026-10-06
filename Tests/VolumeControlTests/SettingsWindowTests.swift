import AppKit
import SwiftUI
import XCTest
@testable import VolumeControl

@MainActor
final class SettingsWindowTests: XCTestCase {
    func testSettingsWindowOpensReusesAndReopensAfterClose() {
        var activations = 0
        let controller = SettingsWindowController(makeContent: { AnyView(Text("设置替身")) },
                                                  activateApplication: { activations += 1 })
        XCTAssertNil(controller.window)
        controller.showSettings()
        let first = controller.window
        XCTAssertTrue(first?.isVisible == true)
        XCTAssertEqual(first?.contentView?.bounds.size, NSSize(width: 360, height: 220))
        controller.showSettings()
        XCTAssertTrue(controller.window === first)
        first?.close()
        XCTAssertFalse(first?.isVisible == true)
        controller.showSettings()
        XCTAssertTrue(controller.window === first)
        XCTAssertTrue(first?.isVisible == true)
        XCTAssertEqual(activations, 3)
        first?.close()
    }

    func testSettingsContentHasUsableIntrinsicHeight() throws {
        let host = NSHostingView(rootView: SettingsView(loginItemController: SettingsLoginStub()))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(host.fittingSize.height, 180, "设置窗口不能因 Form 缺少理想高度而收缩")
        XCTAssertLessThanOrEqual(host.fittingSize.height, 400)
        if let path = ProcessInfo.processInfo.environment["VOLUMECONTROL_SETTINGS_SNAPSHOT"] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.appearance = NSAppearance(named: .aqua)
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
            window.contentView = nil
        }
    }
}

@MainActor
private struct SettingsLoginStub: LoginItemControlling {
    var status: LoginItemStatus { .disabled }
    func setEnabled(_ enabled: Bool) throws {}
}
