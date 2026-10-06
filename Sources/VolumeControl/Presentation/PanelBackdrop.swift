import AppKit
import SwiftUI

/// 原生 Popover 自带玻璃外壳，正文保持透明；独立预览才需要自己的背景。
struct PanelBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.panelReduceTransparency) private var panelReduceTransparency
    private var reduceTransparency: Bool { panelReduceTransparency ?? systemReduceTransparency }
    @Environment(\.usesNativePopoverGlass) private var usesNativePopoverGlass
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else if #available(macOS 26.0, *) {
                if usesNativePopoverGlass {
                    // 明亮桌面可透入 AppKit 玻璃；深色正文用系统底色保证 secondary 文本对比。
                    Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.86 : 0)
                }
                else { Color.clear.glassEffect(.regular, in: Rectangle()) }
            } else {
                WindowFrostedBackdrop()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// behindWindow 采样窗口后的桌面，避免叠加不透明底色遮挡系统材质。
struct WindowFrostedBackdrop: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.setAccessibilityElement(false)
        configure(view)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }
    private func configure(_ view: NSVisualEffectView) {
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}
