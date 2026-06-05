import Foundation
import GRDB

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
}
