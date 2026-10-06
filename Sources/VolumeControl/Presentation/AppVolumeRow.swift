import SwiftUI

struct AppVolumeRow: View {
    let app: AppVolume
    @ObservedObject var model: VolumeControlModel
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stateLabel: String {
        if app.isPreparing { return "验证中" }
        if app.capability.isSupported { return app.isMuted ? "已静音" : "已启用" }
        if app.isRemembered { return "等待恢复" }
        return app.canActivate ? "待启用" : "不可调节"
    }

    private var stateColor: Color {
        if app.isPreparing || app.isRemembered && !app.capability.isSupported { return .orange }
        return app.capability.isSupported ? options.accent.color : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: options.density == .compact ? 6 : 10) {
            HStack(spacing: 10) {
                Image(nsImage: app.icon).resizable().scaledToFit().frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1).help(app.name)
                    HStack(spacing: 4) {
                        Circle().fill(stateColor).frame(width: 5, height: 5)
                        Text(stateLabel).font(.system(size: 10, weight: .medium)).foregroundStyle(stateColor)
                    }
                }
                Spacer(minLength: 8)
                actions
            }
            if app.capability.isSupported {
                HStack(spacing: 10) {
                    Button { model.toggleAppMute(id: app.id) } label: {
                        VolumeSymbol(muted: app.isMuted)
                    }
                    .buttonStyle(PanelIconButtonStyle())
                    .foregroundStyle(app.isMuted ? options.accent.color : Color.secondary)
                    .accessibilityLabel(app.isMuted ? "取消 \(app.name) 静音" : "静音 \(app.name)")
                    .help(app.isMuted ? "取消静音" : "静音")
                    Slider(value: Binding(get: { app.volume }, set: { model.setAppVolume(id: app.id, volume: $0) }), in: 0...1)
                        .accessibilityLabel("\(app.name) 音量")
                    if options.showPercentage {
                    Text("\(Int(app.volume * 100))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                        .contentTransition(.numericText())
                        .animation(options.animation(reduceMotion: reduceMotion), value: Int(app.volume * 100))
                    }
                }
            } else {
                Text(app.isPreparing ? "正在验证音频；权限提示出现时可离开面板" : app.capability.label)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .help(app.capability.label)
            }
        }
        .modifier(PanelCard())
    }

    @ViewBuilder
    private var actions: some View {
        if app.capability.isSupported {
            Button { model.disableAppVolume(id: app.id) } label: { Image(systemName: "stop.circle") }
                .buttonStyle(PanelIconButtonStyle()).foregroundStyle(.secondary)
                .accessibilityLabel("停止 \(app.name) 应用音量控制")
                .help("恢复此应用的原始播放并关闭自动恢复")
        } else if app.isPreparing {
            ProgressView().controlSize(.small)
            Button { model.cancelAppVolume(id: app.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(PanelIconButtonStyle())
                .accessibilityLabel("取消启用 \(app.name) 应用音量")
                .help("取消验证")
        } else {
            if app.canActivate {
                Button { model.startAppVolume(id: app.id) } label: {
                    Label("启用", systemImage: "slider.horizontal.3").font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityLabel("启用 \(app.name) 应用音量")
                .help("保持播放音频，启用独立音量；首次需要系统音频录制权限")
            }
            if app.isRemembered {
                Button { model.disableAppVolume(id: app.id) } label: { Image(systemName: "stop.circle") }
                    .buttonStyle(PanelIconButtonStyle())
                    .accessibilityLabel("关闭 \(app.name) 自动恢复")
                    .help("关闭自动恢复，保留音量设置")
            }
        }
    }
}
