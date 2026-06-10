import Foundation
import GRDB

/// Persists raw activity observations locally.
final class ObservationStore {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    func insert(_ observation: ActivityObservation) {
        try? database.dbQueue.write { db in
            try observation.insert(db)
        }
    }

    func count() -> Int {
        (try? database.dbQueue.read { db in
            try ActivityObservation.fetchCount(db)
        }) ?? 0
    }

    /// Observations captured within the last `seconds`, oldest first. Feeds the 5-min judge.
    func recent(within seconds: TimeInterval, now: Date = Date()) -> [ActivityObservation] {
        let cutoff = now.addingTimeInterval(-seconds)
        return (try? database.dbQueue.read { db in
            try ActivityObservation
                .filter(Column("captured_at") >= cutoff)
                .order(Column("captured_at"))
                .fetchAll(db)
        }) ?? []
    }
}
