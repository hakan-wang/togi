import XCTest
@testable import BogiApp

final class FakeCoachBackend: CoachBackend {
    var lastText: String?
    var lastThread: String?
    /// Every thread id seen, in call order, so tests can assert how the conversation thread
    /// rotates across asks.
    var threads: [String] = []
    func chat(_ text: String, threadId: String) async throws -> String {
        lastText = text; lastThread = threadId
        threads.append(threadId)
        return "Nice work, you focused two hours today."
    }
}

final class CoachTests: XCTestCase {
    func testAskForwardsToBackend() async throws {
        let backend = FakeCoachBackend()
        let coach = CoachService(backend: backend, threadId: "coach-1")
        let answer = try await coach.ask("how was today?")
        XCTAssertEqual(answer, "Nice work, you focused two hours today.")
        XCTAssertEqual(backend.lastText, "how was today?")
        XCTAssertEqual(backend.lastThread, "coach-1")
    }

    func testClearConversationStartsFreshThreadButKeepsTalking() async throws {
        let backend = FakeCoachBackend()
        let coach = CoachService(backend: backend, threadId: "coach")

        // Messages before clearing all share the original thread (one conversation).
        _ = try await coach.ask("first")
        _ = try await coach.ask("second")
        XCTAssertEqual(backend.threads, ["coach", "coach"])

        // Clearing rotates to a new, non-empty thread so the agent forgets the prior chat.
        coach.clearConversation()
        _ = try await coach.ask("after clear")
        let fresh = try XCTUnwrap(backend.threads.last)
        XCTAssertNotEqual(fresh, "coach")
        XCTAssertFalse(fresh.isEmpty)

        // Subsequent messages stay on the new thread — it's a continuing conversation, not a
        // new thread per message.
        _ = try await coach.ask("again")
        XCTAssertEqual(backend.threads.suffix(2), [fresh, fresh])
    }
}
