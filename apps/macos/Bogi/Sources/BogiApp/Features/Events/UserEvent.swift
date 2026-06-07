import Foundation
import GRDB

/// A real-world commitment the user mentioned in chat (meeting, gym, appointment). Lives in the
/// unified cat/sub/title/desc shape, separate from planned_blocks. A `cat='checkin'` event with a
/// `goalId` is a scheduled goal check-in (v6).
struct UserEvent: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "user_events"
    var id: String
    var title: String
    var desc: String?
    var cat: String?
    var sub: String?
    var startAt: Date
    var endAt: Date
    var createdAt: Date
    var goalId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, desc, cat, sub
        case startAt = "start_at"
        case endAt = "end_at"
        case createdAt = "created_at"
        case goalId = "goal_id"
    }
}
