import AppKit
import XCTest
@testable import VolumeControl

final class AppListFilterTests: XCTestCase {
    private func app(_ id: String, name: String, capability: AppAudioCapability = .noAudioSession,
                     remembered: Bool = false, preparing: Bool = false) -> AppVolume {
        AppVolume(id: id, name: name, icon: NSImage(size: NSSize(width: 16, height: 16)),
                  volume: 1, capability: capability, isPreparing: preparing, isRemembered: remembered)
    }

    func testEnabledIncludesRememberedAndPreparingWithoutClaimingSupport() {
        let apps = [app("1", name: "Music", capability: .supported),
                    app("2", name: "Chrome", remembered: true),
                    app("3", name: "Safari", preparing: true),
                    app("4", name: "Notes")]
        let result = AppListFilter.enabled.applications(from: apps, matching: "")
        XCTAssertEqual(result.map(\.id), ["1", "2", "3"])
        XCTAssertFalse(result[1].capability.isSupported)
        XCTAssertFalse(result[2].capability.isSupported)
    }

    func testSearchTrimsWhitespaceAndMatchesCaseInsensitiveAndChineseNames() {
        let apps = [app("1", name: "Google Chrome"), app("2", name: "腾讯会议"), app("3", name: "Music")]
        XCTAssertEqual(AppListFilter.all.applications(from: apps, matching: "  CHROME \n").map(\.id), ["1"])
        XCTAssertEqual(AppListFilter.all.applications(from: apps, matching: "会议").map(\.id), ["2"])
        XCTAssertEqual(AppListFilter.all.applications(from: apps, matching: " \n").map(\.id), ["1", "2", "3"])
    }

    func testSearchAndFilterIntersectPreservingOrderAndIndependentProcesses() {
        let apps = [app("1", name: "Chrome", capability: .supported),
                    app("2", name: "Chrome"), app("3", name: "Chrome", remembered: true)]
        XCTAssertEqual(AppListFilter.enabled.applications(from: apps, matching: "chrome").map(\.id), ["1", "3"])
        XCTAssertTrue(AppListFilter.enabled.applications(from: apps, matching: "Safari").isEmpty)
        XCTAssertTrue(AppListFilter.all.applications(from: [], matching: "").isEmpty)
    }
}
