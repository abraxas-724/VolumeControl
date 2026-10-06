import SwiftUI

enum PanelStyle {
    static let accent = Color.indigo
    static let cornerRadius: CGFloat = 14
}

struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: PanelStyle.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: PanelStyle.cornerRadius)
                    .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

struct PanelIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(width: 30, height: 30)
            .background(.primary.opacity(configuration.isPressed ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}
