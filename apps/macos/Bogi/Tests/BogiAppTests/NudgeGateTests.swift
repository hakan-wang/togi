import XCTest
@testable import BogiApp

final class NudgeGateTests: XCTestCase {
    func testGateOpensWhenOffTaskExceedsThreshold() {
        let gate = NudgeGate(offTaskMinutesThreshold: 3)
        let segs = [
            JudgeSegment(startAt: Date(), endAt: Date(), minutes: 2, category: "Distraction",
                         subCategory: nil, subSub: nil, onTask: false, confidence: 0.9),
            JudgeSegment(startAt: Date(), endAt: Date(), minutes: 2, category: "Distraction",
                         subCategory: nil, subSub: nil, onTask: false, confidence: 0.9),
        ]
        XCTAssertTrue(gate.shouldConsiderNudge(segments: segs, hasActivePlan: true))
    }

    func testGateStaysClosedWhenOnTask() {
        let gate = NudgeGate(offTaskMinutesThreshold: 3)
        let segs = [JudgeSegment(startAt: Date(), endAt: Date(), minutes: 5, category: "Work",
                                 subCategory: nil, subSub: nil, onTask: true, confidence: 0.9)]
        XCTAssertFalse(gate.shouldConsiderNudge(segments: segs, hasActivePlan: true))
    }

    func testGateStaysClosedWithoutAPlan() {
        let gate = NudgeGate(offTaskMinutesThreshold: 0)
        let segs = [JudgeSegment(startAt: Date(), endAt: Date(), minutes: 9, category: "Distraction",
                                 subCategory: nil, subSub: nil, onTask: false, confidence: 0.9)]
        XCTAssertFalse(gate.shouldConsiderNudge(segments: segs, hasActivePlan: false))
    }
}
