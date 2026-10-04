import AppKit
import SwiftUI

@main
struct VolumeControlApp: App {
    @StateObject private var model = VolumeControlModel()

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

struct VolumePanel: View {
    @ObservedObject var model: VolumeControlModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            systemVolume
            Divider()
            appSection
            Divider()
            footer
        }
        .frame(width: 340)
        .padding(.vertical, 8)
        .task { model.refresh() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("VolumeControl")
                    .font(.headline)
                Text(model.outputDeviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新音频状态")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var systemVolume: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("系统音量", systemImage: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(model.systemVolume * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: model.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(model.isMuted ? "取消静音" : "静音")

                Slider(value: $model.systemVolume, in: 0...1) { editing in
                    if !editing { model.commitSystemVolume() }
                }
                .onChange(of: model.systemVolume) { _, _ in model.commitSystemVolume() }
            }
        }
        .padding(16)
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("应用音量")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.apps.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if model.apps.isEmpty {
                ContentUnavailableView("暂无运行中的应用", systemImage: "app.dashed", description: Text("打开应用后点击刷新"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.apps) { app in
                            AppVolumeRow(app: app, model: model)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("设置")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

private struct AppVolumeRow: View {
    let app: AppVolume
    @ObservedObject var model: VolumeControlModel

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .lineLimit(1)
                Text(app.capability.label)
                    .font(.caption2)
                    .foregroundStyle(app.capability.isSupported ? .secondary : .orange)
            }
            Spacer(minLength: 4)
            if app.capability.isSupported {
                Slider(value: Binding(
                    get: { app.volume },
                    set: { model.setAppVolume(id: app.id, volume: $0) }
                ), in: 0...1)
                .frame(width: 100)
                Text("\(Int(app.volume * 100))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 28, alignment: .trailing)
            } else {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .help(app.capability.label)
            }
        }
        .padding(.vertical, 6)
    }
}

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showPercentage") private var showPercentage = true

    var body: some View {
        Form {
            Toggle("登录时启动", isOn: $launchAtLogin)
            Toggle("显示音量百分比", isOn: $showPercentage)
            LabeledContent("版本", value: "0.1.0")
        }
        .padding(20)
        .frame(width: 360)
    }
}
