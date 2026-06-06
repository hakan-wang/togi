import Foundation
import GRDB

/// Owns schema migrations. Phase 0 creates the regular tables. FTS5 + sqlite-vec virtual
/// tables are added in Phase 2 (they need the search stack), and are intentionally absent here.
enum SchemaMigrator {
    static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_core_tables") { db in
            // Referenced tables first (SQLite requires FK targets to exist at CREATE time).

            // Goals the coach references.
            try db.create(table: "goals") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("period", .text).notNull()               // month|quarter|year|custom
                t.column("target", .text)
                t.column("created_at", .datetime).notNull()
            }

            // Evolving category taxonomy.
            try db.create(table: "categories") { t in
                t.column("id", .text).primaryKey()
                t.column("parent_id", .text).references("categories", onDelete: .cascade)
                t.column("name", .text).notNull()
            }

            // Intention: calendar planned blocks (Apple / Google / local).
            try db.create(table: "planned_blocks") { t in
                t.column("id", .text).primaryKey()
                t.column("source", .text).notNull()              // apple | google | local
                t.column("external_event_id", .text)
                t.column("title", .text).notNull()
                t.column("start_at", .datetime).notNull()
                t.column("end_at", .datetime).notNull()
                t.column("category", .text)
                t.column("goal_id", .text).references("goals", onDelete: .setNull)
                t.column("status", .text).notNull()
                t.column("created_by_bogi", .boolean).notNull().defaults(to: false)
                t.column("updated_at", .datetime).notNull()
            }

            // Reality: raw 6s accessibility captures. Pruned after retention window.
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

            // Reality, judged: categorized 5-min segments (category → sub → sub-sub).
            try db.create(table: "activity_segments") { t in
                t.column("id", .text).primaryKey()
                t.column("start_at", .datetime).notNull()
                t.column("end_at", .datetime).notNull()
                t.column("minutes", .double).notNull()
                t.column("planned_block_id", .text).references("planned_blocks", onDelete: .setNull)
                t.column("category", .text)
                t.column("sub_category", .text)
                t.column("sub_sub", .text)                       // short concrete description
                t.column("on_task", .boolean)
                t.column("confidence", .double)
                t.column("judged_at", .datetime).notNull()
            }
            try db.create(indexOn: "activity_segments", columns: ["start_at"])

            // Nudges fired by the judge.
            try db.create(table: "nudges") { t in
                t.column("id", .text).primaryKey()
                t.column("segment_id", .text).references("activity_segments", onDelete: .setNull)
                t.column("planned_block_id", .text).references("planned_blocks", onDelete: .setNull)
                t.column("severity", .integer).notNull().defaults(to: 0)
                t.column("message", .text).notNull()
                t.column("shown_at", .datetime).notNull()
                t.column("outcome", .text)                       // dismissed|snoozed|heeded|escalated
            }

            // Rollups for the data-bank views.
            try db.create(table: "daily_summaries") { t in
                t.column("date", .text).primaryKey()             // yyyy-MM-dd
                t.column("json", .text).notNull()
                t.column("generated_at", .datetime).notNull()
            }
            try db.create(table: "weekly_summaries") { t in
                t.column("iso_week", .text).primaryKey()          // yyyy-Www
                t.column("json", .text).notNull()
                t.column("generated_at", .datetime).notNull()
            }
            try db.create(table: "monthly_summaries") { t in
                t.column("month", .text).primaryKey()             // yyyy-MM
                t.column("json", .text).notNull()
                t.column("generated_at", .datetime).notNull()
            }

            // Connected calendars (Google tokens live in Keychain, NOT here).
            try db.create(table: "calendar_accounts") { t in
                t.column("id", .text).primaryKey()
                t.column("provider", .text).notNull()             // apple|google
                t.column("display_name", .text)
                t.column("status", .text)
                t.column("last_sync_at", .datetime)
            }

            // Key/value settings (raw_retention_days, paused, dnd, embed_impl, …).
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text)
            }

            // Cached account/paid gate.
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
