import Foundation

struct UserDefaultsInterfacePreferences: InterfacePreferenceStoring {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> InterfaceOptions {
        var options = InterfaceOptions()
        options.theme = value("interface.theme", fallback: options.theme)
        options.surface = value("interface.surface", fallback: options.surface)
        options.motion = value("interface.motion", fallback: options.motion)
        options.accent = value("interface.accent", fallback: options.accent)
        options.density = value("interface.density", fallback: options.density)
        // 沿用旧版百分比键，升级后保留用户选择。
        options.showPercentage = boolean("showPercentage", fallback: true)
        options.showTips = boolean("interface.showTips", fallback: true)
        options.showAdvanced = boolean("interface.showAdvanced", fallback: true)
        options.defaultToEnabledApps = boolean("interface.defaultToEnabledApps", fallback: false)
        return options
    }

    func save(_ options: InterfaceOptions) {
        defaults.set(options.theme.rawValue, forKey: "interface.theme")
        defaults.set(options.surface.rawValue, forKey: "interface.surface")
        defaults.set(options.motion.rawValue, forKey: "interface.motion")
        defaults.set(options.accent.rawValue, forKey: "interface.accent")
        defaults.set(options.density.rawValue, forKey: "interface.density")
        defaults.set(options.showPercentage, forKey: "showPercentage")
        defaults.set(options.showTips, forKey: "interface.showTips")
        defaults.set(options.showAdvanced, forKey: "interface.showAdvanced")
        defaults.set(options.defaultToEnabledApps, forKey: "interface.defaultToEnabledApps")
    }

    private func value<T: RawRepresentable>(_ key: String, fallback: T) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
    private func boolean(_ key: String, fallback: Bool) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? fallback
    }
}
