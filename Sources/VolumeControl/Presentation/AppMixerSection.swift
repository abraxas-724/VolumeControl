import SwiftUI

struct AppMixerSection: View {
    @ObservedObject var model: VolumeControlModel
    let listHeight: CGFloat
    @Environment(\.interfaceOptions) private var options
    @State private var searchText = ""
    @State private var filter: AppListFilter = .all

    private var visibleApps: [AppVolume] { filter.applications(from: model.apps, matching: searchText) }

    private var contentHeight: CGFloat {
        guard !visibleApps.isEmpty else { return min(listHeight, 144) }
        let compact = options.density == .compact
        let rows = visibleApps.reduce(CGFloat.zero) { height, app in
            height + (app.capability.isSupported ? (compact ? 68 : 76) : (compact ? 84 : 92))
        }
        return min(listHeight, rows + CGFloat(visibleApps.count - 1) * (compact ? 4 : 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("应用").font(.headline)
                    Spacer()
                    Text("\(model.apps.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel("\(model.apps.count) 个音频应用")
                }
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("搜索应用", text: $searchText).textFieldStyle(.plain).accessibilityLabel("搜索应用")
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(PanelIconButtonStyle()).foregroundStyle(.secondary)
                                .accessibilityLabel("清空应用搜索").help("清空搜索")
                        }
                    }
                    .padding(.horizontal, 8).frame(height: 32)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: PanelStyle.rowRadius))
                    Menu {
                        Picker("显示应用", selection: $filter) {
                            ForEach(AppListFilter.allCases) { item in Text(item.label).tag(item) }
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(width: 28, height: 28).modifier(PanelMenuHover())
                    .foregroundStyle(filter == .enabled ? options.accent.color : Color.secondary)
                    .tint(filter == .enabled ? options.accent.color : Color.secondary)
                    .accessibilityLabel("筛选应用").accessibilityValue(filter.label)
                    .help("显示：\(filter.label)")
                }
            }
            .measurePanelChrome("mixerHeader")
            Group {
                if model.apps.isEmpty {
                    emptyState("暂无音频应用", detail: "播放音频后，应用会显示在这里。", symbol: "speaker.wave.2")
                } else if visibleApps.isEmpty {
                    emptyState("没有符合条件的应用", detail: "尝试其他名称，或显示全部应用。", symbol: "magnifyingglass")
                } else {
                    ScrollView {
                        LazyVStack(spacing: options.density == .compact ? 4 : 8) {
                            ForEach(visibleApps) { app in AppVolumeRow(app: app, model: model) }
                        }
                    }.scrollIndicators(.visible)
                }
            }.frame(height: contentHeight)
            if options.showTips {
                Label("播放后启用，验证成功才可调节。", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help("首次启用需要系统音频录制权限；音频仅在本机处理。")
                    .measurePanelChrome("tips")
            }
        }
        .onAppear { filter = options.defaultToEnabledApps ? .enabled : .all }
        .onChange(of: options.defaultToEnabledApps) { _, enabled in filter = enabled ? .enabled : .all }
    }

    private func emptyState(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(.tertiary).accessibilityHidden(true)
            Text(title).font(.subheadline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
