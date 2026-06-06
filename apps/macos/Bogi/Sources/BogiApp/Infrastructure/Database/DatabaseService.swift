import Foundation
import GRDB

/// Owns the single GRDB `DatabaseQueue`. SQLite (via GRDB) is the only store of
/// user data in Bogi — there is no cloud sync. The vector index (`segment_vec`,
/// a sqlite-vec `vec0` virtual table) is created lazily by `VectorIndex` after
/// the sqlite-vec extension is loaded, not in the GRDB migrator.
final class DatabaseService {
    let dbQueue: DatabaseQueue

    init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: path, configuration: config)
        try SchemaMigrator.migrate(dbQueue)
    }

    init(inMemory: Bool) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(configuration: config)
        try SchemaMigrator.migrate(dbQueue)
    }
}
