import XCTest
@testable import BogiApp

final class JudgeProactivityTests: XCTestCase {
    func testPayloadSerializesGoalsAndDueCheckIns() {
        let now = Date()
        var input = JudgeInput(
            activeBlock: nil,
            observations: [(t: now, app: "Final Cut", window: "edit", text: nil, focused: true)],
            recentOffTaskMinutes: 0)
        input.activeGoals = [(id: "g1", title: "Half marathon", status: "active", cat: "health")]
        input.dueCheckIns = [(eventId: "ev1", goalId: "g1", title: "Check in: half marathon")]

        let json = JudgePrompt.userJSON(input)
        XCTAssertTrue(json.contains("active_goals"))
        XCTAssertTrue(json.contains("due_check_ins"))
        XCTAssertTrue(json.contains("Half marathon"))
        XCTAssertTrue(json.contains("ev1"))
    }

    func testPayloadOmitsGoalsAndCheckInsWhenEmpty() {
        let input = JudgeInput(activeBlock: nil, observations: [], recentOffTaskMinutes: 0)
        let json = JudgePrompt.userJSON(input)
        XCTAssertFalse(json.contains("active_goals"))
        XCTAssertFalse(json.contains("due_check_ins"))
    }
}
