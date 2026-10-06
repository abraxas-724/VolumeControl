import AppKit
import SwiftUI
import XCTest
@testable import VolumeControl

@MainActor
final class VolumePanelTests: XCTestCase {
    func testApplicationListKeepsUsableHeightAndRefreshDoesNotWriteSystemVolume() async throws {
        let audio = FakeAudioService()
        let names = ["腾讯会议", "Google Chrome", "Music", "Safari", "Visual Studio Code", "Slack"]
        let applications = names.enumerated().map { index, name in
            DiscoveredApplication(bundleID: "test.\(index)", name: name, icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!, processID: Int32(100 + index), audioSessionStatus: .detected)
        }
        let control = ProcessTapVolumeController(factory: TestProcessFactory(), storage: MemoryAppAudioPreferences())
        let model = VolumeControlModel(audio: audio, applicationProvider: FakeApplicationProvider(values: applications), audioRouter: ModelRoutingStub(), monitorDevices: false, inputPermission: ModelPermissionStub(), appAudio: control)
        await model.enableAppVolume(id: "test.0:100")
        model.setAppVolume(id: "test.0:100", volume: 0.4)
        let host = NSHostingView(rootView: VolumePanel(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        XCTAssertGreaterThanOrEqual(size.height, 570, "列表不能收缩到仅容纳一个应用")
        audio.volume = 0.7
        model.refresh()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(audio.volumeWrites, 0, "刷新系统音量不能触发 UI 反向写入")
        if let path = ProcessInfo.processInfo.environment["VOLUMECONTROL_PANEL_SNAPSHOT"] {
            func capture(_ destination: String, scheme: ColorScheme) throws {
                let preview = NSHostingView(rootView: VolumePanel(model: model).environment(\.colorScheme, scheme))
                preview.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                window.contentView = preview
                preview.setFrameSize(preview.fittingSize)
                preview.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(preview.bitmapImageRepForCachingDisplay(in: preview.bounds))
                preview.cacheDisplay(in: preview.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: destination))
            }
            let base = URL(fileURLWithPath: path).deletingPathExtension().path
            try capture(path, scheme: .light)
            try capture(base + "-dark.png", scheme: .dark)
            audio.selectionError = AudioServiceError.operationFailed(operation: "切换默认输出设备", status: -50)
            model.selectOutputDevice(2)
            try capture(base + "-error.png", scheme: .light)
        }
        window.contentView = nil
        model.stopAppAudioControl()
    }
}
