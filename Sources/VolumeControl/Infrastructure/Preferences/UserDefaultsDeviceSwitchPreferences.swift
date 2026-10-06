import Foundation

struct UserDefaultsDeviceSwitchPreferences: DeviceSwitchPreferenceStoring {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> DeviceSwitchOptions {
        DeviceSwitchOptions(
            autoSwitchHeadphones: (defaults.object(forKey: "devices.autoSwitchHeadphones") as? Bool) ?? true,
            preferredHeadphoneUID: defaults.string(forKey: "devices.preferredHeadphoneUID")
        )
    }

    func save(_ options: DeviceSwitchOptions) {
        defaults.set(options.autoSwitchHeadphones, forKey: "devices.autoSwitchHeadphones")
        if let uid = options.preferredHeadphoneUID { defaults.set(uid, forKey: "devices.preferredHeadphoneUID") }
        else { defaults.removeObject(forKey: "devices.preferredHeadphoneUID") }
    }
}
