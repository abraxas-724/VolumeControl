import XCTest
@testable import VolumeControl

final class AudioRoutingBufferPlanTests: XCTestCase {
    func testUSBMicrophoneAndBlackHoleOutputAreExcluded() throws {
        let plan = try AudioRoutingBufferPlan(physicalInputs: [1], physicalOutputs: [2], virtualInputs: [2], virtualOutputs: [2], aggregateInputs: [1, 2], aggregateOutputs: [2, 2])
        XCTAssertEqual(plan.inputStart, 1)
        XCTAssertEqual(plan.inputCount, 1)
        XCTAssertEqual(plan.outputCount, 1)
        XCTAssertEqual(plan.inputStreams, [false, true])
        XCTAssertEqual(plan.outputStreams, [true, false])
    }
    func testReorderedStreamsAndChannelMismatchFailBeforeStarting() {
        XCTAssertThrowsError(try AudioRoutingBufferPlan(physicalInputs: [1], physicalOutputs: [2], virtualInputs: [2], virtualOutputs: [2], aggregateInputs: [2, 1], aggregateOutputs: [2, 2]))
        XCTAssertThrowsError(try AudioRoutingBufferPlan(physicalInputs: [], physicalOutputs: [1], virtualInputs: [2], virtualOutputs: [2], aggregateInputs: [2], aggregateOutputs: [1, 2]))
    }
}
