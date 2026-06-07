import Foundation
import GRDB

/// Read/write over the episodic journal. Mirrors the DatabaseService-injection style of the
/// other repositories.
final class JournalRepository {
    private let database: DatabaseService
    init(database: DatabaseService) { self.database = database }

    func insert(_ entry: JournalEntry) {
        try? database.dbQueue.write { db in try entry.insert(db) }
    }

    /// Newest first. Filter by kind, goal, and/or status; cap with limit.
    func entries(kind: String? = nil, goalId: String? = nil,
                 status: String? = nil, limit: Int? = nil) -> [JournalEntry] {
        (try? database.dbQueue.read { db in
            var request = JournalEntry.all()
            if let kind { request = request.filter(Column("kind") == kind) }
            if let goalId { request = request.filter(Column("goal_id") == goalId) }
            if let status { request = request.filter(Column("status") == status) }
            request = request.order(Column("created_at").desc)
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        }) ?? []
    }

    func setStatus(id: String, status: String) {
        try? database.dbQueue.write { db in
            guard var e = try JournalEntry.fetchOne(db, key: id) else { return }
            e.status = status
            try e.update(db)
        }
    }
}
