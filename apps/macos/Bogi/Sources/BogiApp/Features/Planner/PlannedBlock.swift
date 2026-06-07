import Foundation
import GRDB

/// Intention: a calendar planned block (Apple / Google / local). Local SQLite is canonical.
/// Bogi may update its OWN blocks (created_by_bogi == true) but must never silently delete
/// user-created events.
struct PlannedBlock: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "planned_blocks"

    var id: String
    var source: String                 // apple | google | local
    var externalEventId: String?
    var title: String
    var startAt: Date
    var endAt: Date
    var cat: String?
    var sub: String?
    var desc: String?
    var goalId: String?
    var status: String                 // planned | done | cancelled | orphaned | …
    var createdByBogi: Bool
    var updatedAt: Date
    /// Which Google calendar this block lives in (e.g. "primary"), so Bogi can update/delete the
    /// matching Google event later. nil for local-only blocks and Apple events. Declared last with
    /// a default so existing initializers keep working.
    var calendarId: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case externalEventId = "external_event_id"
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case cat
        case sub
        case desc
        case goalId = "goal_id"
        case status
        case createdByBogi = "created_by_bogi"
        case updatedAt = "updated_at"
        case calendarId = "calendar_id"
    }
}
