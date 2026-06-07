import XCTest
import GRDB
@testable import BogiApp

final class SchemaMigrationTests: XCTestCase {
    func testMigrationCreatesAllCoreTables() throws {
        let db = try DatabaseService(inMemory: true)

        let expected = [
            "planned_blocks", "activity_observations", "activity_segments", "nudges",
            "daily_summaries", "weekly_summaries", "monthly_summaries",
            "goals", "calendar_accounts", "settings", "account",
            "category_registry", "user_events"
        ]

        try db.dbQueue.read { conn in
            for table in expected {
                XCTAssertTrue(try conn.tableExists(table), "missing table: \(table)")
            }
        }
    }

    func testInMemoryDatabaseBoots() throws {
        XCTAssertNoThrow(try DatabaseService(inMemory: true))
    }

    func testObservationsHaveFocusedColumn() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            let cols = try conn.columns(in: "activity_observations").map { $0.name }
            XCTAssertTrue(cols.contains("focused"), "activity_observations needs a focused column")
        }
    }

    func testPlannedBlocksHaveCalendarIdColumn() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            let cols = try conn.columns(in: "planned_blocks").map { $0.name }
            XCTAssertTrue(cols.contains("calendar_id"), "planned_blocks needs a calendar_id column for two-way sync")
        }
    }

    func testV5CreatesSeededCategoryRegistry() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            XCTAssertTrue(try conn.tableExists("category_registry"))
            XCTAssertFalse(try conn.tableExists("categories"), "legacy categories table should be gone")
            let count = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM category_registry") ?? 0
            XCTAssertEqual(count, 9, "9 default categories seeded")
            let deepwork = try String.fetchOne(conn, sql: "SELECT color FROM category_registry WHERE id = 'deepwork'")
            XCTAssertEqual(deepwork, "#2E5BFF")
        }
    }

    func testV5RenamesSegmentAndBlockColumns() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            let seg = try conn.columns(in: "activity_segments").map { $0.name }
            XCTAssertTrue(["cat", "sub", "title", "desc"].allSatisfy(seg.contains))
            XCTAssertFalse(seg.contains("category"))
            XCTAssertFalse(seg.contains("sub_category"))
            let blk = try conn.columns(in: "planned_blocks").map { $0.name }
            XCTAssertTrue(["cat", "sub", "desc"].allSatisfy(blk.contains))
            XCTAssertFalse(blk.contains("category"))
        }
    }

    func testV5CreatesUserEvents() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            XCTAssertTrue(try conn.tableExists("user_events"))
            let cols = try conn.columns(in: "user_events").map { $0.name }
            XCTAssertTrue(["cat", "sub", "title", "desc", "start_at", "end_at"].allSatisfy(cols.contains))
        }
    }

    func testV6ExtendsGoals() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            let cols = try conn.columns(in: "goals").map { $0.name }
            XCTAssertTrue(["why", "status", "cat", "updated_at"].allSatisfy(cols.contains), "goals missing v6 columns")
        }
    }

    func testV6CreatesJournal() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            XCTAssertTrue(try conn.tableExists("journal"))
            let cols = try conn.columns(in: "journal").map { $0.name }
            XCTAssertTrue(["id", "created_at", "kind", "goal_id", "cat", "title", "desc", "confidence", "evidence", "status"].allSatisfy(cols.contains))
        }
    }

    func testV6AddsGoalIdToUserEvents() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            let cols = try conn.columns(in: "user_events").map { $0.name }
            XCTAssertTrue(cols.contains("goal_id"), "user_events needs goal_id for check-ins")
        }
    }
}
