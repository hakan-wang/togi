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
}
