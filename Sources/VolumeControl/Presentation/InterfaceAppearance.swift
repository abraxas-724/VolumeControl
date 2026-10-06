import SwiftUI

private struct InterfaceOptionsKey: EnvironmentKey {
    static let defaultValue = InterfaceOptions()
}
private struct PanelMaximumHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 680
}
private struct NativePopoverGlassKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PanelReduceMotionKey: EnvironmentKey { static let defaultValue: Bool? = nil }
private struct PanelReduceTransparencyKey: EnvironmentKey { static let defaultValue: Bool? = nil }

extension EnvironmentValues {
    var panelReduceMotion: Bool? {
        get { self[PanelReduceMotionKey.self] }
        set { self[PanelReduceMotionKey.self] = newValue }
    }
    var panelReduceTransparency: Bool? {
        get { self[PanelReduceTransparencyKey.self] }
        set { self[PanelReduceTransparencyKey.self] = newValue }
    }
    var interfaceOptions: InterfaceOptions {
        get { self[InterfaceOptionsKey.self] }
        set { self[InterfaceOptionsKey.self] = newValue }
    }
    var panelMaximumHeight: CGFloat {
        get { self[PanelMaximumHeightKey.self] }
        set { self[PanelMaximumHeightKey.self] = newValue }
    }
    var usesNativePopoverGlass: Bool {
        get { self[NativePopoverGlassKey.self] }
        set { self[NativePopoverGlassKey.self] = newValue }
    }
}

extension InterfaceAccent {
    var color: Color {
        switch self {
        case .system: return Color(nsColor: .controlAccentColor)
        case .indigo: return .indigo
        case .blue: return .blue
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        }
    }
}

extension InterfaceTheme {
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

extension InterfaceOptions {
    func animation(reduceMotion: Bool, duration: Double = PanelMotion.state) -> Animation? {
        guard allowsMotion(reduceMotion: reduceMotion) else { return nil }
        return .easeOut(duration: duration)
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

enum InterfaceAppearanceSupport {
    static var nativeGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

struct VolumeSymbol: View {
    let muted: Bool
    var body: some View {
        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
    }
}
