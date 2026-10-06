import SwiftUI

struct HeadphoneSwitchSettings: View {
    @ObservedObject var model: VolumeControlModel

    private var candidates: [OutputAudioDevice] {
        model.outputDevices.filter { $0.canBePreferredHeadphones && $0.uid != nil }
    }

    var body: some View {
        Section("耳机与输出") {
            Toggle("插入耳机自动切换", isOn: $model.deviceSwitchOptions.autoSwitchHeadphones)
            Picker("指定耳机", selection: Binding(get: { model.deviceSwitchOptions.preferredHeadphoneUID ?? "" },
                set: { model.deviceSwitchOptions.preferredHeadphoneUID = $0.isEmpty ? nil : $0 })) {
                Text("自动识别").tag("")
                ForEach(candidates) { device in Text(device.name).tag(device.uid!) }
                if let saved = model.deviceSwitchOptions.preferredHeadphoneUID, !candidates.contains(where: { $0.uid == saved }) {
                    Text("已保存的耳机（未连接）").tag(saved)
                }
            }
            .disabled(!model.deviceSwitchOptions.autoSwitchHeadphones)
            Text("新接入耳机时切换输出；未被识别的 USB 或蓝牙耳机可在此指定。启动软件和修改此设置不会切换当前输出。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.isV2Enabled || model.isEnablingRouting {
                Text("高级路由测试期间暂停自动切换。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
