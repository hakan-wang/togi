import Foundation
import GRDB

/// Typed accessor over the `settings` key/value table. Holds the privacy levers
/// (retention, pause, DND) and feature flags (embedding implementation).
final class SettingsStore {
    private let database: DatabaseService

    enum Key: String {
        case rawRetentionDays = "raw_retention_days"
        case paused
        case dnd
        case embedImpl = "embed_impl"
    }

    init(database: DatabaseService) {
        self.database = database
    }

    func string(_ key: Key) -> String? {
        try? database.dbQueue.read { db in
            try Setting.fetchOne(db, key: key.rawValue)?.value
        }
    }

    func set(_ key: Key, _ value: String?) {
        try? database.dbQueue.write { db in
            var s = Setting(key: key.rawValue, value: value)
            try s.save(db)
        }
    }

    func int(_ key: Key, default fallback: Int) -> Int {
        string(key).flatMap(Int.init) ?? fallback
    }

    func bool(_ key: Key, default fallback: Bool = false) -> Bool {
        guard let v = string(key) else { return fallback }
        return v == "1" || v.lowercased() == "true"
    }

    func setBool(_ key: Key, _ value: Bool) { set(key, value ? "1" : "0") }

    // Convenience for the most-used levers.
    var rawRetentionDays: Int { int(.rawRetentionDays, default: 14) }
    var isPaused: Bool { bool(.paused) }
}
