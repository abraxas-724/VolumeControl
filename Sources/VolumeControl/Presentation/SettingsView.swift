import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var preferences: InterfacePreferences
    @State private var launchAtLogin: Bool
    @State private var loginItemStatus: LoginItemStatus
    @State private var loginItemError: String?
    @State private var page = 0
    @State private var previewVolume = 0.42
    @State private var previewMuted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let loginItemController: any LoginItemControlling
    let openPrivacySettings: () -> Void
    let quitApplication: () -> Void

    init(preferences: InterfacePreferences, loginItemController: (any LoginItemControlling)? = nil,
         initialPage: Int = 0, openPrivacySettings: @escaping () -> Void = {}, quitApplication: @escaping () -> Void = {}) {
        self.preferences = preferences
        _page = State(initialValue: initialPage)
        let controller = loginItemController ?? SystemLoginItemController()
        self.loginItemController = controller
        _loginItemStatus = State(initialValue: controller.status)
        _launchAtLogin = State(initialValue: controller.status.isRegistered)
        self.openPrivacySettings = openPrivacySettings
        self.quitApplication = quitApplication
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").font(.title2.weight(.semibold))
                    .foregroundStyle(preferences.options.accent.color)
                    .frame(width: 46, height: 46).modifier(InteractiveSurface(emphasized: true))
                VStack(alignment: .leading, spacing: 3) {
                    Text("按你的喜好，调好每一处").font(.title3.weight(.semibold))
                    Text("VolumeControl 设置").font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker("设置页面", selection: $page) {
                Text("外观与动效").tag(0)
                Text("通用").tag(1)
            }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if page == 0 { appearance } else { general }
                }.padding(.bottom, 4)
            }.scrollIndicators(.visible)
            HStack {
                Text("2.0.0-beta.3").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("重置界面设置") { preferences.resetAppearance() }
                    .buttonStyle(.borderless).font(.caption)
                    .help("只重置外观和面板显示，不改变音量、应用授权或登录启动")
            }
        }
        .padding(22)
        .frame(width: 500, height: 660)
        .background(InterfaceBackdrop())
        .animation(preferences.options.animation(reduceMotion: reduceMotion), value: page)
        .modifier(InterfaceAppearance(options: preferences.options))
        .onAppear { refreshLoginStatus() }
    }

    private var appearance: some View {
        Group {
            preview
            section("颜色模式", symbol: "circle.lefthalf.filled") {
                Picker("颜色模式", selection: $preferences.options.theme) {
                    ForEach(InterfaceTheme.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            section("界面材质", symbol: "drop.fill") {
                Picker("界面材质", selection: $preferences.options.surface) {
                    ForEach(InterfaceSurface.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                if preferences.options.surface == .liquid {
                    if #available(macOS 26.0, *) {
                        caption("原生液态玻璃用于按钮与切换控件，正文保持清晰。")
                    } else { caption("原生液态玻璃需要 macOS 26+；当前使用磨砂玻璃。") }
                }
                if reduceTransparency { caption("系统已开启减少透明度，当前使用实色界面。") }
            }
            section("强调色", symbol: "paintpalette.fill") {
                HStack(spacing: 16) {
                    ForEach(InterfaceAccent.allCases) { accent in
                        Button { preferences.options.accent = accent } label: {
                            Circle().fill(accent.color).frame(width: 30, height: 30)
                                .overlay {
                                    if preferences.options.accent == accent {
                                        Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                    }
                                }
                                .padding(3)
                                .overlay(Circle().strokeBorder(accent.color.opacity(preferences.options.accent == accent ? 0.8 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain).accessibilityLabel("\(accent.label)强调色")
                        .accessibilityAddTraits(preferences.options.accent == accent ? .isSelected : [])
                        .help(accent.label)
                    }
                }.frame(maxWidth: .infinity)
            }
            section("交互动效", symbol: "sparkles") {
                Picker("交互动效", selection: $preferences.options.motion) {
                    ForEach(InterfaceMotion.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                caption(reduceMotion ? "系统已开启减少动态效果，自定义动效暂停。" : "轻柔：淡入与柔和反馈。灵动：弹簧切换、悬停与按压回弹。")
            }
            section("布局密度", symbol: "rectangle.compress.vertical") {
                Picker("布局密度", selection: $preferences.options.density) {
                    ForEach(InterfaceDensity.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                caption("紧凑模式缩小行间距和列表高度，更适合小屏幕。")
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("外观预览", systemImage: "wand.and.stars").font(.subheadline.weight(.semibold))
                Spacer()
                Text(previewMuted ? "静音" : "\(Int(previewVolume * 100))%")
                    .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(preferences.options.accent.color)
                    .contentTransition(.numericText())
                    .animation(preferences.options.animation(reduceMotion: reduceMotion), value: Int(previewVolume * 100))
            }
            GlassControlGroup {
                HStack(spacing: 12) {
                    Button { previewMuted.toggle() } label: {
                        VolumeSymbol(muted: previewMuted)
                    }.buttonStyle(PanelIconButtonStyle()).accessibilityLabel("切换预览静音")
                    Slider(value: $previewVolume).accessibilityLabel("预览音量")
                }
            }
            caption("试试按钮和滑块；此处只预览外观，不改变实际音量。")
        }.modifier(PanelCard())
    }

    private var general: some View {
        Group {
            section("启动与显示", symbol: "switch.2") {
                toggleRow("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in updateLogin(enabled) }
                if loginItemStatus == .requiresApproval {
                    caption("请在系统设置的登录项中允许 VolumeControl。")
                } else if loginItemStatus == .unavailable {
                    caption("请将应用放入“应用程序”文件夹后再启用登录启动。")
                }
                if let loginItemError { Text(loginItemError).font(.caption).foregroundStyle(.red) }
                Divider()
                toggleRow("显示音量百分比", isOn: $preferences.options.showPercentage)
                toggleRow("显示操作提示", isOn: $preferences.options.showTips)
                toggleRow("显示高级路由入口", isOn: $preferences.options.showAdvanced)
            }
            section("应用列表", symbol: "app.badge") {
                toggleRow("默认显示已启用应用", isOn: $preferences.options.defaultToEnabledApps)
                caption("包括正在验证与等待恢复的应用。筛选不会启用或停用音频控制。")
            }
            section("隐私与应用", symbol: "hand.raised.fill") {
                caption("应用音频只在本机处理，不保存录音文件或上传。修改外观不会影响音量或授权。")
                Button(action: openPrivacySettings) { Label("打开系统隐私设置", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.bordered)
                Button(action: quitApplication) { Label("退出 VolumeControl", systemImage: "power") }
                    .buttonStyle(.bordered)
            }
        }.toggleStyle(.switch)
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                .foregroundStyle(preferences.options.accent.color)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).modifier(PanelCard())
    }

    private func toggleRow(_ title: String, isOn binding: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: binding).labelsHidden().toggleStyle(.switch)
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
