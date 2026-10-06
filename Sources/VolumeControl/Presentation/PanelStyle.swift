import SwiftUI

enum PanelStyle { static let cornerRadius: CGFloat = 18 }

struct PanelCard: ViewModifier {
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder
    func body(content: Content) -> some View {
        let surface = options.effectiveSurface(nativeGlassAvailable: InterfaceAppearanceSupport.nativeGlassAvailable,
                                               reduceTransparency: reduceTransparency)
        let padded = content.padding(options.density.cardPadding)
        if #available(macOS 26.0, *), surface == .liquid {
            // 将正文交给玻璃合成，才能获得原生光学边缘、背景透色及自适应文字。
            padded.environment(\.isInsideGlassCard, true)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            padded.background {
                let shape = RoundedRectangle(cornerRadius: PanelStyle.cornerRadius, style: .continuous)
                if surface == .frosted { shape.fill(.regularMaterial) }
                else { shape.fill(Color(nsColor: .controlBackgroundColor)) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: PanelStyle.cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }
}

struct PanelIconButtonStyle: ButtonStyle {
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        PanelButtonFeedback(label: configuration.label, isPressed: configuration.isPressed,
                            options: options, reduceMotion: reduceMotion, isEnabled: isEnabled)
    }
}

private struct PanelButtonFeedback<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let options: InterfaceOptions
    let reduceMotion: Bool
    let isEnabled: Bool

    var body: some View {
        label.font(.system(size: 13, weight: .medium)).frame(width: 32, height: 32)
            .modifier(InteractiveSurface())
            .overlay(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(isPressed ? 0.08 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(options.animation(reduceMotion: reduceMotion), value: isPressed)
    }
}
