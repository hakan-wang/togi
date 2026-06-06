import XCTest
import GRDB
@testable import BogiApp

final class SchemaMigrationTests: XCTestCase {
    func testMigrationCreatesAllCoreTables() throws {
        let db = try DatabaseService(inMemory: true)

        let expected = [
            "planned_blocks", "activity_observations", "activity_segments", "nudges",
            "daily_summaries", "weekly_summaries", "monthly_summaries",
            "goals", "categories", "calendar_accounts", "settings", "account",
            "north_star"
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
}
