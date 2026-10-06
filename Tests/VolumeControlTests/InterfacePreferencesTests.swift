import XCTest
@testable import VolumeControl

final class MemoryInterfacePreferences: InterfacePreferenceStoring {
    var options = InterfaceOptions()
    var saves = 0
    func load() -> InterfaceOptions { options }
    func save(_ options: InterfaceOptions) { self.options = options; saves += 1 }
}

@MainActor
final class InterfacePreferencesTests: XCTestCase {
    func testLiquidDefaultsAreClearAndTransparencyIsValidated() {
        var options = InterfaceOptions()
        XCTAssertEqual(options.glassStyle, .clear)
        XCTAssertEqual(options.glassBackgroundOpacity, 0.12, accuracy: 0.0001)
        for (value, expected) in [(Double.nan, 0.88), (.infinity, 0.88), (-0.2, 0), (1.2, 1)] {
            options.glassBackgroundTransparency = value
            XCTAssertEqual(options.safeGlassBackgroundTransparency, expected)
        }
        options.glassStyle = .system
        XCTAssertEqual(options.glassBackgroundOpacity, 1)
    }

    func testGlassChoicesPersistAndResetWithoutWritingOnLoad() {
        let store = MemoryInterfacePreferences()
        let preferences = InterfacePreferences(storage: store)
        XCTAssertEqual(store.saves, 0)
        preferences.options.glassStyle = .system
        preferences.options.glassBackgroundTransparency = 0.95
        let reloaded = InterfacePreferences(storage: store)
        XCTAssertEqual(reloaded.options.glassStyle, .system)
        XCTAssertEqual(reloaded.options.glassBackgroundTransparency, 0.95)
        XCTAssertEqual(store.saves, 2)
        reloaded.resetAppearance()
        XCTAssertEqual(reloaded.options.glassStyle, .clear)
        XCTAssertEqual(reloaded.options.glassBackgroundTransparency, 0.88)
    }

    func testLegacyPlayfulMotionMigratesToNativeOpeningWithoutWritingOnLoad() {
        let store = MemoryInterfacePreferences()
        store.options.motion = .playful
        let preferences = InterfacePreferences(storage: store)
        XCTAssertEqual(preferences.options.motion, .subtle)
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(InterfaceMotion.selectableCases, [.off, .subtle])
    }

    func testLoadingDoesNotWriteAndSelectionsSurviveNewModel() {
        let store = MemoryInterfacePreferences()
        let model = InterfacePreferences(storage: store)
        XCTAssertEqual(store.saves, 0)
        model.options.theme = .dark
        model.options.surface = .liquid
        model.options.accent = .teal
        model.options.defaultToEnabledApps = true
        XCTAssertEqual(InterfacePreferences(storage: store).options, model.options)
        XCTAssertEqual(store.saves, 4)
    }

    func testResetRestoresOnlyInterfaceDefaultsAndDoesNotRewriteUnchangedValue() {
        let store = MemoryInterfacePreferences()
        let model = InterfacePreferences(storage: store)
        model.resetAppearance()
        XCTAssertEqual(store.saves, 0)
        model.options.density = .compact
        model.options.showPercentage = false
        model.resetAppearance()
        XCTAssertEqual(model.options, InterfaceOptions())
        XCTAssertEqual(store.saves, 3)
    }

    func testGlassFallsBackOnOldSystemsAndReduceTransparencyOverridesEveryStyle() {
        var options = InterfaceOptions()
        for surface in InterfaceSurface.allCases {
            options.surface = surface
            XCTAssertEqual(options.effectiveSurface(nativeGlassAvailable: false, reduceTransparency: false), .frosted)
            XCTAssertEqual(options.effectiveSurface(nativeGlassAvailable: true, reduceTransparency: false), .liquid)
        }
        for surface in InterfaceSurface.allCases {
            options.surface = surface
            XCTAssertEqual(options.effectiveSurface(nativeGlassAvailable: true, reduceTransparency: true), .standard)
        }
    }

    func testReducedMotionOverridesUserAnimationsAndCompactLayoutIsSmaller() {
        var options = InterfaceOptions()
        for motion in InterfaceMotion.allCases {
            options.motion = motion
            XCTAssertFalse(options.allowsMotion(reduceMotion: true))
            XCTAssertNil(options.animation(reduceMotion: true))
        }
        options.motion = .off
        XCTAssertFalse(options.allowsMotion(reduceMotion: false))
        options.motion = .playful
        XCTAssertTrue(options.allowsMotion(reduceMotion: false))
        XCTAssertNotNil(options.animation(reduceMotion: false))
        XCTAssertLessThan(InterfaceDensity.compact.listHeight, InterfaceDensity.comfortable.listHeight)
    }
}
