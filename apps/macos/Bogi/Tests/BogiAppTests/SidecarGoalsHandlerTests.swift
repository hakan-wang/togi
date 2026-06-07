import XCTest
@testable import BogiApp

final class SidecarGoalsHandlerTests: XCTestCase {
    private func iso(_ s: String) -> String { s }

    func testManageGoalAddRoutes() async {
        var seenOp: String?
        let h = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            manageGoal: { op, _ in seenOp = op; return ["ok": true, "id": "g1"] })
        let out = await h.handle("manage_goal", ["op": "add", "title": "Half marathon"])
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(seenOp, "add")
    }

    func testLogJournalRejectsBadKind() async {
        let h = SidecarActionHandlers(createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil })
        let out = await h.handle("log_journal", ["kind": "nonsense", "title": "x"])
        XCTAssertEqual(out["error"] as? String, "bad_input")
    }

    func testLogJournalInsertsValidEntry() async {
        var inserted: JournalEntry?
        let h = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            logJournal: { entry in inserted = entry; return entry.id })
        let out = await h.handle("log_journal", ["kind": "insight", "title": "Loses focus ~35m into editing", "confidence": 0.7])
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(inserted?.kind, "insight")
        XCTAssertEqual(inserted?.title, "Loses focus ~35m into editing")
    }

    func testLogJournalRejectsUnknownCat() async {
        let h = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            categoryExists: { _ in false },
            logJournal: { $0.id })
        let out = await h.handle("log_journal", ["kind": "insight", "title": "x", "cat": "ghost"])
        XCTAssertEqual(out["error"] as? String, "bad_input")
    }

    func testAddEventCarriesGoalId() async {
        var seen: UserEvent?
        let h = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            addEvent: { ev in seen = ev; return ev.id })
        let out = await h.handle("add_event", [
            "title": "Check in", "start": "2026-06-08T18:00:00Z", "end": "2026-06-08T18:05:00Z",
            "goal_id": "g1"])
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(seen?.goalId, "g1")
    }
}
