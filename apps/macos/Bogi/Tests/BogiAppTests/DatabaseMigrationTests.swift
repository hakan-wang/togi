import XCTest
import GRDB
@testable import BogiApp

final class DatabaseMigrationTests: XCTestCase {
    func testMigratorCreatesCoreTables() throws {
        let dbQueue = try DatabaseQueue()
        try SchemaMigrator.migrate(dbQueue)

        try dbQueue.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            XCTAssertTrue(tables.contains("planned_blocks"))
            XCTAssertTrue(tables.contains("reality_logs"))
            XCTAssertTrue(tables.contains("activity_observations"))
            XCTAssertTrue(tables.contains("sync_queue"))
        }
    }
}
