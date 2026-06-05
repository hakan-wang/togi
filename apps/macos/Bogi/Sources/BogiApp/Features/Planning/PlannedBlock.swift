import Foundation

struct PlannedBlock: Codable, Equatable, Identifiable {
    let id: String
    var source: String
    var externalEventID: String?
    var title: String
    var startAt: Date
    var endAt: Date
    var category: String?
    var goalID: String?
    var status: String
    var createdByBogi: Bool
    var updatedAt: Date
}
