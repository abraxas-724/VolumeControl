import SwiftUI

/// 统一桌面微交互，减少动态效果时包括按压缩放在内全部关闭。
enum PanelMotion {
    static let micro = 0.12
    static let state = 0.18
    static let section = 0.20
}

enum PanelStyle {
    static let width: CGFloat = 430
    static let rowRadius: CGFloat = 8
    static let inset: CGFloat = 16
}

struct PanelIconButtonStyle: ButtonStyle {
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.panelReduceMotion) private var panelReduceMotion
    private var reduceMotion: Bool { panelReduceMotion ?? systemReduceMotion }
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
    @State private var hovered = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        label.font(.body).frame(width: 28, height: 28)
            .background(.primary.opacity(isEnabled && (hovered || isPressed) ? (isPressed ? 0.10 : 0.06) : 0),
                        in: RoundedRectangle(cornerRadius: PanelStyle.rowRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PanelStyle.rowRadius, style: .continuous)
                .strokeBorder(options.accent.color.opacity(isFocused ? 0.7 : 0), lineWidth: 2))
            .contentShape(Rectangle())
            .scaleEffect(isPressed && options.allowsMotion(reduceMotion: reduceMotion) ? 0.97 : 1)
            .opacity(isEnabled ? (isPressed ? 0.8 : 1) : 0.4)
            .onHover { hovered = $0 }
            .animation(options.animation(reduceMotion: reduceMotion, duration: PanelMotion.micro), value: hovered)
            .animation(options.animation(reduceMotion: reduceMotion, duration: PanelMotion.micro), value: isPressed)
    }
}

/// Menu 保留原生键盘与菜单行为，仅给标签增加轻量悬停反馈。
struct PanelMenuHover: ViewModifier {
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.panelReduceMotion) private var panelReduceMotion
    private var reduceMotion: Bool { panelReduceMotion ?? systemReduceMotion }

    func body(content: Content) -> some View {
        content.padding(4)
            .background(.primary.opacity(hovered && isEnabled ? 0.06 : 0),
                        in: RoundedRectangle(cornerRadius: PanelStyle.rowRadius, style: .continuous))
            .onHover { hovered = $0 }
            .animation(options.animation(reduceMotion: reduceMotion, duration: PanelMotion.micro), value: hovered)
    }
}
