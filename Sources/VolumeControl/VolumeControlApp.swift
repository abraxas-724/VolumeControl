import AppKit
import SwiftUI

@main
struct VolumeControlApp: App {
    @StateObject private var model = VolumeControlModel()

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let error = model.lastError { errorBanner(error) }
            systemVolume
            Divider()
            appSection
            Divider()
            footer
        }
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .padding(.vertical, 8)
        .task { await model.refreshLoop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            model.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            model.refresh()
        }
        .sheet(isPresented: $showInstallSheet) {
            BlackHoleInstallView(installGuide: model.blackHoleInstallGuide)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("操作未完成", systemImage: "exclamationmark.triangle.fill").font(.subheadline.weight(.semibold))
                Spacer()
                Button { model.dismissError() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("关闭错误提示")
            }
            ScrollView {
                Text(message).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 68)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.top, 10)
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
            }
        }
        .padding(16)
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("应用音量")
                    .font(.headline)
                Spacer()
                Text("\(model.apps.count) 个应用")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("播放音频后点击应用旁的启用按钮。首次需要允许系统音频录制。")
                .font(.caption)
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
                    LazyVStack(spacing: 8) {
                        ForEach(model.apps) { app in
                            AppVolumeRow(app: app, model: model)
                        }
                    }
                }
                .frame(height: 320)
                .scrollIndicators(.visible)
            }
            DisclosureGroup("高级路由测试") {
                HStack {
                    if model.blackHoleAvailable {
                        if model.isEnablingRouting {
                            Button("取消启动") {
                                model.cancelRoutingValidation()
                            }
                            .font(.caption)
                        } else if model.isV2Enabled {
                            Button("停止路由验证") { model.disableV2() }
                                .font(.caption)
                                .buttonStyle(.bordered)
                        } else {
                            Button("验证音频路由") {
                                model.startRoutingValidation()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: app.icon).resizable().frame(width: 28, height: 28)
                Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                if app.capability.isSupported {
                    Text(app.isMuted ? "已静音" : "\(Int(app.volume * 100))%")
                        .font(.subheadline.monospacedDigit())
                    Button { model.disableAppVolume(id: app.id) } label: { Image(systemName: "stop.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("停止 \(app.name) 应用音量控制")
                        .help("恢复此应用的原始播放")
                } else if app.isPreparing {
                    ProgressView().controlSize(.small)
                    Button { model.cancelAppVolume(id: app.id) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("取消启用 \(app.name) 应用音量")
                } else if app.canActivate {
                    Button { model.startAppVolume(id: app.id) } label: { Label("启用", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("启用 \(app.name) 应用音量")
                        .help("保持播放音频，启用独立音量")
                }
            }
            if app.capability.isSupported {
                HStack(spacing: 12) {
                    Button { model.toggleAppMute(id: app.id) } label: {
                        Image(systemName: app.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(app.isMuted ? "取消应用静音" : "静音应用")
                    Slider(value: Binding(get: { app.volume }, set: { model.setAppVolume(id: app.id, volume: $0) }), in: 0...1)
                        .accessibilityLabel("\(app.name) 音量")
                }
            } else {
                Text(app.isPreparing ? "正在验证音频；权限提示出现时可离开面板" : app.capability.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(app.capability.label)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
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
            LabeledContent("版本", value: "2.0.0-beta.2")
        }
        .padding(20)
        .frame(width: 360)
    }
}
