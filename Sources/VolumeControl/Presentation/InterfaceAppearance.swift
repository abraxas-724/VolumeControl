import SwiftUI

private struct InterfaceOptionsKey: EnvironmentKey {
    static let defaultValue = InterfaceOptions()
}

extension EnvironmentValues {
    var interfaceOptions: InterfaceOptions {
        get { self[InterfaceOptionsKey.self] }
        set { self[InterfaceOptionsKey.self] = newValue }
    }
}

extension InterfaceAccent {
    var color: Color {
        switch self { case .indigo: return .indigo; case .blue: return .blue; case .teal: return .teal
        case .green: return .green; case .orange: return .orange; case .pink: return .pink }
    }
}

extension InterfaceTheme {
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

extension InterfaceOptions {
    func animation(reduceMotion: Bool) -> Animation? {
        guard allowsMotion(reduceMotion: reduceMotion) else { return nil }
        return .easeInOut(duration: 0.18)
    }
}

struct InterfaceAppearance: ViewModifier {
    let options: InterfaceOptions
    func body(content: Content) -> some View {
        content
            .environment(\.interfaceOptions, options)
            .preferredColorScheme(options.theme.colorScheme)
            .transformEnvironment(\.colorScheme) { scheme in
                if let forced = options.theme.colorScheme { scheme = forced }
            }
            .tint(options.accent.color)
    }
}

/// 液态玻璃只用于交互控件，正文保持稳定的内容层；旧系统使用系统磨砂材质。
enum InterfaceAppearanceSupport {
    static var nativeGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

struct InteractiveSurface: ViewModifier {
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = 12
    var emphasized = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let surface = options.effectiveSurface(nativeGlassAvailable: InterfaceAppearanceSupport.nativeGlassAvailable,
                                               reduceTransparency: reduceTransparency)
        if surface == .liquid {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular.tint(emphasized ? options.accent.color.opacity(0.2) : nil).interactive(),
                                    in: RoundedRectangle(cornerRadius: radius))
            } else { frosted(content) }
        } else if surface == .frosted {
            frosted(content)
        } else {
            content.background(emphasized ? options.accent.color.opacity(0.14) : Color.primary.opacity(0.05),
                               in: RoundedRectangle(cornerRadius: radius))
        }
    }

    private func frosted(_ content: Content) -> some View {
        content.background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(0.08)))
    }
}

struct GlassControlGroup<Content: View>: View {
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: () -> Content
    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *), options.surface == .liquid && !reduceTransparency {
            GlassEffectContainer(spacing: 12) { content() }
        } else { content() }
    }
}

struct InterfaceBackdrop: View {
    @Environment(\.interfaceOptions) private var options
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if options.surface != .standard && !reduceTransparency {
                LinearGradient(colors: [options.accent.color.opacity(0.16), .clear, options.accent.color.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.allowsHitTesting(false)
    }
}

struct VolumeSymbol: View {
    let muted: Bool
    var body: some View {
        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
    }
}
