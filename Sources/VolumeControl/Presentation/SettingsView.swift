import SwiftUI

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
            LabeledContent("版本", value: "2.0.0-beta.3")
        }
        .padding(20)
        .frame(width: 360)
    }
}
