import Foundation
import GRDB

/// Raw 6s accessibility capture. Pruned after the retention window.
struct ActivityObservation: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "activity_observations"

    var id: String
    var capturedAt: Date
    var activeApp: String?
    var activeAppBundleId: String?
    var activeWindowTitle: String?
    var text: String?
    var contentHash: String?
    var captureMethod: String
    var excluded: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case capturedAt = "captured_at"
        case activeApp = "active_app"
        case activeAppBundleId = "active_app_bundle_id"
        case activeWindowTitle = "active_window_title"
        case text
        case contentHash = "content_hash"
        case captureMethod = "capture_method"
        case excluded
    }
}
