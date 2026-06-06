import XCTest
import GRDB
@testable import BogiApp

final class SchemaMigrationTests: XCTestCase {
    func testInMemoryDatabaseBoots() throws {
        XCTAssertNoThrow(try DatabaseService(inMemory: true))
    }

    func testMigrationCreatesAllCoreTables() throws {
        let service = try DatabaseService(inMemory: true)
        let expected = [
            "planned_blocks", "activity_observations", "activity_segments",
            "segment_fts", "nudges", "daily_summaries", "weekly_summaries",
            "monthly_summaries", "goals", "categories", "calendar_accounts",
            "settings", "account",
        ]
        try service.dbQueue.read { db in
            for table in expected {
                XCTAssertTrue(try db.tableExists(table), "missing table: \(table)")
            }
        }
    }

    func testPlannedBlockRoundTrips() throws {
        let service = try DatabaseService(inMemory: true)
        var block = PlannedBlock(
            id: "b1", source: .local, externalEventId: nil, title: "Edit videos",
            startAt: Date(timeIntervalSince1970: 1_000), endAt: Date(timeIntervalSince1970: 4_600),
            category: "work/content", goalId: nil, status: .planned,
            createdByBogi: true, updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        try service.dbQueue.write { db in try block.insert(db) }
        let fetched = try service.dbQueue.read { db in try PlannedBlock.fetchOne(db, key: "b1") }
        XCTAssertEqual(fetched?.title, "Edit videos")
        XCTAssertEqual(fetched?.status, .planned)
        XCTAssertEqual(fetched?.createdByBogi, true)
    }

    func testForeignKeysEnabled() throws {
        let service = try DatabaseService(inMemory: true)
        let enabled = try service.dbQueue.read { db in
            try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") ?? false
        }
        XCTAssertTrue(enabled)
    }
}
