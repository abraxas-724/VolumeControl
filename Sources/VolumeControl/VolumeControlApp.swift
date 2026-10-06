import AppKit
import SwiftUI

@main
struct VolumeControlApp: App {
    @StateObject private var model = VolumeControlModel(restoreRememberedAudio: !CommandLine.arguments.contains { $0.hasPrefix("--verify-") })

    init() {
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
            VolumePanel(model: model)
        } label: {
            Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .accessibilityLabel("VolumeControl")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
