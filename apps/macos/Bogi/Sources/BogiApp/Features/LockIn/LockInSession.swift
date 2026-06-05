import Foundation

struct LockInSession: Codable, Equatable, Identifiable {
    let id: String
    let blockID: String?
    let startedAt: Date
    var endedAt: Date?
    var summary: String?
}
