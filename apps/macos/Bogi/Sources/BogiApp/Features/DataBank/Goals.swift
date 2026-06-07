import Foundation
import GRDB

/// A goal the coach references when judging plan-vs-reality. Persisted to the `goals` table
/// (created by SchemaMigrator; extended in v6 with lifecycle + motivation).
struct GoalRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "goals"

    var id: String
    var title: String
    var period: String          // month | quarter | year | custom
    var target: String?
    var createdAt: Date
    var why: String?
    var status: String          // active | done | abandoned
    var cat: String?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, period, target, why, status, cat
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// CRUD over goals.
final class GoalsService {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    /// Create and persist a new goal (defaults to active).
    @discardableResult
    func add(title: String, period: String, target: String? = nil,
             why: String? = nil, cat: String? = nil) -> GoalRecord {
        let now = Date()
        let goal = GoalRecord(
            id: UUID().uuidString, title: title, period: period, target: target,
            createdAt: now, why: why, status: "active", cat: cat, updatedAt: now)
        try? database.dbQueue.write { db in try goal.insert(db) }
        return goal
    }

    /// Goals oldest first, optionally filtered by status.
    func all(status: String? = nil) -> [GoalRecord] {
        (try? database.dbQueue.read { db in
            var request = GoalRecord.order(Column("created_at"))
            if let status { request = request.filter(Column("status") == status) }
            return try request.fetchAll(db)
        }) ?? []
    }

    /// Mutate any subset of mutable fields; bumps updated_at. Returns false if the id is unknown.
    @discardableResult
    func update(id: String, status: String? = nil, why: String? = nil,
                target: String? = nil, cat: String? = nil) -> Bool {
        ((try? database.dbQueue.write { db -> Bool in
            guard var g = try GoalRecord.fetchOne(db, key: id) else { return false }
            if let status { g.status = status }
            if let why { g.why = why }
            if let target { g.target = target }
            if let cat { g.cat = cat }
            g.updatedAt = Date()
            try g.update(db)
            return true
        }) ?? false)
    }

    func delete(id: String) {
        try? database.dbQueue.write { db in _ = try GoalRecord.deleteOne(db, key: id) }
    }
}
