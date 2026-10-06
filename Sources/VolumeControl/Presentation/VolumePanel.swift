import SwiftUI

struct VolumePanel: View {
    @ObservedObject var model: VolumeControlModel
    @ObservedObject var preferences: InterfacePreferences
    let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var filterNamespace
    private var options: InterfaceOptions { preferences.options }
    private var accent: Color { options.accent.color }
    @State private var showInstallSheet = false
    @State private var searchText = ""
    @State private var filter: AppListFilter = .all

    private var visibleApps: [AppVolume] {
        filter.applications(from: model.apps, matching: searchText)
    }

    var body: some View {
        panelContent
            .modifier(InterfaceAppearance(options: options))
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let error = model.lastError { errorBanner(error) }
            systemVolume
            appSection
            if options.showAdvanced || model.isV2Enabled || model.isEnablingRouting { advancedSection }
            footer
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(InterfaceBackdrop())
        .animation(options.animation(reduceMotion: reduceMotion), value: filter)
        .onAppear {
            filter = options.defaultToEnabledApps ? .enabled : .all
        }
        .onChange(of: options.defaultToEnabledApps) { _, enabled in filter = enabled ? .enabled : .all }
        .sheet(isPresented: $showInstallSheet) {
            BlackHoleInstallView(installGuide: model.blackHoleInstallGuide)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .modifier(InteractiveSurface(emphasized: true))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("VolumeControl").font(.system(size: 17, weight: .semibold))
                    Text("BETA").font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(accent.opacity(0.1), in: Capsule())
                }
                Text("让每个应用，都有合适的音量")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(PanelIconButtonStyle())
                .accessibilityLabel("刷新音频状态")
                .help("刷新音频状态")
        }
    }

    private var systemVolume: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("系统音量").font(.subheadline.weight(.semibold))
                Spacer()
                if options.showPercentage && model.canAdjustSystemVolume {
                    Text(model.isMuted ? "已静音" : "\(Int(model.systemVolume * 100))%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(options.animation(reduceMotion: reduceMotion), value: Int(model.systemVolume * 100))
                        .foregroundStyle(model.isMuted ? Color.secondary : accent)
                }
            }
            HStack(spacing: 12) {
                Button { model.toggleMute() } label: {
                    VolumeSymbol(muted: model.isMuted)
                }
                .buttonStyle(PanelIconButtonStyle())
                .foregroundStyle(model.isMuted ? accent : Color.primary)
                .disabled(!model.canMuteSystemAudio)
                .accessibilityLabel(model.isMuted ? "取消静音" : "静音")
                .help(model.isMuted ? "取消静音" : "静音")
                Slider(value: $model.systemVolume, in: 0...1) { editing in
                    if !editing { model.commitSystemVolume() }
                }
                .disabled(!model.canAdjustSystemVolume)
                .accessibilityLabel("系统音量")
            }
            if !model.canAdjustSystemVolume {
                Text("此设备不支持系统音量调节")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker.fill").foregroundStyle(.secondary)
                Text("输出设备").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Menu {
                    ForEach(model.outputDevices) { device in
                        Button { model.selectOutputDevice(device.id) } label: {
                            if device.id == model.selectedOutputDeviceID {
                                Label(device.name, systemImage: "checkmark")
                            } else { Text(device.name) }
                        }
                    }
                } label: {
                    Text(model.outputDeviceName).font(.caption.weight(.medium)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
                .disabled(model.outputDevices.isEmpty || model.isV2Enabled || model.isEnablingRouting)
                .accessibilityLabel("选择音频输出设备")
                .help(model.isV2Enabled || model.isEnablingRouting ? "请先停止高级路由测试" : "切换电脑默认音频输出")
            }
        }
        .modifier(PanelCard())
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("应用混音器").font(.headline)
                Spacer()
                Text("\(model.apps.filter { $0.capability.isSupported }.count) 已启用 · \(model.apps.count) 个应用")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索应用", text: $searchText)
                        .textFieldStyle(.plain).accessibilityLabel("搜索应用")
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityLabel("清空应用搜索")
                    }
                }
                .padding(8)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 2) {
                    ForEach(AppListFilter.allCases) { item in
                        Button { filter = item } label: {
                            Text(item.label).font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background {
                                    if filter == item {
                                        RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.16))
                                            .matchedGeometryEffect(id: "filter", in: filterNamespace)
                                    }
                                }
                        }.buttonStyle(.plain)
                            .accessibilityLabel(item.label)
                            .accessibilityAddTraits(filter == item ? .isSelected : [])
                    }
                }.padding(3).frame(width: 164)
                    .modifier(InteractiveSurface())
            }
            Group {
                if model.apps.isEmpty {
                    emptyState("暂无音频应用", detail: "播放音频后应用会自动显示，也可点击刷新。", symbol: "speaker.wave.2")
                } else if visibleApps.isEmpty {
                    emptyState("没有符合条件的应用", detail: "尝试其他名称，或切换到全部应用。", symbol: "magnifyingglass")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(visibleApps) { app in AppVolumeRow(app: app, model: model) }
                        }
                    }
                    .scrollIndicators(.visible)
                }
            }
            .frame(height: options.density.listHeight)
            if options.showTips {
            Label("仅显示音频应用；播放后启用，验证成功才可调节。", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help("首次启用需要系统音频录制权限；音频仅在本机处理。")
            }
        }
    }

    private var advancedSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("BlackHole 实验回路，与应用音量控制互斥。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.blackHoleAvailable {
                    if model.isEnablingRouting {
                        Button("取消启动") { model.cancelRoutingValidation() }
                    } else if model.isV2Enabled {
                        Button("停止路由验证") { model.disableV2() }
                    } else {
                        Button("验证音频路由") { model.startRoutingValidation() }
                    }
                } else {
                    Button("安装 BlackHole") { showInstallSheet = true }
                }
            }
            .buttonStyle(.bordered).controlSize(.small).padding(.top, 8)
        } label: {
            Label("高级路由测试", systemImage: "wrench.and.screwdriver")
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 8) {
                Text(model.statusMessage).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).help(model.statusMessage)
                Spacer(minLength: 8)
                if model.hasAppAudioControl || model.apps.contains(where: \.isRemembered) {
                    Button { model.stopAppAudioControl() } label: { Image(systemName: "stop.circle") }
                        .buttonStyle(PanelIconButtonStyle())
                        .accessibilityLabel("停止所有应用音量控制")
                        .help("停止所有应用控制并关闭自动恢复")
                }
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(PanelIconButtonStyle()).accessibilityLabel("设置").help("设置")
            }
        }
    }

    private func emptyState(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.tertiary)
            Text(title).font(.subheadline.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PanelCard())
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("操作未完成", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { model.dismissError() } label: { Image(systemName: "xmark") }
                    .buttonStyle(PanelIconButtonStyle()).accessibilityLabel("关闭错误提示")
            }
            ScrollView {
                Text(message).font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 68)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
