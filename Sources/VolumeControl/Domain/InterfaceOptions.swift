import Foundation

enum InterfaceTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var label: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
}

enum InterfaceSurface: String, CaseIterable, Identifiable {
    case standard, frosted, liquid
    var id: Self { self }
    var label: String { switch self { case .standard: return "经典"; case .frosted: return "磨砂玻璃"; case .liquid: return "液态玻璃" } }
}

enum InterfaceMotion: String, CaseIterable, Identifiable {
    case off, subtle, playful
    var id: Self { self }
    var label: String { switch self { case .off: return "关闭"; case .subtle: return "轻柔"; case .playful: return "灵动" } }
}

enum InterfaceAccent: String, CaseIterable, Identifiable {
    case indigo, blue, teal, green, orange, pink
    var id: Self { self }
    var label: String { switch self { case .indigo: return "靛蓝"; case .blue: return "海蓝"; case .teal: return "青色"; case .green: return "薄荷"; case .orange: return "暖橙"; case .pink: return "樱粉" } }
}

enum InterfaceDensity: String, CaseIterable, Identifiable {
    case comfortable, compact
    var id: Self { self }
    var label: String { self == .compact ? "紧凑" : "舒适" }
    var listHeight: Double { self == .compact ? 260 : 320 }
    var cardPadding: Double { self == .compact ? 10 : 14 }
}

/// 界面偏好独立于音频授权和增益；重置外观不会改变播放或登录项。
struct InterfaceOptions: Equatable {
    var theme: InterfaceTheme = .system
    var surface: InterfaceSurface = .standard
    var motion: InterfaceMotion = .subtle
    var accent: InterfaceAccent = .indigo
    var density: InterfaceDensity = .comfortable
    var showPercentage = true
    var showTips = true
    var showAdvanced = true
    var defaultToEnabledApps = false

    func effectiveSurface(nativeGlassAvailable: Bool, reduceTransparency: Bool) -> InterfaceSurface {
        guard !reduceTransparency else { return .standard }
        return surface == .liquid && !nativeGlassAvailable ? .frosted : surface
    }

    func allowsMotion(reduceMotion: Bool) -> Bool { motion != .off && !reduceMotion }
}

protocol InterfacePreferenceStoring {
    func load() -> InterfaceOptions
    func save(_ options: InterfaceOptions)
}
