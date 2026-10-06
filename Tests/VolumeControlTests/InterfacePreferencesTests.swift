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
        options.surface = .liquid
        XCTAssertEqual(options.effectiveSurface(nativeGlassAvailable: false, reduceTransparency: false), .frosted)
        XCTAssertEqual(options.effectiveSurface(nativeGlassAvailable: true, reduceTransparency: false), .liquid)
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
