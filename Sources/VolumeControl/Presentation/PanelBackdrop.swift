import AppKit
import SwiftUI

/// 材质只替换背景层，面板正文及其交互状态保持同一视图身份。
struct PanelBackdrop: View {
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let surface = options.effectiveSurface(nativeGlassAvailable: InterfaceAppearanceSupport.nativeGlassAvailable,
                                               reduceTransparency: reduceTransparency)
        ZStack {
            switch surface {
            case .standard:
                Color(nsColor: .windowBackgroundColor)
            case .frosted:
                WindowFrostedBackdrop()
            case .liquid:
                // 分区玻璃由实际卡片承载；底层只采样窗口后方，避免大玻璃覆盖小玻璃。
                WindowFrostedBackdrop(material: .underWindowBackground)
            }
            if surface == .frosted {
                LinearGradient(colors: [options.accent.color.opacity(0.06), .clear, options.accent.color.opacity(0.025)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// behindWindow 采样窗口后面的桌面/应用；不能用不透明底色遮住该材质。
struct WindowFrostedBackdrop: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.setAccessibilityElement(false)
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}
