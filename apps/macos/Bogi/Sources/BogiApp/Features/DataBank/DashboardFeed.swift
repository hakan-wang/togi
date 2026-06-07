import Foundation

/// Read-only, period-independent value types the dashboard renders below the period stats.
/// Like `PeriodInsight`, these are a contract consumed by the dashboard views — keep stable.

/// A behavioural insight ("Notice") the agent recorded, surfaced as a card.
struct InsightCard: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String?
    let confidence: Double?
    let createdAt: Date
}

/// One entry in a goal's journey timeline: a progress note, a check-in, or a milestone.
struct GoalJourneyEntry: Equatable, Identifiable {
    let id: String
    let kind: String        // progress | checkin | milestone
    let text: String
    let at: Date
}

/// An active goal as shown on the dashboard: its motivation, status, the next scheduled
/// check-in (if any), and a few recent journey entries.
struct GoalCard: Equatable, Identifiable {
    let id: String
    let title: String
    let why: String?
    let status: String
    let nextCheckIn: Date?
    let journey: [GoalJourneyEntry]
}
