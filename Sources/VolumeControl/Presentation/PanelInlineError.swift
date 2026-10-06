import SwiftUI

struct PanelInlineError: View {
    let message: String
    let dismiss: () -> Void
    @State private var showDetails = false
    private var summary: String {
        String((message.split(separator: "\n").first.map(String.init) ?? message).prefix(80))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("操作未完成").font(.subheadline)
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(message)
                }
                Spacer(minLength: 4)
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(PanelIconButtonStyle()).foregroundStyle(.secondary)
                    .accessibilityLabel("关闭错误提示").help("关闭错误提示")
            }
            if message.count > 80 || message.contains("\n") {
                DisclosureGroup("显示详情", isExpanded: $showDetails) {
                    ScrollView {
                        Text(message).font(.caption).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 80)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
