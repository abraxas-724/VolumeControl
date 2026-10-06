import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var preferences: InterfacePreferences
    @State private var launchAtLogin: Bool
    @State private var loginItemStatus: LoginItemStatus
    @State private var loginItemError: String?
    @State private var page: SettingsPage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let loginItemController: any LoginItemControlling
    private let audioModel: VolumeControlModel?
    let openPrivacySettings: () -> Void
    let quitApplication: () -> Void

    init(preferences: InterfacePreferences, loginItemController: (any LoginItemControlling)? = nil,
         audioModel: VolumeControlModel? = nil, initialPage: SettingsPage = .general,
         openPrivacySettings: @escaping () -> Void = {}, quitApplication: @escaping () -> Void = {}) {
        self.preferences = preferences
        self.audioModel = audioModel
        _page = State(initialValue: initialPage)
        let controller = loginItemController ?? SystemLoginItemController()
        self.loginItemController = controller
        _loginItemStatus = State(initialValue: controller.status)
        _launchAtLogin = State(initialValue: controller.status.isRegistered)
        self.openPrivacySettings = openPrivacySettings
        self.quitApplication = quitApplication
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                ForEach(SettingsPage.allCases.filter { $0 != .audio || audioModel != nil }) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 200)
            .navigationTitle("设置")
        } detail: {
            Form {
                switch page ?? .general {
                case .general: general
                case .appearance: appearance
                case .audio:
                    if let audioModel { HeadphoneSwitchSettings(model: audioModel) }
                case .advanced: advanced
                case .about: about
                }
            }
            .formStyle(.grouped)
            .navigationTitle((page ?? .general).title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, idealWidth: 720, minHeight: 480, idealHeight: 560)
        .modifier(InterfaceAppearance(options: preferences.options))
        .onAppear { refreshLoginStatus() }
    }

    private var general: some View {
        Group {
            Section("启动") {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in updateLogin(enabled) }
                if loginItemStatus == .requiresApproval { caption("请在系统设置的登录项中允许 VolumeControl。") }
                else if loginItemStatus == .unavailable { caption("请将应用放入“应用程序”文件夹后再启用登录启动。") }
                if let loginItemError { Label(loginItemError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary) }
            }
            Section("面板显示") {
                Toggle("显示音量百分比", isOn: $preferences.options.showPercentage)
                Toggle("显示操作提示", isOn: $preferences.options.showTips)
                Toggle("默认显示已启用应用", isOn: $preferences.options.defaultToEnabledApps)
                caption("已启用筛选包括正在验证与等待恢复的应用。筛选不会改变音频控制。")
            }
        }
    }

    private var appearance: some View {
        Group {
            Section("外观") {
                Picker("颜色模式", selection: $preferences.options.theme) {
                    ForEach(InterfaceTheme.allCases) { Text($0.label).tag($0) }
                }
                Picker("强调色", selection: $preferences.options.accent) {
                    ForEach(InterfaceAccent.allCases) { Text($0.label).tag($0) }
                }
                Toggle("紧凑布局", isOn: Binding(get: { preferences.options.density == .compact },
                    set: { preferences.options.density = $0 ? .compact : .comfortable }))
                caption("背景材质随 macOS 自动适配，强调色仅用于控件和选中状态。")
                if reduceTransparency { caption("系统已开启减少透明度，面板使用实色背景。") }
            }
            Section("动态效果") {
                Toggle("使用界面动效", isOn: Binding(get: { preferences.options.motion != .off },
                    set: { preferences.options.motion = $0 ? .subtle : .off }))
                caption(reduceMotion ? "系统已开启减少动态效果，界面动画与面板展开动画均已关闭。" : "使用短暂反馈和系统原生弹出动画。")
            }
            Section {
                Button("重置界面设置") { preferences.resetAppearance() }
                caption("恢复外观和面板显示默认值，保留音量、音频授权和登录启动。")
            }
        }
    }

    private var advanced: some View {
        Group {
            Section("实验功能") {
                Toggle("显示高级路由入口", isOn: $preferences.options.showAdvanced)
                caption("BlackHole 路由验证位于音量面板，与原生应用音量控制互斥。运行或启动路由时，入口始终保留。")
                if let audioModel {
                    LabeledContent("BlackHole", value: audioModel.blackHoleAvailable ? "已安装" : "未检测到")
                    LabeledContent("路由状态", value: audioModel.isEnablingRouting ? "正在验证" : audioModel.isV2Enabled ? "验证运行中" : "未运行")
                }
            }
            Section("权限") {
                Button(action: openPrivacySettings) { Label("打开系统隐私设置", systemImage: "arrow.up.right.square") }
                caption("启用应用音量需要系统音频录制权限；BlackHole 路由验证需要相应输入权限。")
            }
        }
    }

    private var about: some View {
        Group {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2.fill").font(.largeTitle).foregroundStyle(.secondary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VolumeControl").font(.title3)
                        Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版本")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                caption("系统声音与应用独立音量控制。原生应用音量为 Beta，逐应用验证后启用。")
                Link("GitHub", destination: URL(string: "https://github.com/abraxas-724/VolumeControl")!)
            }
            Section("隐私") {
                caption("应用音频仅在本机处理，不保存录音文件或上传。")
            }
            Section { Button("退出 VolumeControl", action: quitApplication) }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func refreshLoginStatus() {
        loginItemStatus = loginItemController.status
        launchAtLogin = loginItemStatus.isRegistered
    }
    private func updateLogin(_ enabled: Bool) {
        do { try loginItemController.setEnabled(enabled); loginItemError = nil }
        catch { loginItemError = error.localizedDescription }
        refreshLoginStatus()
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, audio, advanced, about
    var id: Self { self }
    var title: String {
        switch self { case .general: return "通用"; case .appearance: return "外观"; case .audio: return "音频"; case .advanced: return "高级"; case .about: return "关于" }
    }
    var symbol: String {
        switch self { case .general: return "gearshape"; case .appearance: return "circle.lefthalf.filled"; case .audio: return "headphones"; case .advanced: return "wrench.and.screwdriver"; case .about: return "info.circle" }
    }
}
