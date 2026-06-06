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
}
