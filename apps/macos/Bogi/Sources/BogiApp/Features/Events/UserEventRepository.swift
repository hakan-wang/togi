import Foundation
import GRDB

final class UserEventRepository {
    private let database: DatabaseService
    init(database: DatabaseService) { self.database = database }

    func insert(_ event: UserEvent) {
        try? database.dbQueue.write { db in try event.insert(db) }
    }

    /// Events whose start falls in [start, end] — for summaries/list_events.
    func events(inRange start: Date, _ end: Date) -> [UserEvent] {
        (try? database.dbQueue.read { db in
            try UserEvent
                .filter(Column("start_at") >= start && Column("start_at") <= end)
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }

    /// Events active at `date` (start <= date < end) — context for the judge tick.
    func events(overlapping date: Date) -> [UserEvent] {
        (try? database.dbQueue.read { db in
            try UserEvent
                .filter(Column("start_at") <= date && Column("end_at") > date)
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }

    /// Events attached to a goal (its scheduled check-ins), soonest first.
    func events(forGoal goalId: String) -> [UserEvent] {
        (try? database.dbQueue.read { db in
            try UserEvent
                .filter(Column("goal_id") == goalId)
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }

    /// Goal check-ins that are due as of `date`: any goal-linked event whose start time has
    /// arrived. No upper bound, so a check-in the 5-minute tick stepped past still fires next tick.
    func dueCheckIns(asOf date: Date) -> [UserEvent] {
        (try? database.dbQueue.read { db in
            try UserEvent
                .filter(Column("goal_id") != nil && Column("start_at") <= date)
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }

    func delete(id: String) {
        try? database.dbQueue.write { db in _ = try UserEvent.deleteOne(db, key: id) }
    }
}
