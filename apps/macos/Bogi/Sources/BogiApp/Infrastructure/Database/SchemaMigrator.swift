import Foundation
import GRDB

enum SchemaMigrator {
    static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("create_core_tables") { db in
            try db.create(table: "planned_blocks") { table in
                table.column("id", .text).primaryKey()
                table.column("source", .text).notNull()
                table.column("external_event_id", .text)
                table.column("title", .text).notNull()
                table.column("start_at", .datetime).notNull()
                table.column("end_at", .datetime).notNull()
                table.column("category", .text)
                table.column("goal_id", .text)
                table.column("status", .text).notNull()
                table.column("created_by_bogi", .boolean).notNull().defaults(to: false)
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "reality_logs") { table in
                table.column("id", .text).primaryKey()
                table.column("block_id", .text).references("planned_blocks", onDelete: .setNull)
                table.column("start_at", .datetime).notNull()
                table.column("end_at", .datetime).notNull()
                table.column("category", .text)
                table.column("user_text", .text).notNull()
                table.column("generated_summary", .text)
                table.column("confidence", .double)
                table.column("source", .text).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "activity_observations") { table in
                table.column("id", .text).primaryKey()
                table.column("block_id", .text).references("planned_blocks", onDelete: .setNull)
                table.column("captured_at", .datetime).notNull()
                table.column("active_app", .text)
                table.column("active_window_title", .text)
                table.column("local_text_summary", .text)
                table.column("category_guess", .text)
                table.column("confidence", .double)
                table.column("capture_method", .text).notNull()
            }

            try db.create(table: "sync_queue") { table in
                table.column("id", .text).primaryKey()
                table.column("entity_type", .text).notNull()
                table.column("entity_id", .text).notNull()
                table.column("operation", .text).notNull()
                table.column("payload_json", .text).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("attempt_count", .integer).notNull().defaults(to: 0)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
