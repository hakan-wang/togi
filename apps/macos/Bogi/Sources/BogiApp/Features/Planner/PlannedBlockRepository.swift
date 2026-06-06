import Foundation
import GRDB

/// Persists planned blocks locally. Local SQLite is the canonical store of intent.
final class PlannedBlockRepository {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    /// Insert or replace a block by primary key.
    func upsert(_ block: PlannedBlock) {
        try? database.dbQueue.write { db in
            try block.save(db)
        }
    }

    func all() -> [PlannedBlock] {
        (try? database.dbQueue.read { db in
            try PlannedBlock
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }

    /// All blocks overlapping the calendar day containing `date` (local time zone).
    func blocks(onDay date: Date) -> [PlannedBlock] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return (try? database.dbQueue.read { db in
            // Overlap: starts before the day ends AND ends after the day starts.
            try PlannedBlock
                .filter(Column("start_at") < dayEnd && Column("end_at") > dayStart)
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }

    /// The block currently active at `date` (start <= date < end). Earliest start wins on ties.
    func activeBlock(at date: Date) -> PlannedBlock? {
        try? database.dbQueue.read { db in
            try PlannedBlock
                .filter(Column("start_at") <= date && Column("end_at") > date)
                .order(Column("start_at"))
                .fetchOne(db)
        } ?? nil
    }

    func delete(id: String) {
        _ = try? database.dbQueue.write { db in
            try PlannedBlock.deleteOne(db, key: id)
        }
    }

    func count() -> Int {
        (try? database.dbQueue.read { db in
            try PlannedBlock.fetchCount(db)
        }) ?? 0
    }

    /// Fetch a single block by primary key.
    func block(id: String) -> PlannedBlock? {
        try? database.dbQueue.read { db in
            try PlannedBlock.fetchOne(db, key: id)
        } ?? nil
    }

    /// Fetch a single block by its (source, external_event_id) pair. Used during reconciliation.
    func block(source: String, externalEventId: String) -> PlannedBlock? {
        try? database.dbQueue.read { db in
            try PlannedBlock
                .filter(Column("source") == source && Column("external_event_id") == externalEventId)
                .fetchOne(db)
        } ?? nil
    }

    /// All blocks for a given source. Used to detect events that disappeared upstream.
    func blocks(source: String) -> [PlannedBlock] {
        (try? database.dbQueue.read { db in
            try PlannedBlock
                .filter(Column("source") == source)
                .fetchAll(db)
        }) ?? []
    }
}
