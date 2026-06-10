import Foundation
import GRDB

/// Owns the local SQLite database — the only store of user data (local-first, no cloud).
final class DatabaseService {
    let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try SchemaMigrator.migrate(dbQueue)
    }

    init(inMemory: Bool) throws {
        dbQueue = try DatabaseQueue()
        try SchemaMigrator.migrate(dbQueue)
    }

    /// `~/Library/Application Support/Bogi/bogi.sqlite`, creating the directory if needed.
    static func defaultPath() -> String {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Bogi", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bogi.sqlite").path
    }
}
