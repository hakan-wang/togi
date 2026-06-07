import Foundation
import GRDB

/// CRUD over the category registry. Mirrors SegmentStore's DatabaseService-injection style.
final class CategoryRepository {
    private let database: DatabaseService
    init(database: DatabaseService) { self.database = database }

    func all() -> [CategoryEntry] {
        (try? database.dbQueue.read { db in
            try CategoryEntry.order(Column("sort_order")).fetchAll(db)
        }) ?? []
    }

    func exists(_ id: String) -> Bool {
        (try? database.dbQueue.read { db in
            try CategoryEntry.filter(key: id).fetchCount(db) > 0
        }) ?? false
    }

    func color(for id: String) -> String? {
        try? database.dbQueue.read { db in
            try CategoryEntry.fetchOne(db, key: id)?.color
        }
    }

    @discardableResult
    func add(name: String, color: String? = nil, description: String? = nil) -> CategoryEntry? {
        let id = Self.slug(name)
        guard !id.isEmpty, !exists(id) else { return nil }
        let now = Date()
        let entry = CategoryEntry(
            id: id, name: name,
            color: color ?? Self.fallbackColor(avoiding: Set(all().map { $0.color })),
            description: description, sortOrder: nextSortOrder(), createdAt: now, updatedAt: now)
        try? database.dbQueue.write { db in try entry.insert(db) }
        return exists(id) ? entry : nil
    }

    func rename(id: String, name: String) -> Bool { update(id) { $0.name = name } }
    func recolor(id: String, color: String) -> Bool { update(id) { $0.color = color } }

    func merge(from: String, into: String) -> Bool {
        guard from != into, exists(from), exists(into) else { return false }
        do {
            try database.dbQueue.write { db in
                for table in ["activity_segments", "planned_blocks", "user_events"] {
                    try db.execute(sql: "UPDATE \(table) SET cat = ? WHERE cat = ?", arguments: [into, from])
                }
                _ = try CategoryEntry.deleteOne(db, key: from)
            }
            return true
        } catch {
            return false
        }
    }

    private func update(_ id: String, _ mutate: (inout CategoryEntry) -> Void) -> Bool {
        ((try? database.dbQueue.write { db -> Bool in
            guard var row = try CategoryEntry.fetchOne(db, key: id) else { return false }
            mutate(&row); row.updatedAt = Date(); try row.update(db); return true
        }) ?? false)
    }

    private func nextSortOrder() -> Int { (all().map { $0.sortOrder }.max() ?? -1) + 1 }

    static func slug(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static func fallbackColor(avoiding used: Set<String>) -> String {
        let palette = ["#0EA5E9", "#A855F7", "#F97316", "#10B981", "#E11D48", "#6366F1", "#84CC16", "#06B6D4"]
        return palette.first { !used.contains($0) } ?? "#9CA3AF"
    }
}
