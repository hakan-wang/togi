import Foundation
import GRDB

/// A goal the coach references when judging plan-vs-reality. Persisted to the `goals` table
/// (created by SchemaMigrator).
struct GoalRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "goals"

    var id: String
    var title: String
    var period: String          // month | quarter | year | custom
    var target: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case period
        case target
        case createdAt = "created_at"
    }
}

/// CRUD over goals.
final class GoalsService {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    /// Create and persist a new goal.
    @discardableResult
    func add(title: String, period: String, target: String? = nil) -> GoalRecord {
        let goal = GoalRecord(
            id: UUID().uuidString,
            title: title,
            period: period,
            target: target,
            createdAt: Date()
        )
        try? database.dbQueue.write { db in
            try goal.insert(db)
        }
        return goal
    }

    /// All goals, oldest first.
    func all() -> [GoalRecord] {
        (try? database.dbQueue.read { db in
            try GoalRecord
                .order(Column("created_at"))
                .fetchAll(db)
        }) ?? []
    }

    func delete(id: String) {
        try? database.dbQueue.write { db in
            _ = try GoalRecord.deleteOne(db, key: id)
        }
    }
}
