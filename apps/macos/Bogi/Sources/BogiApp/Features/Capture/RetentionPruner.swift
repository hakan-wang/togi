import Foundation
import GRDB

/// Deletes raw observations older than the retention window (privacy lever).
final class RetentionPruner {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    @discardableResult
    func prune(retentionDays: Int, now: Date) -> Int {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return (try? database.dbQueue.write { db in
            try ActivityObservation
                .filter(Column("captured_at") < cutoff)
                .deleteAll(db)
        }) ?? 0
    }
}
