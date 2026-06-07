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

        // Phase 2 — search infrastructure: FTS5 keyword + BLOB vector store.
        migrator.registerMigration("v2_search") { db in
            try db.execute(sql: "CREATE VIRTUAL TABLE segment_fts USING fts5(segment_id UNINDEXED, description)")
            try db.create(table: "segment_embeddings") { t in
                t.column("segment_id", .text).primaryKey()
                t.column("vector", .blob).notNull()
                t.column("dim", .integer).notNull()
            }
        }


        // Phase A — explicit focus marker on raw observations (default true: we only
        // capture the focused window today; this is forward-compatible with background capture).
        migrator.registerMigration("v3_observation_focused") { db in
            try db.alter(table: "activity_observations") { t in
                t.add(column: "focused", .boolean).notNull().defaults(to: true)
            }
        }

        // Two-way Google sync — remember which Google calendar a block lives in so Bogi-created
        // blocks can be updated (and matched on re-sync) on the right calendar.
        migrator.registerMigration("v4_planned_block_calendar_id") { db in
            try db.alter(table: "planned_blocks") { t in
                t.add(column: "calendar_id", .text)
            }
        }

        // Phase: North Star — the user's single apex life-goal, stated in onboarding. Sits ABOVE
        // `goals`. UNLIKE the rest of the data bank (strictly local), this row SYNCS to Supabase:
        // it holds only user-stated goal text, never captured screen data. Singleton per device —
        // the service always upserts the fixed id "primary".
        migrator.registerMigration("v5_north_star") { db in
            try db.create(table: "north_star") { t in
                t.column("id", .text).primaryKey()                 // always "primary"
                t.column("text", .text).notNull()
                t.column("why", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                // Sync bookkeeping — local-only columns, never sent in the request body.
                t.column("remote_id", .text)
                t.column("dirty", .boolean).notNull().defaults(to: true)
                t.column("synced_at", .datetime)
            }
        }

        migrator.registerMigration("v5_tailored_data_model") { db in
            // Replace the unused legacy taxonomy with a flat, colored, agent-curated registry.
            try db.drop(table: "categories")
            try db.create(table: "category_registry") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("color", .text).notNull()
                t.column("description", .text)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            let seed: [(id: String, name: String, color: String, description: String)] = [
                (id: "deepwork", name: "Deep work", color: "#2E5BFF", description: "focused, cognitively heavy work"),
                (id: "creative", name: "Creative", color: "#8B5CF6", description: "making things (design, writing, video)"),
                (id: "admin", name: "Admin", color: "#64748B", description: "email, scheduling, paperwork"),
                (id: "health", name: "Health", color: "#22C55E", description: "exercise, meals, rest"),
                (id: "social", name: "Social", color: "#EC4899", description: "time with people, calls"),
                (id: "errands", name: "Errands", color: "#F59E0B", description: "out and about, shopping"),
                (id: "leisure", name: "Leisure", color: "#14B8A6", description: "intentional downtime (games, shows)"),
                (id: "scroll", name: "Scroll", color: "#EF4444", description: "passive feed consumption"),
                (id: "personal", name: "Personal", color: "#9CA3AF", description: "catch-all, misc personal"),
            ]
            for (i, c) in seed.enumerated() {
                try db.execute(sql: """
                    INSERT INTO category_registry (id, name, color, description, sort_order, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'))
                    """, arguments: [c.id, c.name, c.color, c.description, i])
            }

            // Reality, judged: rename to the unified field shape.
            try db.alter(table: "activity_segments") { t in
                t.rename(column: "category", to: "cat")
                t.rename(column: "sub_category", to: "sub")
                t.rename(column: "sub_sub", to: "title")
                t.add(column: "desc", .text)
            }
            // Old free-text values are not registry ids; null them (no invented mappings).
            try db.execute(sql: "UPDATE activity_segments SET cat = NULL")

            // Plan: rename + extend (title already exists).
            try db.alter(table: "planned_blocks") { t in
                t.rename(column: "category", to: "cat")
                t.add(column: "sub", .text)
                t.add(column: "desc", .text)
            }
            try db.execute(sql: "UPDATE planned_blocks SET cat = NULL")

            // Conversation: custom events in the unified shape.
            try db.create(table: "user_events") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("desc", .text)
                t.column("cat", .text)
                t.column("sub", .text)
                t.column("start_at", .datetime).notNull()
                t.column("end_at", .datetime).notNull()
                t.column("created_at", .datetime).notNull()
            }
            try db.create(indexOn: "user_events", columns: ["start_at"])
        }

        migrator.registerMigration("v6_goals_and_journal") { db in
            // Granular goals gain motivation, lifecycle, optional category, and a touch timestamp.
            try db.alter(table: "goals") { t in
                t.add(column: "why", .text)
                t.add(column: "status", .text).notNull().defaults(to: "active")  // active|done|abandoned
                t.add(column: "cat", .text)
                t.add(column: "updated_at", .datetime)
            }
            try db.execute(sql: "UPDATE goals SET updated_at = created_at WHERE updated_at IS NULL")

            // Episodic memory: dated, evidenced agent notes. kind splits the three views
            // (insight cards / goal journey / check-in outcomes). Evidence is JSON time-ranges.
            try db.create(table: "journal") { t in
                t.column("id", .text).primaryKey()
                t.column("created_at", .datetime).notNull()
                t.column("kind", .text).notNull()                 // insight|progress|checkin|milestone
                t.column("goal_id", .text).references("goals", onDelete: .setNull)
                t.column("cat", .text)
                t.column("title", .text).notNull()
                t.column("desc", .text)
                t.column("confidence", .double)
                t.column("evidence", .text)                       // JSON: [{start_at,end_at}]
                t.column("status", .text).notNull().defaults(to: "active")  // active|dismissed|superseded
            }
            try db.create(indexOn: "journal", columns: ["created_at"])
            try db.create(indexOn: "journal", columns: ["goal_id"])
            try db.create(indexOn: "journal", columns: ["kind"])

            // A scheduled check-in is a user_events row (cat='checkin') attached to a goal.
            try db.alter(table: "user_events") { t in
                t.add(column: "goal_id", .text).references("goals", onDelete: .setNull)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
