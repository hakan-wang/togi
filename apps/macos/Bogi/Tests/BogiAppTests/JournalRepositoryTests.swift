import XCTest
@testable import BogiApp

final class JournalRepositoryTests: XCTestCase {
    private func repo() throws -> JournalRepository {
        JournalRepository(database: try DatabaseService(inMemory: true))
    }

    private func entry(_ id: String, kind: String, goalId: String? = nil) -> JournalEntry {
        JournalEntry(id: id, createdAt: Date(), kind: kind, goalId: goalId, cat: nil,
                     title: "t-\(id)", desc: nil, confidence: nil, evidence: nil, status: "active")
    }

    func testInsertAndFilterByKind() throws {
        let db = try DatabaseService(inMemory: true)
        let r = JournalRepository(database: db)
        let goals = GoalsService(database: db)
        let g = goals.add(title: "Test goal", period: "month")
        r.insert(entry("a", kind: "insight"))
        r.insert(entry("b", kind: "checkin", goalId: g.id))
        XCTAssertEqual(r.entries(kind: "insight").map { $0.id }, ["a"])
        XCTAssertEqual(r.entries(goalId: g.id).map { $0.id }, ["b"])
        XCTAssertEqual(r.entries().count, 2)
    }

    func testSetStatusHides() throws {
        let r = try repo()
        r.insert(entry("a", kind: "insight"))
        r.setStatus(id: "a", status: "dismissed")
        XCTAssertEqual(r.entries(kind: "insight", status: "active").count, 0)
        XCTAssertEqual(r.entries(kind: "insight", status: "dismissed").count, 1)
    }

    func testUserEventForGoalAndDelete() throws {
        let db = try DatabaseService(inMemory: true)
        let events = UserEventRepository(database: db)
        let goals = GoalsService(database: db)
        let g = goals.add(title: "Half marathon", period: "quarter")
        let now = Date()
        let e = UserEvent(id: "ev1", title: "Check in: half marathon", desc: nil, cat: "checkin",
                          sub: nil, startAt: now, endAt: now.addingTimeInterval(300),
                          createdAt: now, goalId: g.id)
        events.insert(e)
        XCTAssertEqual(events.events(forGoal: g.id).map { $0.id }, ["ev1"])
        events.delete(id: "ev1")
        XCTAssertTrue(events.events(forGoal: g.id).isEmpty)
    }

    func testDueCheckInsReturnsOnlyGoalLinkedPastEvents() throws {
        let db = try DatabaseService(inMemory: true)
        let goals = GoalsService(database: db)
        let events = UserEventRepository(database: db)
        let g = goals.add(title: "Half marathon", period: "quarter")
        let past = Date().addingTimeInterval(-60)
        let future = Date().addingTimeInterval(3600)
        events.insert(UserEvent(id: "due1", title: "Check in", desc: nil, cat: nil, sub: nil,
                                startAt: past, endAt: past.addingTimeInterval(300), createdAt: past, goalId: g.id))
        events.insert(UserEvent(id: "notyet", title: "Check in later", desc: nil, cat: nil, sub: nil,
                                startAt: future, endAt: future.addingTimeInterval(300), createdAt: past, goalId: g.id))
        events.insert(UserEvent(id: "plain", title: "Gym", desc: nil, cat: nil, sub: nil,
                                startAt: past, endAt: past.addingTimeInterval(300), createdAt: past, goalId: nil))
        let dueNow = events.dueCheckIns(asOf: Date())
        XCTAssertEqual(dueNow.map { $0.id }, ["due1"])
    }
}
