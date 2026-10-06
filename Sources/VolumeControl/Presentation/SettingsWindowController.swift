import AppKit
import SwiftUI

/// 菜单栏应用不会因打开面板自动激活；显式置前同一个设置窗口，避免被其他应用遮挡。
@MainActor
final class SettingsWindowController {
    private(set) var window: NSWindow?
    private let makeContent: @MainActor () -> AnyView
    private let activateApplication: @MainActor () -> Void

    init(makeContent: (@MainActor () -> AnyView)? = nil,
         activateApplication: (@MainActor () -> Void)? = nil) {
        self.makeContent = makeContent ?? { AnyView(SettingsView()) }
        self.activateApplication = activateApplication ?? { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    func showSettings() {
        if window == nil {
            let controller = NSHostingController(rootView: makeContent())
            let settings = NSWindow(contentViewController: controller)
            settings.title = "VolumeControl 设置"
            settings.styleMask = [.titled, .closable, .miniaturizable]
            settings.isReleasedWhenClosed = false
            settings.setContentSize(NSSize(width: 360, height: 220))
            settings.center()
            window = settings
        }
        activateApplication()
        window?.makeKeyAndOrderFront(nil)
    }
}
