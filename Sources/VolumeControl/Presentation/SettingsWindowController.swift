import AppKit
import Combine
import SwiftUI

/// 菜单栏应用不会因打开面板自动激活；显式置前同一个设置窗口，避免被其他应用遮挡。
@MainActor
final class SettingsWindowController {
    private(set) var window: NSWindow?
    private var appearanceSubscription: AnyCancellable?
    private let preferences: InterfacePreferences?
    private let makeContent: @MainActor () -> AnyView
    private let activateApplication: @MainActor () -> Void

    init(preferences: InterfacePreferences? = nil, makeContent: @escaping @MainActor () -> AnyView,
         activateApplication: (@MainActor () -> Void)? = nil) {
        self.preferences = preferences
        self.makeContent = makeContent
        self.activateApplication = activateApplication ?? { NSApplication.shared.activate(ignoringOtherApps: true) }
        appearanceSubscription = preferences?.$options.sink { [weak self] options in
            self?.applyTheme(options.theme)
        }
    }

    func showSettings() {
        if window == nil {
            let controller = NSHostingController(rootView: makeContent())
            let settings = NSWindow(contentViewController: controller)
            settings.title = "VolumeControl 设置"
            settings.styleMask = [.titled, .closable, .miniaturizable]
            settings.isReleasedWhenClosed = false
            settings.setContentSize(NSSize(width: 500, height: 660))
            settings.center()
            window = settings
        }
        applyTheme(preferences?.options.theme ?? .system)
        activateApplication()
        window?.makeKeyAndOrderFront(nil)
    }
    private func applyTheme(_ theme: InterfaceTheme) {
        switch theme {
        case .system: window?.appearance = nil
        case .light: window?.appearance = NSAppearance(named: .aqua)
        case .dark: window?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
