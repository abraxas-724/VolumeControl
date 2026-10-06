import SwiftUI

struct AppVolumeRow: View {
    let app: AppVolume
    @ObservedObject var model: VolumeControlModel
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.panelReduceMotion) private var panelReduceMotion
    private var reduceMotion: Bool { panelReduceMotion ?? systemReduceMotion }
    @State private var hovered = false
    @FocusState private var stopFocused: Bool
    @AccessibilityFocusState private var stopAccessibilityFocused: Bool

    private var revealActions: Bool { hovered || stopFocused || stopAccessibilityFocused }
    private var stateLabel: String {
        if app.isPreparing { return "验证中" }
        if app.isRemembered { return "等待恢复" }
        switch app.capability {
        case .permissionRequired: return "需要权限"
        case .noAudioSession: return "等待播放"
        case .unsupported: return app.canActivate ? "待启用" : "不可调节"
        case .supported: return ""
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(nsImage: app.icon).resizable().scaledToFit().frame(width: 28, height: 28)
                .padding(.top, 4).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.name).font(.body).lineLimit(1).truncationMode(.tail).help(app.name)
                    Spacer(minLength: 4)
                    if app.capability.isSupported && options.showPercentage {
                        Text("\(Int(app.volume * 100))%")
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                            .contentTransition(.numericText())
                            .animation(options.animation(reduceMotion: reduceMotion), value: Int(app.volume * 100))
                    }
                    actions
                }
                if app.capability.isSupported {
                    HStack(spacing: 8) {
                        Button { model.toggleAppMute(id: app.id) } label: { VolumeSymbol(muted: app.isMuted) }
                            .buttonStyle(PanelIconButtonStyle())
                            .foregroundStyle(app.isMuted ? options.accent.color : Color.secondary)
                            .accessibilityLabel(app.isMuted ? "取消 \(app.name) 静音" : "静音 \(app.name)")
                            .help(app.isMuted ? "取消静音" : "静音")
                        Slider(value: Binding(get: { app.volume }, set: { model.setAppVolume(id: app.id, volume: $0) }), in: 0...1)
                            .accessibilityLabel("\(app.name) 音量")
                        // 让滑块与上方百分比对齐，悬停操作不会推动内容。
                        Spacer().frame(width: 28)
                    }
                } else {
                    Text(stateLabel).font(.caption).foregroundStyle(.secondary)
                    if app.isPreparing || app.capability != .unsupported("点击启用应用音量") {
                        Text(app.isPreparing ? "正在验证音频；权限提示出现时可离开面板。" : app.capability.label)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            .help(app.capability.label)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, options.density == .compact ? 4 : 8)
        .background(.primary.opacity(revealActions ? 0.045 : 0),
                    in: RoundedRectangle(cornerRadius: PanelStyle.rowRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(options.animation(reduceMotion: reduceMotion, duration: PanelMotion.micro), value: revealActions)
        .contextMenu { contextActions }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if app.capability.isSupported || app.isRemembered {
                Button("停止控制并关闭自动恢复") { model.disableAppVolume(id: app.id) }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if app.capability.isSupported {
            Button { model.disableAppVolume(id: app.id) } label: { Image(systemName: "stop.circle") }
                .buttonStyle(PanelIconButtonStyle()).foregroundStyle(.secondary)
                .focused($stopFocused).accessibilityFocused($stopAccessibilityFocused)
                // 保持控件与焦点节点存在；键盘或旁白聚焦时立即显示。
                .opacity(revealActions ? 1 : 0.001)
                .accessibilityHidden(false)
                .accessibilityLabel("停止 \(app.name) 应用音量控制")
                .help("恢复原始播放并关闭此应用的自动恢复")
        } else if app.isPreparing {
            ProgressView().controlSize(.small).accessibilityLabel("正在验证 \(app.name)")
            Button { model.cancelAppVolume(id: app.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(PanelIconButtonStyle())
                .accessibilityLabel("取消启用 \(app.name) 应用音量").help("取消验证")
        } else {
            if app.canActivate {
                Button("启用") { model.startAppVolume(id: app.id) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityLabel("启用 \(app.name) 应用音量")
                    .help("保持播放，验证后启用独立音量；首次需要系统音频录制权限")
            }
            if app.isRemembered {
                Button { model.disableAppVolume(id: app.id) } label: { Image(systemName: "stop.circle") }
                    .buttonStyle(PanelIconButtonStyle())
                    .accessibilityLabel("关闭 \(app.name) 自动恢复").help("关闭自动恢复，保留音量设置")
            }
        }
    }

    @ViewBuilder private var contextActions: some View {
        if app.capability.isSupported {
            Button(app.isMuted ? "取消静音" : "静音") { model.toggleAppMute(id: app.id) }
            Button("重置音量为 100%") { model.setAppVolume(id: app.id, volume: 1) }
            Divider()
            Button("停止控制并关闭自动恢复") { model.disableAppVolume(id: app.id) }
        } else if app.isPreparing {
            Button("取消验证") { model.cancelAppVolume(id: app.id) }
        } else {
            if app.canActivate { Button("启用独立音量") { model.startAppVolume(id: app.id) } }
            if app.isRemembered { Button("关闭自动恢复") { model.disableAppVolume(id: app.id) } }
        }
    }
}
