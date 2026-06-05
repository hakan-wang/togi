import Foundation

struct RealityLog: Codable, Equatable, Identifiable {
    let id: String
    var blockID: String?
    var startAt: Date
    var endAt: Date
    var category: String?
    var userText: String
    var generatedSummary: String?
    var confidence: Double?
    var source: String
    var updatedAt: Date
}
