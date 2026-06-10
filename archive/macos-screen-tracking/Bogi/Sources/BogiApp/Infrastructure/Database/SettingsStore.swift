import Foundation
import GRDB

/// Typed access to the key/value `settings` table.
final class SettingsStore {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    func string(_ key: String) -> String? {
        try? database.dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
        }
    }

    func set(_ key: String, _ value: String?) {
        try? database.dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO settings (key, value) VALUES (?, ?) " +
                     "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [key, value]
            )
        }
    }

    func int(_ key: String, default fallback: Int) -> Int {
        guard let s = string(key), let v = Int(s) else { return fallback }
        return v
    }

    func bool(_ key: String, default fallback: Bool) -> Bool {
        guard let s = string(key) else { return fallback }
        return s == "1" || s == "true"
    }

    func setBool(_ key: String, _ value: Bool) {
        set(key, value ? "1" : "0")
    }

    func stringArray(_ key: String) -> [String] {
        guard let s = string(key), let data = s.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return arr
    }

    func setStringArray(_ key: String, _ value: [String]) {
        guard let data = try? JSONEncoder().encode(value), let s = String(data: data, encoding: .utf8) else { return }
        set(key, s)
    }
}
