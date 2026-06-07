import XCTest
@testable import BogiApp

final class GoalsServiceTests: XCTestCase {
    private func service() throws -> GoalsService {
        GoalsService(database: try DatabaseService(inMemory: true))
    }

    func testAddDefaultsToActiveAndStampsUpdatedAt() throws {
        let s = try service()
        let g = s.add(title: "Run a half marathon", period: "quarter", why: "feel strong")
        XCTAssertEqual(g.status, "active")
        XCTAssertEqual(g.why, "feel strong")
        XCTAssertNotNil(g.updatedAt)
    }

    func testUpdateTransitionsStatusAndFields() throws {
        let s = try service()
        let g = s.add(title: "Ship v1", period: "month")
        XCTAssertTrue(s.update(id: g.id, status: "done", target: "by Friday"))
        let reloaded = s.all().first { $0.id == g.id }
        XCTAssertEqual(reloaded?.status, "done")
        XCTAssertEqual(reloaded?.target, "by Friday")
        XCTAssertFalse(s.update(id: "nope", status: "done"))
    }

    func testAllFilterByStatus() throws {
        let s = try service()
        let a = s.add(title: "A", period: "month")
        _ = s.add(title: "B", period: "month")
        XCTAssertTrue(s.update(id: a.id, status: "done"))
        XCTAssertEqual(s.all(status: "active").count, 1)
        XCTAssertEqual(s.all(status: "active").first?.title, "B")
    }
}
