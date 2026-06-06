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
    var category: String?
    var goalId: String?
    var status: String                 // planned | done | cancelled | orphaned | …
    var createdByBogi: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case externalEventId = "external_event_id"
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case category
        case goalId = "goal_id"
        case status
        case createdByBogi = "created_by_bogi"
        case updatedAt = "updated_at"
    }
}
