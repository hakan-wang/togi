import Foundation
import Combine

/// Shared, app-wide dependency container. Built once at launch (see `AppDelegate`)
/// and injected into SwiftUI scenes. Feature modules attach their services here
/// during integration; the foundation only guarantees the database + settings.
@MainActor
final class AppEnvironment: ObservableObject {
    let database: DatabaseService
    let settings: SettingsStore

    init(database: DatabaseService) {
        self.database = database
        self.settings = SettingsStore(database: database)
    }

    /// Production environment backed by an on-disk SQLite database in
    /// Application Support. Falls back to an in-memory database if the support
    /// directory cannot be created (the app still launches; capture is degraded).
    static func live() -> AppEnvironment {
        do {
            let url = try AppPaths.databaseURL()
            let database = try DatabaseService(path: url.path)
            return AppEnvironment(database: database)
        } catch {
            NSLog("Bogi: falling back to in-memory database: \(error)")
            // Force-try is acceptable here: an in-memory DB creation failing
            // would indicate GRDB itself is broken, which is unrecoverable.
            let database = try! DatabaseService(inMemory: true)
            return AppEnvironment(database: database)
        }
    }
}

enum AppPaths {
    static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("Bogi", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func databaseURL() throws -> URL {
        try supportDirectory().appendingPathComponent("bogi.sqlite")
    }
}
