import AppKit
import Combine
import SwiftUI

/// AppKit 只管理状态栏和窗口生命周期，界面继续由注入模型的 SwiftUI View 展示。
@MainActor
final class VolumeControlApplicationDelegate: NSObject, NSApplicationDelegate {
    private var model: VolumeControlModel?
    private var preferences: InterfacePreferences?
    private var settingsWindow: SettingsWindowController?
    private var panel: MenuBarPopoverController?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        let model = VolumeControlModel(restoreRememberedAudio: !arguments.contains { $0.hasPrefix("--verify-") })
        let preferences = InterfacePreferences(storage: UserDefaultsInterfacePreferences())
        self.model = model
        self.preferences = preferences
        installApplicationMenu()
        settingsWindow = SettingsWindowController(preferences: preferences, makeContent: {
            AnyView(SettingsView(preferences: preferences, audioModel: model, openPrivacySettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(url)
                }
            }, quitApplication: { NSApplication.shared.terminate(nil) }))
        })
        let panel = MenuBarPopoverController(preferences: preferences, content: AnyView(
            VolumePanel(model: model, preferences: preferences, openSettings: { [weak self] in
                self?.showSettings()
            })
        ), beforeOpening: { model.refresh() })
        self.panel = panel
        model.$isMuted.sink { [weak panel] muted in panel?.setMuted(muted) }.store(in: &subscriptions)
        model.objectWillChange.sink { [weak panel] in panel?.scheduleResize() }.store(in: &subscriptions)
        panel.start()
        if arguments.contains("--verify-process-audio") {
            Task { await ProcessAudioValidationRunner.run(arguments: arguments) }
        }
        if arguments.contains("--verify-audio-routing") {
            Task { await AudioRoutingValidationRunner.run(arguments: arguments) }
        }
        if arguments.contains("--verify-target-audio") {
            Task { await ProcessAudioValidationRunner.runTarget(arguments: arguments) }
        }
        if arguments.contains("--verify-remembered-audio") {
            Task { await AppAudioRestorationValidationRunner.run(arguments: arguments) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { panel?.stop() }

    @objc private func showSettings() {
        panel?.close()
        settingsWindow?.showSettings()
    }

    private func installApplicationMenu() {
        // 改用 AppKit 启动后，保留 SwiftUI App 原来提供的退出、设置和文本编辑快捷键。
        let menu = NSMenu()
        let applicationMenu = NSMenu(title: "VolumeControl")
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        applicationMenu.addItem(settings)
        applicationMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 VolumeControl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        applicationMenu.addItem(quit)
        let edit = NSMenu(title: "编辑")
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        menu.addItem(editItem)
        for (title, action, key) in [
            ("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"),
            ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a")
        ] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        NSApplication.shared.mainMenu = menu
    }
}
