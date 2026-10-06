import XCTest
@testable import VolumeControl

final class AudioBufferBudgetTests: XCTestCase {
    func testBackpressureLimitsCountAndReleasesAfterPlayback() throws {
        let budget = AudioBufferBudget(maximumBuffers: 2, maximumDuration: 1)
        let first = try XCTUnwrap(budget.reserve(duration: 0.1))
        XCTAssertNotNil(budget.reserve(duration: 0.1))
        XCTAssertNil(budget.reserve(duration: 0.1))
        budget.finish(first)
        budget.finish(first)
        XCTAssertNotNil(budget.reserve(duration: 0.1))
        XCTAssertNil(budget.reserve(duration: 0.1))
    }

    func testDurationLimitDoesNotAssumeTapRespectsRequestedFrameCount() {
        let budget = AudioBufferBudget(maximumBuffers: 10, maximumDuration: 0.25)
        XCTAssertNotNil(budget.reserve(duration: 0.1))
        XCTAssertNotNil(budget.reserve(duration: 0.1))
        XCTAssertNil(budget.reserve(duration: 0.1))
        XCTAssertNil(budget.reserve(duration: 0.3))
    }

    func testInvalidDurationsCannotConsumeBudget() {
        let budget = AudioBufferBudget()
        for value in [0, -1, Double.nan, Double.infinity] {
            XCTAssertNil(budget.reserve(duration: value))
        }
        XCTAssertNotNil(budget.reserve(duration: 0.01))
    }

    func testLateCallbacksAndProducerAreInvalidatedOnStop() throws {
        let budget = AudioBufferBudget()
        let ticket = try XCTUnwrap(budget.reserve(duration: 0.01))
        budget.close()
        XCTAssertFalse(budget.contains(ticket))
        budget.finish(ticket)
        XCTAssertNil(budget.reserve(duration: 0.01))
    }

    func testConcurrentProducersCannotExceedBufferCount() {
        let budget = AudioBufferBudget(maximumBuffers: 4, maximumDuration: 1)
        let lock = NSLock()
        var tickets: [AudioBufferBudget.Ticket] = []
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            if let ticket = budget.reserve(duration: 0.01) {
                lock.lock()
                tickets.append(ticket)
                lock.unlock()
            }
        }
        XCTAssertEqual(tickets.count, 4)
        tickets.forEach { budget.finish($0) }
        XCTAssertNotNil(budget.reserve(duration: 0.01))
    }
}
