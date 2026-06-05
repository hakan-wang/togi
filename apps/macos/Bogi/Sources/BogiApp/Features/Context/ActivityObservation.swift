import Foundation

struct ActivityObservation: Codable, Equatable, Identifiable {
    let id: String
    var blockID: String?
    var capturedAt: Date
    var activeApp: String?
    var activeWindowTitle: String?
    var localTextSummary: String?
    var categoryGuess: String?
    var confidence: Double?
    var captureMethod: String
}

struct ContextClassification: Equatable {
    let category: String
    let confidence: Double
}
