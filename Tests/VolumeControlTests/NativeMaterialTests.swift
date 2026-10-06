import AppKit
import SwiftUI
import XCTest
@testable import VolumeControl

@MainActor
final class NativeMaterialTests: XCTestCase {
    func testReducedTransparencyUsesOpaqueBackgroundForBothColorSchemes() throws {
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: Color.clear.frame(width: 430, height: 240)
                .background(PanelBackdrop())
                .environment(\.panelReduceTransparency, true)
                .environment(\.colorScheme, scheme))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 240),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            defer { window.contentView = nil }
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let color = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
            XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
        }
    }
}
