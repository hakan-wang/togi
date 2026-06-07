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
}
