import AppKit
import SwiftUI

/// 材质只替换背景层，面板正文及其交互状态保持同一视图身份。
struct PanelBackdrop: View {
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

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
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.clear.tint(options.accent.color.opacity(0.06)),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else { WindowFrostedBackdrop() }
            }
            if surface == .liquid {
                // 保留光学边缘与背景采样，同时使正文在鲜艳壁纸前保持对比度。
                (colorScheme == .dark ? Color.black : Color.white).opacity(colorScheme == .dark ? 0.18 : 0.12)
            }
            if surface != .standard {
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
