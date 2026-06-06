import XCTest
@testable import BogiApp

final class JudgeTests: XCTestCase {

    // A canned, well-formed judge reply: two off-task segments + a should=true nudge.
    private let offTaskJSON = """
    {
      "segments": [
        {
          "start_at": "2026-06-06T10:00:00Z",
          "end_at": "2026-06-06T10:02:30Z",
          "minutes": 2.5,
          "category": "Distraction",
          "sub_category": "Social",
          "sub_sub": "Scrolling X feed",
          "on_task": false,
          "confidence": 0.9
        },
        {
          "start_at": "2026-06-06T10:02:30Z",
          "end_at": "2026-06-06T10:05:00Z",
          "minutes": 2.5,
          "category": "Distraction",
          "sub_category": "Video",
          "sub_sub": "YouTube",
          "on_task": false,
          "confidence": 0.8
        }
      ],
      "nudge": { "should": true, "severity": 2, "message": "You planned deep work but you're on X. Close it." }
    }
    """

    // An on-task reply: one segment matching the plan, no nudge.
    private let onTaskJSON = """
    {
      "segments": [
        {
          "start_at": "2026-06-06T10:00:00Z",
          "end_at": "2026-06-06T10:05:00Z",
          "minutes": 5.0,
          "category": "Work",
          "sub_category": "Coding",
          "sub_sub": "Editing JudgeService.swift",
          "on_task": true,
          "confidence": 0.95
        }
      ],
      "nudge": { "should": false, "severity": 0, "message": null }
    }
    """

    // MARK: - parse

    func testParseCleanJSON() throws {
        let output = try JudgeOutput.parse(offTaskJSON)
        XCTAssertEqual(output.segments.count, 2)
        XCTAssertEqual(output.segments.first?.subSub, "Scrolling X feed")
        XCTAssertEqual(output.segments.first?.onTask, false)
        XCTAssertEqual(output.segments.first?.minutes, 2.5)
        XCTAssertTrue(output.nudge.should)
        XCTAssertEqual(output.nudge.severity, 2)
    }

    func testParseWithFencesAndProse() throws {
        let wrapped = """
        Sure! Here is my analysis of the last five minutes:

        ```json
        \(offTaskJSON)
        ```

        Let me know if you'd like more detail.
        """
        let output = try JudgeOutput.parse(wrapped)
        XCTAssertEqual(output.segments.count, 2)
        XCTAssertTrue(output.nudge.should)
        XCTAssertEqual(output.nudge.message, "You planned deep work but you're on X. Close it.")
    }

    func testParseThrowsWhenNoJSON() {
        XCTAssertThrowsError(try JudgeOutput.parse("no json here, sorry"))
    }

    // MARK: - runOnce

    private func makeInput() -> JudgeInput {
        let start = ISO8601DateFormatter().date(from: "2026-06-06T10:00:00Z")!
        return JudgeInput(
            activeBlock: (title: "Deep work", category: "Work",
                          startAt: start, endAt: start.addingTimeInterval(3600)),
            observations: [
                (t: start, app: "X", window: "Home", text: "scrolling"),
            ],
            recentOffTaskMinutes: 0
        )
    }

    func testRunOnceWritesSegmentsAndReturnsNudge() async throws {
        let db = try DatabaseService(inMemory: true)
        let store = SegmentStore(database: db)
        let inference = MockInferenceClient(response: offTaskJSON)
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let service = JudgeService(inference: inference, segmentStore: store, clock: { fixedNow })

        let nudge = try await service.runOnce(input: makeInput())

        XCTAssertEqual(store.count(), 2)
        XCTAssertTrue(nudge.should)
        XCTAssertEqual(nudge.severity, 2)
        // The judge actually built and sent a prompt.
        XCTAssertEqual(inference.lastSystem, JudgePrompt.system)
        XCTAssertEqual(inference.lastMessages.first?.role, "user")
    }

    func testRunOnceOnTaskYieldsNoNudge() async throws {
        let db = try DatabaseService(inMemory: true)
        let store = SegmentStore(database: db)
        let inference = MockInferenceClient(response: onTaskJSON)
        let service = JudgeService(inference: inference, segmentStore: store)

        let nudge = try await service.runOnce(input: makeInput())

        XCTAssertEqual(store.count(), 1)
        XCTAssertFalse(nudge.should)
    }
}
