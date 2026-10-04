import AppKit
import SwiftUI

@main
struct VolumeControlApp: App {
    @StateObject private var model = VolumeControlModel()

    init() {
        if CommandLine.arguments.contains("--verify-process-audio") {
            Task { await ProcessAudioValidationRunner.run(arguments: CommandLine.arguments) }
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

struct VolumePanel: View {
    @ObservedObject var model: VolumeControlModel
    @AppStorage("showPercentage") private var showPercentage = true
    @State private var showInstallSheet = false
    @State private var routingTask: Task<Void, Never>?

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
        .task { await model.refreshLoop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            model.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            model.refresh()
        }
        .onDisappear { routingTask?.cancel() }
        .sheet(isPresented: $showInstallSheet) {
            BlackHoleInstallView(installGuide: model.blackHoleInstallGuide)
        }
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
            .accessibilityLabel("刷新音频状态")
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
                if showPercentage {
                    Text("\(Int(model.systemVolume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    model.toggleMute()
                } label: {
                    Image(systemName: model.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(model.isMuted ? "取消静音" : "静音")
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

            Text("播放音频后点击应用旁的启用按钮。首次需要允许系统音频录制。")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if model.hasAppAudioControl {
                Button("停止应用音量控制") { model.stopAppAudioControl() }
                    .font(.caption)
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
            DisclosureGroup("高级路由测试") {
                HStack {
                    if model.blackHoleAvailable {
                        if model.isEnablingRouting {
                            Button("取消启动") {
                                routingTask?.cancel()
                                model.disableV2()
                            }
                            .font(.caption)
                        } else if model.isV2Enabled {
                            Button("停止路由验证") { model.disableV2() }
                                .font(.caption)
                                .buttonStyle(.bordered)
                        } else {
                            Button("验证音频路由") {
                                routingTask = Task { await model.enableV2() }
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Button("安装 BlackHole") {
                            showInstallSheet = true
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
            }
            .font(.caption)
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
            .accessibilityLabel("设置")
            .help("设置")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

private struct AppVolumeRow: View {
    let app: AppVolume
    @ObservedObject var model: VolumeControlModel
    @State private var activationTask: Task<Void, Never>?

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
                    .foregroundStyle(app.capability.isSupported ? Color.secondary : Color.orange)
            }
            Spacer(minLength: 4)
            if app.capability.isSupported {
                Button {
                    model.toggleAppMute(id: app.id)
                } label: {
                    Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(app.isMuted ? "取消应用静音" : "静音应用")
                .help(app.isMuted ? "取消应用静音" : "静音此应用")
                
                Slider(value: Binding(
                    get: { app.volume },
                    set: { model.setAppVolume(id: app.id, volume: $0) }
                ), in: 0...1)
                .frame(width: 80)
                Button { model.disableAppVolume(id: app.id) } label: { Image(systemName: "stop.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("停止 \(app.name) 应用音量控制")
                    .help("恢复此应用的原始播放")
                Text("\(Int(app.volume * 100))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 28, alignment: .trailing)
            } else if app.isPreparing {
                Button { activationTask?.cancel() } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("取消启用应用音量")
                ProgressView().controlSize(.small)
            } else if app.canActivate {
                Button {
                    activationTask = Task { await model.enableAppVolume(id: app.id) }
                } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.borderless)
                .accessibilityLabel("启用 \(app.name) 应用音量")
                .help("保持播放音频，启用独立音量")
            } else {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(app.capability.label)
                    .help(app.capability.label)
            }
        }
        .padding(.vertical, 6)
        .onDisappear { activationTask?.cancel() }
    }
}

@MainActor
struct SettingsView: View {
    @State private var launchAtLogin: Bool
    @State private var loginItemStatus: LoginItemStatus
    @State private var loginItemError: String?
    @AppStorage("showPercentage") private var showPercentage = true
    private let loginItemController: any LoginItemControlling

    @MainActor
    init(loginItemController: (any LoginItemControlling)? = nil) {
        let controller = loginItemController ?? SystemLoginItemController()
        self.loginItemController = controller
        let status = controller.status
        _loginItemStatus = State(initialValue: status)
        _launchAtLogin = State(initialValue: status.isRegistered)
    }

    var body: some View {
        Form {
            Toggle("登录时启动", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        try loginItemController.setEnabled(enabled)
                        loginItemStatus = loginItemController.status
                        loginItemError = nil
                        launchAtLogin = loginItemStatus.isRegistered
                    } catch {
                        loginItemStatus = loginItemController.status
                        launchAtLogin = loginItemStatus.isRegistered
                        loginItemError = error.localizedDescription
                    }
                }
            if loginItemStatus == .requiresApproval {
                Text("请在系统设置的登录项中允许 VolumeControl。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if loginItemStatus == .unavailable {
                Text("请将应用放入“应用程序”文件夹后再启用登录启动。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("显示音量百分比", isOn: $showPercentage)
            LabeledContent("版本", value: "2.0.0-beta.1")
        }
        .padding(20)
        .frame(width: 360)
    }
}
