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
}
