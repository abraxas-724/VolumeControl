import SwiftUI

struct VolumePanel: View {
    @ObservedObject var model: VolumeControlModel
    @ObservedObject var preferences: InterfacePreferences
    let openSettings: () -> Void
    @Environment(\.panelMaximumHeight) private var maximumHeight
    @State private var chromeHeight: CGFloat = 240
    @State private var showInstallSheet = false
    private var options: InterfaceOptions { preferences.options }
    private var showsAdvanced: Bool { options.showAdvanced || model.isV2Enabled || model.isEnablingRouting }
    private var listHeight: CGFloat {
        // 非列表内容实测高度包括长错误、路由展开和提示；剩余屏幕空间全部留给滚动列表。
        let sectionGaps = CGFloat(4 + (showsAdvanced ? 1 : 0) + (model.lastError == nil ? 0 : 1)) * 12
        let insetsAndMixerGaps: CGFloat = 32 + (options.showTips ? 16 : 8)
        return max(80, min(options.density.listHeight, maximumHeight - chromeHeight - sectionGaps - insetsAndMixerGaps))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.measurePanelChrome("header")
            if let error = model.lastError { PanelInlineError(message: error, dismiss: model.dismissError).measurePanelChrome("error") }
            SystemVolumeSection(model: model).measurePanelChrome("system")
            Divider().measurePanelChrome("divider")
            AppMixerSection(model: model, listHeight: listHeight)
            if showsAdvanced { advancedSection.measurePanelChrome("advanced") }
            footer.measurePanelChrome("footer")
        }
        .padding(PanelStyle.inset)
        .frame(width: PanelStyle.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(PanelBackdrop())
        .onPreferenceChange(PanelChromeHeightKey.self) { heights in
            let measured = heights.values.reduce(0, +)
            if abs(chromeHeight - measured) > 0.5 { chromeHeight = measured }
        }
        .sheet(isPresented: $showInstallSheet) { BlackHoleInstallView(installGuide: model.blackHoleInstallGuide) }
        .modifier(InterfaceAppearance(options: options))
    }

    private var header: some View {
        HStack {
            Text("VolumeControl").font(.headline)
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(PanelIconButtonStyle()).foregroundStyle(.secondary)
                .accessibilityLabel("刷新音频状态").help("刷新音频状态")
        }
    }

    private var advancedSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("BlackHole 实验回路，与应用音量控制互斥。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.blackHoleAvailable {
                    if model.isEnablingRouting { Button("取消启动") { model.cancelRoutingValidation() } }
                    else if model.isV2Enabled { Button("停止路由验证") { model.disableV2() } }
                    else { Button("验证音频路由") { model.startRoutingValidation() } }
                } else { Button("安装 BlackHole") { showInstallSheet = true } }
            }.buttonStyle(.bordered).controlSize(.small).padding(.top, 8)
        } label: { Label("高级路由测试", systemImage: "wrench.and.screwdriver") }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).help(model.statusMessage)
                Spacer(minLength: 8)
                if model.hasAppAudioControl || model.apps.contains(where: \.isRemembered) {
                    Button { model.stopAppAudioControl() } label: { Image(systemName: "stop.circle") }
                        .buttonStyle(PanelIconButtonStyle()).foregroundStyle(.secondary)
                        .accessibilityLabel("停止所有应用音量控制").help("停止所有应用控制并关闭自动恢复")
                }
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(PanelIconButtonStyle()).foregroundStyle(.secondary)
                    .keyboardShortcut(",", modifiers: .command)
                    .accessibilityLabel("设置").help("设置（⌘,）")
            }
        }
    }
}

/// 只测量固定控件，避免滚动列表高度参与计算形成尺寸反馈循环。
struct PanelChromeHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
extension View {
    func measurePanelChrome(_ section: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: PanelChromeHeightKey.self, value: [section: geometry.size.height])
        })
    }
}
