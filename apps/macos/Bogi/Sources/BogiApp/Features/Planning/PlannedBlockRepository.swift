import Foundation
import GRDB

final class PlannedBlockRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func save(_ block: PlannedBlock) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO planned_blocks
                (id, source, external_event_id, title, start_at, end_at, category, goal_id, status, created_by_bogi, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    block.id, block.source, block.externalEventID, block.title,
                    block.startAt, block.endAt, block.category, block.goalID,
                    block.status, block.createdByBogi, block.updatedAt
                ]
            )
        }
    }

    func fetch(id: String) throws -> PlannedBlock? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM planned_blocks WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return PlannedBlock(
                id: row["id"],
                source: row["source"],
                externalEventID: row["external_event_id"],
                title: row["title"],
                startAt: row["start_at"],
                endAt: row["end_at"],
                category: row["category"],
                goalID: row["goal_id"],
                status: row["status"],
                createdByBogi: row["created_by_bogi"],
                updatedAt: row["updated_at"]
            )
        }
    }
}
