import Foundation
import GRDB

/// A time-attributed slice of activity produced by the 5-minute judge. Persisted to the
/// `activity_segments` table (created by SchemaMigrator).
struct ActivitySegment: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "activity_segments"

    var id: String
    var startAt: Date
    var endAt: Date
    var minutes: Double
    var plannedBlockId: String?
    var cat: String?
    var sub: String?
    var title: String?
    var desc: String?
    var onTask: Bool?
    var confidence: Double?
    var judgedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case startAt = "start_at"
        case endAt = "end_at"
        case minutes
        case plannedBlockId = "planned_block_id"
        case cat
        case sub
        case title
        case desc
        case onTask = "on_task"
        case confidence
        case judgedAt = "judged_at"
    }
}
