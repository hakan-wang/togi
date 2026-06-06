import Foundation
import GRDB

/// CRUD over the `goals` table. Goals are the standing intentions the coach
/// grounds its answers in ("did I hit my monthly goal, and if not why?"). They
/// are small and user-authored: a title, a period (month/quarter/year/custom)
/// and a free-text target.
///
/// The store is intentionally thin — it owns no state beyond the database
/// handle, so it is cheap to construct wherever goals are needed (the data-bank
/// views, the coach context builder, settings).
final class GoalsService {
    private let database: DatabaseService
    /// Injectable clock so `created_at` is deterministic in tests.
    private let now: () -> Date

    init(database: DatabaseService, now: @escaping () -> Date = Date.init) {
        self.database = database
        self.now = now
    }

    /// Creates and persists a new goal, returning the stored record. The id is a
    /// fresh UUID and `created_at` is stamped from the injected clock.
    @discardableResult
    func create(title: String, period: GoalPeriod, target: String? = nil) throws -> Goal {
        var goal = Goal(
            id: UUID().uuidString,
            title: title,
            period: period,
            target: target,
            createdAt: now()
        )
        try database.dbQueue.write { db in
            try goal.insert(db)
        }
        return goal
    }

    /// Upserts an existing goal (used when the user edits title/target/period).
    func update(_ goal: Goal) throws {
        var goal = goal
        try database.dbQueue.write { db in
            try goal.update(db)
        }
    }

    /// Saves a goal whether or not it already exists (insert-or-update).
    func save(_ goal: Goal) throws {
        var goal = goal
        try database.dbQueue.write { db in
            try goal.save(db)
        }
    }

    func delete(id: String) throws {
        _ = try database.dbQueue.write { db in
            try Goal.deleteOne(db, key: id)
        }
    }

    func goal(id: String) throws -> Goal? {
        try database.dbQueue.read { db in
            try Goal.fetchOne(db, key: id)
        }
    }

    /// All goals, newest first.
    func all() throws -> [Goal] {
        try database.dbQueue.read { db in
            try Goal
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    /// Goals scoped to a single period (e.g. just the monthly goals).
    func goals(period: GoalPeriod) throws -> [Goal] {
        try database.dbQueue.read { db in
            try Goal
                .filter(Column("period") == period.rawValue)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }
}
