import XCTest
@testable import BogiApp

final class MeetingReminderPlannerTests: XCTestCase {

    private func block(id: String, startsInMinutes minutes: Double, from now: Date,
                       status: String = "planned", title: String = "Standup") -> PlannedBlock {
        let start = now.addingTimeInterval(minutes * 60)
        return PlannedBlock(
            id: id, source: "google", externalEventId: id, title: title,
            startAt: start, endAt: start.addingTimeInterval(1800),
            category: nil, goalId: nil, status: status, createdByBogi: false, updatedAt: now)
    }

    func testFiresEachThresholdOnceAsTimeAdvances() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var fired: Set<String> = []

        // 28 min out → only the 30-min reminder.
        var due = MeetingReminderPlanner.due(blocks: [block(id: "m", startsInMinutes: 28, from: now)],
                                             now: now, fired: &fired)
        XCTAssertEqual(due.map(\.offset), [30])
        XCTAssertEqual(due.first?.minutesUntil, 28)

        // Same block, now 14 min out → the 15-min reminder (30 already fired).
        due = MeetingReminderPlanner.due(blocks: [block(id: "m", startsInMinutes: 14, from: now)],
                                         now: now, fired: &fired)
        XCTAssertEqual(due.map(\.offset), [15])

        // Now 4 min out → the 5-min reminder.
        due = MeetingReminderPlanner.due(blocks: [block(id: "m", startsInMinutes: 4, from: now)],
                                         now: now, fired: &fired)
        XCTAssertEqual(due.map(\.offset), [5])

        // No further reminders for the same block.
        due = MeetingReminderPlanner.due(blocks: [block(id: "m", startsInMinutes: 2, from: now)],
                                         now: now, fired: &fired)
        XCTAssertTrue(due.isEmpty)
    }

    func testDoesNotFireStaleLargerThresholdForSoonBlock() {
        // A block created only 12 min out should get the 15-min reminder, never a stale 30-min one.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var fired: Set<String> = []
        let due = MeetingReminderPlanner.due(blocks: [block(id: "m", startsInMinutes: 12, from: now)],
                                             now: now, fired: &fired)
        XCTAssertEqual(due.map(\.offset), [15])
        // 30 was marked fired (moot), so it never appears later.
        let again = MeetingReminderPlanner.due(blocks: [block(id: "m", startsInMinutes: 11, from: now)],
                                               now: now, fired: &fired)
        XCTAssertTrue(again.isEmpty)
    }

    func testBlockStartingInUnderFiveMinutesFiresFiveOnly() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var fired: Set<String> = []
        let due = MeetingReminderPlanner.due(blocks: [block(id: "m", startsInMinutes: 2, from: now)],
                                             now: now, fired: &fired)
        XCTAssertEqual(due.map(\.offset), [5])
        XCTAssertEqual(due.first?.minutesUntil, 2)
    }

    func testIgnoresFarFutureStartedAndNonPlannedBlocks() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var fired: Set<String> = []
        let due = MeetingReminderPlanner.due(blocks: [
            block(id: "far", startsInMinutes: 45, from: now),                    // too far out
            block(id: "past", startsInMinutes: -3, from: now),                   // already started
            block(id: "orphan", startsInMinutes: 10, from: now, status: "orphaned")  // not planned
        ], now: now, fired: &fired)
        XCTAssertTrue(due.isEmpty)
    }

    func testHandlesMultipleBlocksIndependently() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var fired: Set<String> = []
        let due = MeetingReminderPlanner.due(blocks: [
            block(id: "a", startsInMinutes: 4, from: now, title: "1:1"),
            block(id: "b", startsInMinutes: 28, from: now, title: "Review")
        ], now: now, fired: &fired)
        XCTAssertEqual(Set(due.map(\.blockId)), ["a", "b"])
        XCTAssertEqual(due.first(where: { $0.blockId == "a" })?.offset, 5)
        XCTAssertEqual(due.first(where: { $0.blockId == "b" })?.offset, 30)
    }
}
