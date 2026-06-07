import Foundation
import GRDB

/// CRUD over the category registry. Mirrors SegmentStore's DatabaseService-injection style.
final class CategoryRepository {
    private let database: DatabaseService
    init(database: DatabaseService) { self.database = database }

    func all() -> [CategoryEntry] {
        (try? database.dbQueue.read { db in
            try CategoryEntry.order(Column("sort_order")).fetchAll(db)
        }) ?? []
    }

    func exists(_ id: String) -> Bool {
        (try? database.dbQueue.read { db in
            try CategoryEntry.filter(key: id).fetchCount(db) > 0
        }) ?? false
    }

    func color(for id: String) -> String? {
        try? database.dbQueue.read { db in
            try CategoryEntry.fetchOne(db, key: id)?.color
        }
    }
}
