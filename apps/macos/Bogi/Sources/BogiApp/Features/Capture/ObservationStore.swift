import Foundation
import GRDB

/// Persistence gateway for the raw `activity_observations` table. The capture
/// service writes 6-second snapshots here; the 5-minute judge reads them back
/// over a time range; the retention pruner deletes old rows.
///
/// Thin wrapper over the shared `DatabaseService` GRDB queue — it owns no schema
/// (that lives in `SchemaMigrator`) and reuses the `ActivityObservation` record.
struct ObservationStore {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    /// Inserts a single observation. Returns the inserted record (id assigned by
    /// the caller).
    @discardableResult
    func insert(_ observation: ActivityObservation) throws -> ActivityObservation {
        var record = observation
        try database.dbQueue.write { db in
            try record.insert(db)
        }
        return record
    }

    /// Most recent `limit` observations, newest first. Used by the judge to grab
    /// the latest window of activity and to recover the last persisted snapshot.
    func fetchLast(_ limit: Int) throws -> [ActivityObservation] {
        guard limit > 0 else { return [] }
        return try database.dbQueue.read { db in
            try ActivityObservation
                .order(Column("captured_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// The single most recent observation, or nil when the table is empty.
    func fetchLatest() throws -> ActivityObservation? {
        try fetchLast(1).first
    }

    /// All observations captured in `[from, to)`, oldest first. This is the
    /// judge's primary read: the previous ~5 minutes of raw activity.
    func fetchInRange(from: Date, to: Date) throws -> [ActivityObservation] {
        try database.dbQueue.read { db in
            try ActivityObservation
                .filter(Column("captured_at") >= from && Column("captured_at") < to)
                .order(Column("captured_at").asc)
                .fetchAll(db)
        }
    }

    /// Total row count — handy for tests and the capture indicator.
    func count() throws -> Int {
        try database.dbQueue.read { db in
            try ActivityObservation.fetchCount(db)
        }
    }
}
