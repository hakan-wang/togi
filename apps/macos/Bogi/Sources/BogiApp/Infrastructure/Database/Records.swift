import Foundation
import GRDB

// GRDB record models for Bogi's core tables. Feature modules read/write these.
// Enums are stored as their raw string values to match the schema's CHECK-style
// text columns.

enum BlockSource: String, Codable { case apple, google, local }
enum BlockStatus: String, Codable { case planned, active, done, missed }
enum CaptureMethod: String, Codable { case ax }
enum NudgeOutcome: String, Codable { case dismissed, snoozed, heeded, escalated }
enum GoalPeriod: String, Codable { case month, quarter, year, custom }
enum CalendarProvider: String, Codable { case apple, google }

struct PlannedBlock: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "planned_blocks"
    var id: String
    var source: BlockSource
    var externalEventId: String?
    var title: String
    var startAt: Date
    var endAt: Date
    var category: String?
    var goalId: String?
    var status: BlockStatus
    var createdByBogi: Bool
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, source, title, category, status
        case externalEventId = "external_event_id"
        case startAt = "start_at"
        case endAt = "end_at"
        case goalId = "goal_id"
        case createdByBogi = "created_by_bogi"
        case updatedAt = "updated_at"
    }
}

struct ActivityObservation: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "activity_observations"
    var id: String
    var capturedAt: Date
    var activeApp: String?
    var activeAppBundleId: String?
    var activeWindowTitle: String?
    var text: String?
    var contentHash: String?
    var captureMethod: CaptureMethod
    var excluded: Bool

    enum CodingKeys: String, CodingKey {
        case id, text, excluded
        case capturedAt = "captured_at"
        case activeApp = "active_app"
        case activeAppBundleId = "active_app_bundle_id"
        case activeWindowTitle = "active_window_title"
        case contentHash = "content_hash"
        case captureMethod = "capture_method"
    }
}

struct ActivitySegment: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "activity_segments"
    var id: String
    var startAt: Date
    var endAt: Date
    var minutes: Double
    var plannedBlockId: String?
    var category: String?
    var subCategory: String?
    var subSub: String?
    var onTask: Bool?
    var confidence: Double?
    var judgedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, minutes, category, confidence
        case startAt = "start_at"
        case endAt = "end_at"
        case plannedBlockId = "planned_block_id"
        case subCategory = "sub_category"
        case subSub = "sub_sub"
        case onTask = "on_task"
        case judgedAt = "judged_at"
    }
}

struct Nudge: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "nudges"
    var id: String
    var segmentId: String?
    var plannedBlockId: String?
    var severity: Int
    var message: String
    var shownAt: Date?
    var outcome: NudgeOutcome?

    enum CodingKeys: String, CodingKey {
        case id, severity, message, outcome
        case segmentId = "segment_id"
        case plannedBlockId = "planned_block_id"
        case shownAt = "shown_at"
    }
}

struct Goal: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "goals"
    var id: String
    var title: String
    var period: GoalPeriod
    var target: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, period, target
        case createdAt = "created_at"
    }
}

struct Category: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "categories"
    var id: String
    var parentId: String?
    var name: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case parentId = "parent_id"
    }
}

struct CalendarAccount: Codable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "calendar_accounts"
    var id: String
    var provider: CalendarProvider
    var displayName: String?
    var status: String
    var lastSyncAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, provider, status
        case displayName = "display_name"
        case lastSyncAt = "last_sync_at"
    }
}

struct AccountRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "account"
    var supabaseUserId: String
    var paid: Bool
    var plan: String?
    var checkedAt: Date?

    enum CodingKeys: String, CodingKey {
        case paid, plan
        case supabaseUserId = "supabase_user_id"
        case checkedAt = "checked_at"
    }
}

struct Setting: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "settings"
    var key: String
    var value: String?
}
