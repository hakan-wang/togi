import Foundation

/// Builds the dashboard's "Notice" (insight) cards and goal/journey cards from the journal,
/// goals, and events stores. Read-only and period-independent, mirroring `InsightsService`.
final class DashboardFeedService {
    private let journal: JournalRepository
    private let goals: GoalsService
    private let events: UserEventRepository

    init(journal: JournalRepository, goals: GoalsService, events: UserEventRepository) {
        self.journal = journal
        self.goals = goals
        self.events = events
    }

    /// Active behavioural insights, newest first.
    func insightCards(limit: Int = 8) -> [InsightCard] {
        journal.entries(kind: "insight", status: "active", limit: limit).map {
            InsightCard(id: $0.id, title: $0.title, detail: $0.desc,
                        confidence: $0.confidence, createdAt: $0.createdAt)
        }
    }

    /// Active goals, each enriched with the next upcoming check-in and most recent journey.
    func goalCards(now: Date = Date(), journeyLimit: Int = 3) -> [GoalCard] {
        goals.all(status: "active").map { g in
            let nextCheckIn = events.events(forGoal: g.id).first { $0.startAt >= now }?.startAt
            let journey = journal.entries(goalId: g.id, status: "active", limit: journeyLimit).map {
                GoalJourneyEntry(id: $0.id, kind: $0.kind, text: $0.title, at: $0.createdAt)
            }
            return GoalCard(id: g.id, title: g.title, why: g.why, status: g.status,
                            nextCheckIn: nextCheckIn, journey: journey)
        }
    }
}
