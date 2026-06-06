import Foundation
import GRDB

/// Full v1 schema for Bogi (`create_core_tables`). Mirrors the schema in the
/// implementation plan: planning (intent), raw capture (reality), judged
/// segments, nudges, rollup summaries, taxonomy, goals, calendar accounts,
/// settings and the cached paid-account gate.
///
/// `segment_fts` (FTS5) is created here because FTS5 ships with SQLite.
/// `segment_vec` (sqlite-vec `vec0`) is NOT created here — it needs the
/// loadable sqlite-vec extension, so `VectorIndex` creates it at runtime.
enum SchemaMigrator {
    static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("create_core_tables") { db in
            // INTENT — calendar-planned blocks.
            try db.create(table: "planned_blocks") { t in
                t.column("id", .text).primaryKey()
                t.column("source", .text).notNull()              // apple | google | local
                t.column("external_event_id", .text)
                t.column("title", .text).notNull()
                t.column("start_at", .datetime).notNull()
                t.column("end_at", .datetime).notNull()
                t.column("category", .text)
                t.column("goal_id", .text).references("goals", onDelete: .setNull)
                t.column("status", .text).notNull()              // planned | active | done | missed
                t.column("created_by_bogi", .boolean).notNull().defaults(to: false)
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(indexOn: "planned_blocks", columns: ["start_at"])

            // REALITY (raw) — 6s accessibility captures, pruned after retention.
            try db.create(table: "activity_observations") { t in
                t.column("id", .text).primaryKey()
                t.column("captured_at", .datetime).notNull()
                t.column("active_app", .text)
                t.column("active_app_bundle_id", .text)
                t.column("active_window_title", .text)
                t.column("text", .text)
                t.column("content_hash", .text)
                t.column("capture_method", .text).notNull().defaults(to: "ax")
                t.column("excluded", .boolean).notNull().defaults(to: false)
            }
            try db.create(indexOn: "activity_observations", columns: ["captured_at"])

            // REALITY (judged) — the categorized data bank, durable.
            try db.create(table: "activity_segments") { t in
                t.column("id", .text).primaryKey()
                t.column("start_at", .datetime).notNull()
                t.column("end_at", .datetime).notNull()
                t.column("minutes", .double).notNull().defaults(to: 0)
                t.column("planned_block_id", .text).references("planned_blocks", onDelete: .setNull)
                t.column("category", .text)
                t.column("sub_category", .text)
                t.column("sub_sub", .text)                       // short concrete description
                t.column("on_task", .boolean)
                t.column("confidence", .double)
                t.column("judged_at", .datetime).notNull()
            }
            try db.create(indexOn: "activity_segments", columns: ["start_at"])

            // Keyword search over segment descriptions (semantic search lives in
            // the sqlite-vec `segment_vec` table created by VectorIndex).
            try db.create(virtualTable: "segment_fts", using: FTS5()) { t in
                t.synchronize(withTable: "activity_segments")
                t.column("sub_sub")
                t.column("category")
                t.column("sub_category")
            }

            // In-the-moment nudges surfaced by the mascot.
            try db.create(table: "nudges") { t in
                t.column("id", .text).primaryKey()
                t.column("segment_id", .text).references("activity_segments", onDelete: .setNull)
                t.column("planned_block_id", .text).references("planned_blocks", onDelete: .setNull)
                t.column("severity", .integer).notNull().defaults(to: 0)
                t.column("message", .text).notNull()
                t.column("shown_at", .datetime)
                t.column("outcome", .text)                       // dismissed | snoozed | heeded | escalated
            }

            // Rollups for the day/week/month/year insight views.
            try db.create(table: "daily_summaries") { t in
                t.column("date", .text).primaryKey()             // yyyy-MM-dd
                t.column("json", .text).notNull()
                t.column("generated_at", .datetime).notNull()
            }
            try db.create(table: "weekly_summaries") { t in
                t.column("iso_week", .text).primaryKey()         // yyyy-Www
                t.column("json", .text).notNull()
                t.column("generated_at", .datetime).notNull()
            }
            try db.create(table: "monthly_summaries") { t in
                t.column("month", .text).primaryKey()            // yyyy-MM
                t.column("json", .text).notNull()
                t.column("generated_at", .datetime).notNull()
            }

            // Goals + evolving category taxonomy.
            try db.create(table: "goals") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("period", .text).notNull()              // month | quarter | year | custom
                t.column("target", .text)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(table: "categories") { t in
                t.column("id", .text).primaryKey()
                t.column("parent_id", .text).references("categories", onDelete: .cascade)
                t.column("name", .text).notNull()
            }

            // Calendar accounts (google tokens live in the Keychain, NOT here).
            try db.create(table: "calendar_accounts") { t in
                t.column("id", .text).primaryKey()
                t.column("provider", .text).notNull()            // apple | google
                t.column("display_name", .text)
                t.column("status", .text).notNull()
                t.column("last_sync_at", .datetime)
            }

            // Key/value settings: raw_retention_days, paused, dnd, embed_impl, ...
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }

            // Cached paid-account gate (re-checked against the backend on launch).
            try db.create(table: "account") { t in
                t.column("supabase_user_id", .text).primaryKey()
                t.column("paid", .boolean).notNull().defaults(to: false)
                t.column("plan", .text)
                t.column("checked_at", .datetime)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
