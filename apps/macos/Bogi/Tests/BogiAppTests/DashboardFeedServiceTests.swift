import XCTest
@testable import BogiApp

final class DashboardFeedServiceTests: XCTestCase {
    private func make() throws -> (DashboardFeedService, GoalsService, JournalRepository, UserEventRepository) {
        let db = try DatabaseService(inMemory: true)
        let goals = GoalsService(database: db)
        let journal = JournalRepository(database: db)
        let events = UserEventRepository(database: db)
        return (DashboardFeedService(journal: journal, goals: goals, events: events), goals, journal, events)
    }

    private func insight(_ id: String, _ title: String, at: Date, status: String = "active") -> JournalEntry {
        JournalEntry(id: id, createdAt: at, kind: "insight", goalId: nil, cat: nil,
                     title: title, desc: "detail \(id)", confidence: 0.6, evidence: nil, status: status)
    }

    func testInsightCardsActiveNewestFirstExcludesDismissed() throws {
        let (feed, _, journal, _) = try make()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        journal.insert(insight("a", "Old", at: t0))
        journal.insert(insight("b", "New", at: t0.addingTimeInterval(60)))
        journal.insert(insight("c", "Hidden", at: t0.addingTimeInterval(120), status: "dismissed"))

        let cards = feed.insightCards()
        XCTAssertEqual(cards.map { $0.id }, ["b", "a"])
        XCTAssertEqual(cards.first?.title, "New")
        XCTAssertEqual(cards.first?.detail, "detail b")
        XCTAssertEqual(cards.first?.confidence, 0.6)
    }

    func testGoalCardsBuildNextCheckInAndRecentJourneyExcludesDone() throws {
        let (feed, goals, journal, events) = try make()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let g = goals.add(title: "Half marathon", period: "quarter", why: "feel strong")
        _ = goals.add(title: "Done goal", period: "month")
        let doneId = goals.all().first { $0.title == "Done goal" }!.id
        _ = goals.update(id: doneId, status: "done")

        journal.insert(JournalEntry(id: "j1", createdAt: now.addingTimeInterval(-200), kind: "progress",
                                    goalId: g.id, cat: nil, title: "ran 5k", desc: nil,
                                    confidence: nil, evidence: nil, status: "active"))
        journal.insert(JournalEntry(id: "j2", createdAt: now.addingTimeInterval(-100), kind: "checkin",
                                    goalId: g.id, cat: nil, title: "felt good", desc: nil,
                                    confidence: nil, evidence: nil, status: "active"))

        events.insert(UserEvent(id: "past", title: "past checkin", desc: nil, cat: nil, sub: nil,
                                startAt: now.addingTimeInterval(-3600), endAt: now.addingTimeInterval(-3300),
                                createdAt: now, goalId: g.id))
        let future = now.addingTimeInterval(3600)
        events.insert(UserEvent(id: "next", title: "next checkin", desc: nil, cat: nil, sub: nil,
                                startAt: future, endAt: future.addingTimeInterval(300),
                                createdAt: now, goalId: g.id))

        let cards = feed.goalCards(now: now)
        XCTAssertEqual(cards.count, 1, "done goal should be excluded")
        let card = cards[0]
        XCTAssertEqual(card.title, "Half marathon")
        XCTAssertEqual(card.why, "feel strong")
        XCTAssertEqual(card.nextCheckIn, future)
        XCTAssertEqual(card.journey.map { $0.id }, ["j2", "j1"], "journey newest first")
    }
}
