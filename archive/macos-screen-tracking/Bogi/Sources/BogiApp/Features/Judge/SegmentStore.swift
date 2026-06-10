import Foundation
import GRDB

/// Persists judged activity segments locally.
final class SegmentStore {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    func insert(_ segment: ActivitySegment) {
        try? database.dbQueue.write { db in
            try segment.insert(db)
        }
    }

    func count() -> Int {
        (try? database.dbQueue.read { db in
            try ActivitySegment.fetchCount(db)
        }) ?? 0
    }

    /// Sum of off-task minutes from judged segments within the last `seconds`. Feeds nudge urgency.
    func offTaskMinutes(within seconds: TimeInterval, now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-seconds)
        let total = (try? database.dbQueue.read { db in
            try ActivitySegment
                .filter(Column("start_at") >= cutoff && Column("on_task") == false)
                .fetchAll(db)
                .reduce(0.0) { $0 + $1.minutes }
        }) ?? 0
        return Int(total.rounded())
    }
}
