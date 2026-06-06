import XCTest
@testable import BogiApp

final class FakeCoachBackend: CoachBackend {
    var lastText: String?
    var lastThread: String?
    func chat(_ text: String, threadId: String) async throws -> String {
        lastText = text; lastThread = threadId
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
}
