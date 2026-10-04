import Foundation

struct UserDefaultsAppAudioPreferences: AppAudioPreferenceStoring {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load(_ bundleID: String) throws -> AppAudioPreferences {
        guard let data = defaults.data(forKey: key(bundleID)) else { return AppAudioPreferences() }
        var preferences = try JSONDecoder().decode(AppAudioPreferences.self, from: data)
        preferences.volume = try AppAudioPreferences.validatedVolume(preferences.volume)
        return preferences
    }

    func save(_ preferences: AppAudioPreferences, for bundleID: String) throws {
        let data = try JSONEncoder().encode(preferences)
        defaults.set(data, forKey: key(bundleID))
    }
    private func key(_ bundleID: String) -> String { "processTapVolume.v1.\(bundleID)" }
}
