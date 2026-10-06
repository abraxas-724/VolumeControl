import SwiftUI

struct SystemVolumeSection: View {
    @ObservedObject var model: VolumeControlModel
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.panelReduceMotion) private var panelReduceMotion
    private var reduceMotion: Bool { panelReduceMotion ?? systemReduceMotion }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("系统音量").font(.subheadline)
                Spacer()
                if options.showPercentage && model.canAdjustSystemVolume {
                    Text(model.isMuted ? "已静音" : "\(Int(model.systemVolume * 100))%")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(minWidth: 40, alignment: .trailing)
                        .contentTransition(.numericText())
                        .animation(options.animation(reduceMotion: reduceMotion), value: Int(model.systemVolume * 100))
                }
            }
            HStack(spacing: 8) {
                Button { model.toggleMute() } label: { VolumeSymbol(muted: model.isMuted) }
                    .buttonStyle(PanelIconButtonStyle())
                    .foregroundStyle(model.isMuted ? options.accent.color : Color.primary)
                    .disabled(!model.canMuteSystemAudio)
                    .accessibilityLabel(model.isMuted ? "取消系统静音" : "系统静音")
                    .help(model.isMuted ? "取消静音" : "静音")
                Slider(value: $model.systemVolume, in: 0...1) { editing in
                    if !editing { model.commitSystemVolume() }
                }
                .disabled(!model.canAdjustSystemVolume).accessibilityLabel("系统音量")
            }
            if !model.canAdjustSystemVolume {
                Text("此设备不支持系统音量调节").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("输出设备").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Menu {
                    ForEach(model.outputDevices) { device in
                        Button { model.selectOutputDevice(device.id) } label: {
                            if device.id == model.selectedOutputDeviceID { Label(device.name, systemImage: "checkmark") }
                            else { Text(device.name) }
                        }
                    }
                } label: {
                    Text(model.outputDeviceName).font(.callout).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(.secondary).tint(.secondary)
                .disabled(model.outputDevices.isEmpty || model.isV2Enabled || model.isEnablingRouting)
                .modifier(PanelMenuHover())
                .accessibilityLabel("选择音频输出设备")
                .accessibilityValue(model.outputDeviceName)
                .help(model.isV2Enabled || model.isEnablingRouting ? "请先停止高级路由测试" : model.outputDeviceName)
            }
        }
    }
}
