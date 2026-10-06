import XCTest
@testable import VolumeControl

final class ProcessTapInputPlanTests: XCTestCase {
    func testUSBMicrophoneIsDisabledWhileStereoTapRemainsEnabled() throws {
        let plan = try ProcessTapInputPlan(physicalInputs: [1], aggregateInputs: [1, 2], tapChannels: 2)
        XCTAssertEqual(plan.enabledStreams, [false, true])
    }
    func testOutputOnlyDeviceAndSplitTapChannelsAreSupported() throws {
        XCTAssertEqual(try ProcessTapInputPlan(physicalInputs: [], aggregateInputs: [2], tapChannels: 2).enabledStreams, [true])
        XCTAssertEqual(try ProcessTapInputPlan(physicalInputs: [2], aggregateInputs: [2, 1, 1], tapChannels: 2).enabledStreams, [false, true, true])
    }
    func testUnknownInputOrderMissingTapAndAdditionalInputAreRejected() {
        XCTAssertThrowsError(try ProcessTapInputPlan(physicalInputs: [1], aggregateInputs: [2, 1], tapChannels: 2))
        XCTAssertThrowsError(try ProcessTapInputPlan(physicalInputs: [1], aggregateInputs: [1], tapChannels: 2))
        XCTAssertThrowsError(try ProcessTapInputPlan(physicalInputs: [1], aggregateInputs: [1, 1, 2], tapChannels: 2))
    }
}
