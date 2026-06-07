import Foundation
import GRDB

/// One row of the agent-curated category registry (the only level with a color).
struct CategoryEntry: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "category_registry"
    var id: String
    var name: String
    var color: String
    var description: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, color, description
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
