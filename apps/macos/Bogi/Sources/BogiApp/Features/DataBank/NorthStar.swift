import Foundation
import GRDB

/// The user's single apex life-goal ("the one big thing your life is pointing at"), captured in
/// onboarding. It sits ABOVE the period-scoped `goals` and frames every judgement Togi makes:
/// the Judge weighs drift against it, the Coach answers against it, the planner leans toward it.
///
/// This is the ONE exception to Togi's local-only rule. The goal *text* syncs to Supabase so it
/// follows the user across devices and seeds the AI everywhere. It never carries captured screen
/// data — only the short string the user typed here. Singleton: `id` is always "primary".
struct NorthStarRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "north_star"
    static let singletonID = "primary"

    var id: String = NorthStarRecord.singletonID
    var text: String
    var why: String?
    var createdAt: Date
    var updatedAt: Date
    // Sync bookkeeping — local-only columns, never serialized into a request body.
    var remoteId: String?
    var dirty: Bool = true
    var syncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case why
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case remoteId = "remote_id"
        case dirty
        case syncedAt = "synced_at"
    }
}

/// Local CRUD over the singleton North Star. Mirrors `GoalsService` so the Coach and Judge can
/// read it the same way they read goals. Reads hit SQLite directly (the Judge runs every five
/// minutes, not a hot path). Backend sync is layered on separately so the app works fully offline.
final class NorthStarService {
    private let database: DatabaseService
    private let sync: NorthStarSync?

    init(database: DatabaseService, sync: NorthStarSync? = nil) {
        self.database = database
        self.sync = sync
    }

    /// The current North Star, or nil if onboarding hasn't set one yet.
    func current() -> NorthStarRecord? {
        try? database.dbQueue.read { db in
            try NorthStarRecord.fetchOne(db, key: NorthStarRecord.singletonID)
        }
    }

    /// Create or replace the North Star. Writes through to SQLite immediately and marks the row
    /// dirty so the sync layer pushes it to the backend on its next pass. `createdAt` is preserved
    /// across edits; `updatedAt` always bumps so last-write-wins works during sync.
    @discardableResult
    func save(text: String, why: String? = nil) -> NorthStarRecord {
        let now = Date()
        let existing = current()
        let record = NorthStarRecord(
            id: NorthStarRecord.singletonID,
            text: text,
            why: why,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            remoteId: existing?.remoteId,
            dirty: true,
            syncedAt: existing?.syncedAt
        )
        try? database.dbQueue.write { db in
            if existing == nil {
                try record.insert(db)
            } else {
                try record.update(db)
            }
        }
        if sync != nil {
            Task { await pushIfDirty() }
        }
        return record
    }

    /// Pull the North Star from the user's account and reconcile (last-write-wins, kept simple):
    /// seed a fresh device from the account, or push a local edit that hasn't synced yet. Safe to
    /// call when signed out or offline — it quietly no-ops.
    func refresh() async {
        guard sync != nil else { return }
        if let local = current() {
            if local.dirty { await pushIfDirty() }
        } else if let remote = await sync?.fetch() {
            seedFromRemote(text: remote.text, why: remote.why, remoteId: remote.id)
        }
    }

    /// Push the local row to the account if it has unsynced edits, then mark it clean.
    private func pushIfDirty() async {
        guard let sync, let local = current(), local.dirty,
              let remote = await sync.upsert(text: local.text, why: local.why) else { return }
        try? await database.dbQueue.write { db in
            guard var row = try NorthStarRecord.fetchOne(db, key: NorthStarRecord.singletonID) else { return }
            row.dirty = false
            row.remoteId = remote.id
            row.syncedAt = Date()
            try row.update(db)
        }
    }

    /// Write a remote North Star into the local store on a fresh device (already clean / synced).
    private func seedFromRemote(text: String, why: String?, remoteId: String) {
        let now = Date()
        let record = NorthStarRecord(
            id: NorthStarRecord.singletonID,
            text: text, why: why,
            createdAt: now, updatedAt: now,
            remoteId: remoteId, dirty: false, syncedAt: now
        )
        try? database.dbQueue.write { db in try record.insert(db) }
    }

    /// Remove the North Star (rare; e.g. the user resets onboarding).
    func clear() {
        try? database.dbQueue.write { db in
            _ = try NorthStarRecord.deleteOne(db, key: NorthStarRecord.singletonID)
        }
    }
}
