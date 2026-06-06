import XCTest
import GRDB
@testable import BogiApp

final class SchemaMigrationTests: XCTestCase {
    func testMigrationCreatesAllCoreTables() throws {
        let db = try DatabaseService(inMemory: true)

        let expected = [
            "planned_blocks", "activity_observations", "activity_segments", "nudges",
            "daily_summaries", "weekly_summaries", "monthly_summaries",
            "goals", "categories", "calendar_accounts", "settings", "account"
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
}