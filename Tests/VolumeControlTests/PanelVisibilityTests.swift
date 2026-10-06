import AppKit
import SwiftUI
import XCTest
@testable import VolumeControl

@MainActor
final class PanelVisibilityTests: XCTestCase {
    func testPanelRemainsOpaqueWhenMaterialChangesInPlace() async throws {
        let preferences = InterfacePreferences(storage: MemoryInterfacePreferences())
        preferences.options.motion = .off
        let model = VolumeControlModel(audio: FakeAudioService(), applicationProvider: FakeApplicationProvider(values: []),
            audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(),
            appAudio: UnsupportedAppAudioControl())
        let host = NSHostingView(rootView: VolumePanel(model: model, preferences: preferences, openSettings: {}).environment(\.panelReduceTransparency, true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 740), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        for surface in [InterfaceSurface.standard, .liquid, .frosted, .liquid, .standard] {
            preferences.options.surface = surface
            try await Task.sleep(nanoseconds: 80_000_000)
            host.setFrameSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            // 减少透明度必须在所有历史材质偏好下保持实色。
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let alpha = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 4)).alphaComponent
            XCTAssertGreaterThan(alpha, 0.9, "切换到 \(surface) 后不能隐藏整页")
        }
    }
}
