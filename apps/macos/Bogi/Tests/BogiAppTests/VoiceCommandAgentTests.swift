import XCTest
@testable import BogiApp

/// Covers the pure decode path of the voice brain — the part that turns the model's JSON reply
/// into a calendar action. No network, mirroring the PlannerCommandParser tests.
final class VoiceCommandAgentTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testScheduleWithExplicitISO() {
        let json = """
        {"intent":"schedule","title":"Call with Sarah","start":"2026-06-07T15:00:00Z","end":"2026-06-07T15:30:00Z","say":"done, call with sarah tomorrow at 3 pm."}
        """
        guard case let .schedule(title, start, end, say) = VoiceCommandAgent.decode(json, now: now) else {
            return XCTFail("expected .schedule")
        }
        XCTAssertEqual(title, "Call with Sarah")
        XCTAssertFalse(say.isEmpty)
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(iso.string(from: start), "2026-06-07T15:00:00Z")
        XCTAssertEqual(end.timeIntervalSince(start), 30 * 60, accuracy: 1)
    }

    func testScheduleDefaultsEndToThirtyMinutes() {
        let json = """
        {"intent":"schedule","title":"Dentist","start":"2026-06-07T09:00:00Z","end":null,"say":""}
        """
        guard case let .schedule(title, start, end, say) = VoiceCommandAgent.decode(json, now: now) else {
            return XCTFail("expected .schedule")
        }
        XCTAssertEqual(title, "Dentist")
        XCTAssertEqual(end.timeIntervalSince(start), 30 * 60, accuracy: 1)
        // A confirmation line is always provided, even when the model omits one.
        XCTAssertTrue(say.contains("Dentist"))
    }

    func testScheduleWithoutTimeFallsBackToNeedInfo() {
        let json = """
        {"intent":"schedule","title":"Call mom","start":null,"end":null,"say":"what time?"}
        """
        guard case let .needInfo(say) = VoiceCommandAgent.decode(json, now: now) else {
            return XCTFail("expected .needInfo when the time is missing")
        }
        XCTAssertEqual(say, "what time?")
    }

    func testScheduleWithoutTitleFallsBackToNeedInfo() {
        let json = """
        {"intent":"schedule","title":"","start":"2026-06-07T09:00:00Z","say":""}
        """
        guard case .needInfo = VoiceCommandAgent.decode(json, now: now) else {
            return XCTFail("expected .needInfo when the title is missing")
        }
    }

    func testNeedInfo() {
        let json = #"{"intent":"need_info","say":"who is the call with?"}"#
        XCTAssertEqual(VoiceCommandAgent.decode(json, now: now), .needInfo(say: "who is the call with?"))
    }

    func testCancel() {
        let json = #"{"intent":"cancel","say":"okay, never mind."}"#
        XCTAssertEqual(VoiceCommandAgent.decode(json, now: now), .cancel(say: "okay, never mind."))
    }

    func testChat() {
        let json = #"{"intent":"chat","say":"ask me in the chat box and i'll pull your numbers."}"#
        XCTAssertEqual(
            VoiceCommandAgent.decode(json, now: now),
            .chat(say: "ask me in the chat box and i'll pull your numbers.")
        )
    }

    func testFencedJSON() {
        let json = """
        ```json
        {"intent":"need_info","say":"what day?"}
        ```
        """
        XCTAssertEqual(VoiceCommandAgent.decode(json, now: now), .needInfo(say: "what day?"))
    }

    func testProseWrappedJSON() {
        let json = "Sure! Here is the JSON: {\"intent\":\"cancel\",\"say\":\"stopped.\"} hope that helps"
        XCTAssertEqual(VoiceCommandAgent.decode(json, now: now), .cancel(say: "stopped."))
    }

    func testGarbageDegradesToChat() {
        guard case .chat = VoiceCommandAgent.decode("not json at all", now: now) else {
            return XCTFail("expected a conversational fallback on garbage input")
        }
    }

    func testOfflessLocalDatetimeParses() {
        // Model omitted the timezone offset — should still parse as local time.
        XCTAssertNotNil(VoiceCommandAgent.parseDate("2026-06-07T15:00", now: now))
        XCTAssertNil(VoiceCommandAgent.parseDate("null", now: now))
        XCTAssertNil(VoiceCommandAgent.parseDate(nil, now: now))
    }
}
