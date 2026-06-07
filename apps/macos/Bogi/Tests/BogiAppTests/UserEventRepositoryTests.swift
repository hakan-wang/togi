import XCTest
import GRDB
@testable import BogiApp

final class UserEventRepositoryTests: XCTestCase {
    private func make() throws -> (UserEventRepository, DatabaseService) {
        let db = try DatabaseService(inMemory: true)
        return (UserEventRepository(database: db), db)
    }
    private func ev(_ id: String, _ start: String, _ end: String) -> UserEvent {
        let iso = ISO8601DateFormatter()
        return UserEvent(id: id, title: "Gym", desc: nil, cat: "health", sub: nil,
                         startAt: iso.date(from: start)!, endAt: iso.date(from: end)!, createdAt: Date())
    }

    func testInsertAndRangeQuery() throws {
        let (r, _) = try make()
        r.insert(ev("e1", "2026-06-06T18:00:00Z", "2026-06-06T19:00:00Z"))
        r.insert(ev("e2", "2026-06-08T18:00:00Z", "2026-06-08T19:00:00Z"))
        let iso = ISO8601DateFormatter()
        let inRange = r.events(inRange: iso.date(from: "2026-06-06T00:00:00Z")!, iso.date(from: "2026-06-06T23:59:59Z")!)
        XCTAssertEqual(inRange.map { $0.id }, ["e1"])
    }

    func testOverlappingForJudge() throws {
        let (r, _) = try make()
        r.insert(ev("e1", "2026-06-06T18:00:00Z", "2026-06-06T19:00:00Z"))
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(r.events(overlapping: iso.date(from: "2026-06-06T18:30:00Z")!).map { $0.id }, ["e1"])
        XCTAssertTrue(r.events(overlapping: iso.date(from: "2026-06-06T20:00:00Z")!).isEmpty)
    }
}
