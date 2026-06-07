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
          "cat": "scroll",
          "sub": "Social",
          "title": "Scrolling X feed",
          "on_task": false,
          "confidence": 0.9
        },
        {
          "start_at": "2026-06-06T10:02:30Z",
          "end_at": "2026-06-06T10:05:00Z",
          "minutes": 2.5,
          "cat": "leisure",
          "sub": "Video",
          "title": "YouTube",
          "on_task": false,
          "confidence": 0.8
        }
      ],
      "nudge": { "should": true, "severity": 2, "message": "You planned deep work but you're on X. Close it." }
    }
    """

    // MARK: - parse

    func testParseCleanJSON() throws {
        let output = try JudgeOutput.parse(offTaskJSON)
        XCTAssertEqual(output.segments.count, 2)
        XCTAssertEqual(output.segments.first?.title, "Scrolling X feed")
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

    // MARK: - userJSON

    func testUserJSONIncludesFocusedFlag() {
        let input = JudgeInput(
            activeBlock: nil,
            observations: [(t: Date(timeIntervalSince1970: 0), app: "Xcode",
                            window: "Bogi", text: "code", focused: true)],
            recentOffTaskMinutes: 0)
        let json = JudgePrompt.userJSON(input)
        XCTAssertTrue(json.contains("\"focused\""), "observation JSON should carry focused")
    }

    // MARK: - offTaskMinutes

    func testOffTaskMinutesSumsOnlyInWindowOffTask() throws {
        let db = try DatabaseService(inMemory: true)
        let store = SegmentStore(database: db)
        let now = Date(timeIntervalSince1970: 100_000)

        func segment(id: String, startOffset: TimeInterval, minutes: Double, onTask: Bool) -> ActivitySegment {
            let start = now.addingTimeInterval(startOffset)
            return ActivitySegment(
                id: id, startAt: start, endAt: start.addingTimeInterval(minutes * 60),
                minutes: minutes, plannedBlockId: nil,
                cat: "scroll", sub: nil, title: nil, desc: nil,
                onTask: onTask, confidence: 0.9, judgedAt: now)
        }

        // In window, off-task → counted (2.5 + 3.5 = 6.0).
        store.insert(segment(id: "a", startOffset: -600, minutes: 2.5, onTask: false))
        store.insert(segment(id: "b", startOffset: -1800, minutes: 3.5, onTask: false))
        // In window but on-task → excluded.
        store.insert(segment(id: "c", startOffset: -300, minutes: 4.0, onTask: true))
        // Off-task but older than the 60-min window → excluded.
        store.insert(segment(id: "d", startOffset: -4000, minutes: 5.0, onTask: false))

        XCTAssertEqual(store.offTaskMinutes(within: 3600, now: now), 6)
    }
}