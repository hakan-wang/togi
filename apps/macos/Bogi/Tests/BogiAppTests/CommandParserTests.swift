import XCTest
@testable import BogiApp

final class CommandParserTests: XCTestCase {
    private let now = TestClock.reference            // Sat 2026-06-06 12:00 UTC
    private let cal = TestClock.utcCalendar

    private func parse(_ text: String) -> ParsedCommand {
        CommandParser.parse(text, now: now, calendar: cal)
    }

    func testDurationWithActivityNoTime() {
        let cmd = parse("one hour to edit videos tomorrow")
        XCTAssertEqual(cmd.action, .create)
        XCTAssertEqual(cmd.title, "edit videos")
        XCTAssertEqual(cmd.durationMinutes, 60)
        XCTAssertNil(cmd.startAt)            // no clock time given
        XCTAssertTrue(cmd.confident)
    }

    func testBareTimeCreate() {
        let cmd = parse("put a meeting at 3")
        XCTAssertEqual(cmd.action, .create)
        XCTAssertEqual(cmd.title, "meeting")
        let start = try? XCTUnwrap(cmd.startAt)
        XCTAssertEqual(cal.component(.hour, from: start!), 3)
        XCTAssertEqual(cal.component(.day, from: start!), 6)
        // No explicit duration → default 60 min applied to end.
        XCTAssertEqual(cmd.endAt, cmd.startAt?.addingTimeInterval(3600))
    }

    func testDurationDayAndTime() {
        let cmd = parse("30 minutes to read at 9am tomorrow")
        XCTAssertEqual(cmd.title, "read")
        XCTAssertEqual(cmd.durationMinutes, 30)
        let start = try? XCTUnwrap(cmd.startAt)
        XCTAssertEqual(cal.component(.day, from: start!), 7)     // tomorrow
        XCTAssertEqual(cal.component(.hour, from: start!), 9)
        XCTAssertEqual(cmd.endAt, start!.addingTimeInterval(30 * 60))
    }

    func testWakePhraseAndSpelledDuration() {
        let cmd = parse("Hey Bogi, block 2 hours for deep work")
        XCTAssertEqual(cmd.title, "deep work")
        XCTAssertEqual(cmd.durationMinutes, 120)
        XCTAssertEqual(cmd.action, .create)
    }

    func testHalfAnHour() {
        let cmd = parse("schedule a stretch break for half an hour")
        XCTAssertEqual(cmd.durationMinutes, 30)
        XCTAssertEqual(cmd.title, "stretch break")
    }

    func testMoveCommandToTime() {
        let cmd = parse("reschedule deep work to 5pm")
        XCTAssertEqual(cmd.action, .move)
        XCTAssertEqual(cmd.title, "deep work")
        let start = try? XCTUnwrap(cmd.startAt)
        XCTAssertEqual(cal.component(.hour, from: start!), 17)
    }

    func testCategoryTagAndMeridiem() {
        let cmd = parse("schedule gym at 6am #health")
        XCTAssertEqual(cmd.category, "health")
        XCTAssertEqual(cmd.title, "gym")
        let start = try? XCTUnwrap(cmd.startAt)
        XCTAssertEqual(cal.component(.hour, from: start!), 6)
    }

    func testWeekdayResolution() {
        // Next Monday after Sat 2026-06-06 is 2026-06-08.
        let cmd = parse("block an hour for planning on monday at 10am")
        let start = try? XCTUnwrap(cmd.startAt)
        XCTAssertEqual(cal.component(.day, from: start!), 8)
        XCTAssertEqual(cal.component(.hour, from: start!), 10)
        XCTAssertEqual(cmd.title, "planning")
    }

    func testTwentyFourHourClock() {
        let cmd = parse("put a review at 15:30")
        let start = try? XCTUnwrap(cmd.startAt)
        XCTAssertEqual(cal.component(.hour, from: start!), 15)
        XCTAssertEqual(cal.component(.minute, from: start!), 30)
    }

    func testUnrecognizedIsNotConfident() {
        let cmd = parse("hello there friend")
        XCTAssertFalse(cmd.confident)       // no duration and no time → defer to LLM
    }

    // MARK: - LLM fallback

    func testInferenceRequestShape() {
        let request = CommandParser.inferenceRequest(for: "do the thing next week", now: now, calendar: cal)
        XCTAssertEqual(request.messages.first?.role, .system)
        XCTAssertEqual(request.messages.last?.role, .user)
        XCTAssertEqual(request.messages.last?.content, "do the thing next week")
        XCTAssertTrue(request.messages.first?.content.contains("JSON") == true)
    }

    func testParseLLMResponseJSON() {
        let json = """
        Sure! {"action":"create","title":"edit videos","category":"content",\
        "start":"2026-06-07T14:00:00Z","end":"2026-06-07T15:00:00Z","durationMinutes":60}
        """
        let cmd = try? XCTUnwrap(CommandParser.parse(llmResponse: json))
        XCTAssertEqual(cmd?.action, .create)
        XCTAssertEqual(cmd?.title, "edit videos")
        XCTAssertEqual(cmd?.category, "content")
        XCTAssertEqual(cmd?.durationMinutes, 60)
        XCTAssertNotNil(cmd?.startAt)
    }

    func testParseLLMResponseRejectsGarbage() {
        XCTAssertNil(CommandParser.parse(llmResponse: "no json here"))
    }
}
