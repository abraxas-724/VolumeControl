import AppKit
import SwiftUI

@main
@MainActor
struct VolumeControlApp: App {
    @StateObject private var model = VolumeControlModel(restoreRememberedAudio: !CommandLine.arguments.contains { $0.hasPrefix("--verify-") })
    @StateObject private var preferences: InterfacePreferences
    @State private var settingsWindow: SettingsWindowController

    init() {
        let preferences = InterfacePreferences(storage: UserDefaultsInterfacePreferences())
        _preferences = StateObject(wrappedValue: preferences)
        _settingsWindow = State(initialValue: SettingsWindowController(preferences: preferences, makeContent: {
            AnyView(SettingsView(preferences: preferences, openPrivacySettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                    NSWorkspace.shared.open(url)
                }
            }, quitApplication: { NSApplication.shared.terminate(nil) }))
        }))
        if CommandLine.arguments.contains("--verify-process-audio") {
            Task { await ProcessAudioValidationRunner.run(arguments: CommandLine.arguments) }
        }
        if CommandLine.arguments.contains("--verify-audio-routing") {
            Task { await AudioRoutingValidationRunner.run(arguments: CommandLine.arguments) }
        }
        if CommandLine.arguments.contains("--verify-target-audio") {
            Task { await ProcessAudioValidationRunner.runTarget(arguments: CommandLine.arguments) }
        }
        if CommandLine.arguments.contains("--verify-remembered-audio") {
            Task { await AppAudioRestorationValidationRunner.run(arguments: CommandLine.arguments) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            VolumePanel(model: model, preferences: preferences, openSettings: { settingsWindow.showSettings() })
        } label: {
            Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .accessibilityLabel("VolumeControl")
        }
        .menuBarExtraStyle(.window)

    }
}
