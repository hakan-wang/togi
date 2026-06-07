import Foundation
import GRDB

/// One dated, agent-authored note: a behavioural insight (Notice), a goal-progress entry, a
/// logged check-in, or a milestone. Episodic memory, distinct from the synthesized
/// `behaviour_profile` doc (Remember). Lives in the `journal` table (SchemaMigrator v6).
struct JournalEntry: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "journal"

    var id: String
    var createdAt: Date
    var kind: String            // insight | progress | checkin | milestone
    var goalId: String?
    var cat: String?
    var title: String
    var desc: String?
    var confidence: Double?
    var evidence: String?       // JSON string: [{start_at,end_at}]
    var status: String          // active | dismissed | superseded

    enum CodingKeys: String, CodingKey {
        case id, kind, cat, title, desc, confidence, evidence, status
        case createdAt = "created_at"
        case goalId = "goal_id"
    }
}
