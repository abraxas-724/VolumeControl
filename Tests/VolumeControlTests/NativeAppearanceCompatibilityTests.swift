import XCTest
@testable import VolumeControl

@MainActor
final class NativeAppearanceCompatibilityTests: XCTestCase {
    func testSystemAccentAndLegacyMaterialPreferencesRoundTripWithoutMigrationWrites() throws {
        let suite = "VolumeControlTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = UserDefaultsInterfacePreferences(defaults: defaults)
        XCTAssertEqual(storage.load().accent, .system)
        for surface in InterfaceSurface.allCases {
            for style in InterfaceGlassStyle.allCases {
                var legacy = InterfaceOptions()
                legacy.surface = surface
                legacy.glassStyle = style
                legacy.glassBackgroundTransparency = 0.37
                legacy.accent = .teal
                legacy.showPercentage = false
                storage.save(legacy)
                let preferences = InterfacePreferences(storage: storage)
                XCTAssertEqual(preferences.options, legacy)
                preferences.options.accent = .system
                let loaded = storage.load()
                XCTAssertEqual(loaded.accent, .system)
                XCTAssertEqual(loaded.surface, surface)
                XCTAssertEqual(loaded.glassStyle, style)
                XCTAssertEqual(loaded.glassBackgroundTransparency, 0.37)
                XCTAssertFalse(loaded.showPercentage)
            }
        }
    }
}
