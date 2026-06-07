import XCTest
@testable import BogiApp

final class CategoryRepositoryTests: XCTestCase {
    private func repo() throws -> CategoryRepository {
        CategoryRepository(database: try DatabaseService(inMemory: true))
    }

    func testAllReturnsSeededNine() throws {
        let all = try repo().all()
        XCTAssertEqual(all.count, 9)
        XCTAssertEqual(all.first?.id, "deepwork")           // sort_order 0
        XCTAssertEqual(all.first?.color, "#2E5BFF")
    }

    func testExistsAndColor() throws {
        let r = try repo()
        XCTAssertTrue(r.exists("scroll"))
        XCTAssertFalse(r.exists("nope"))
        XCTAssertEqual(r.color(for: "health"), "#22C55E")
        XCTAssertNil(r.color(for: "nope"))
    }

    func testAddCreatesSluggedEntry() throws {
        let r = try repo()
        let added = r.add(name: "Side Project", color: "#123456", description: nil)
        XCTAssertEqual(added?.id, "sideproject")
        XCTAssertTrue(r.exists("sideproject"))
        XCTAssertNil(r.add(name: "Side Project"))  // no dupes — second add returns nil
        XCTAssertEqual(r.all().filter { $0.id == "sideproject" }.count, 1)
    }

    func testRenameAndRecolor() throws {
        let r = try repo()
        XCTAssertTrue(r.rename(id: "scroll", name: "Doomscroll"))
        XCTAssertEqual(r.all().first { $0.id == "scroll" }?.name, "Doomscroll")
        XCTAssertTrue(r.recolor(id: "scroll", color: "#000000"))
        XCTAssertEqual(r.color(for: "scroll"), "#000000")
        XCTAssertFalse(r.rename(id: "nope", name: "X"))
    }

    func testMergeReassignsAcrossAllTablesAndDeletes() throws {
        let db = try DatabaseService(inMemory: true)
        let r = CategoryRepository(database: db)
        try db.dbQueue.write { conn in
            try conn.execute(sql: "INSERT INTO activity_segments (id,start_at,end_at,minutes,cat,judged_at) VALUES ('s1','2026-06-06 10:00:00','2026-06-06 10:05:00',5,'scroll','2026-06-06 10:05:00')")
            try conn.execute(sql: "INSERT INTO planned_blocks (id,source,title,start_at,end_at,cat,status,created_by_bogi,updated_at) VALUES ('p1','local','x','2026-06-06 09:00:00','2026-06-06 10:00:00','scroll','planned',1,'2026-06-06 09:00:00')")
            try conn.execute(sql: "INSERT INTO user_events (id,title,cat,start_at,end_at,created_at) VALUES ('e1','y','scroll','2026-06-06 11:00:00','2026-06-06 12:00:00','2026-06-06 08:00:00')")
        }
        XCTAssertTrue(r.merge(from: "scroll", into: "social"))
        XCTAssertFalse(r.exists("scroll"))
        try db.dbQueue.read { conn in
            for table in ["activity_segments", "planned_blocks", "user_events"] {
                let leftover = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM \(table) WHERE cat = 'scroll'") ?? -1
                XCTAssertEqual(leftover, 0, "\(table) still has scroll")
                let moved = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM \(table) WHERE cat = 'social'") ?? -1
                XCTAssertEqual(moved, 1, "\(table) not reassigned to social")
            }
        }
        XCTAssertFalse(r.merge(from: "nope", into: "social"))
    }
}
