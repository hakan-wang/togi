import XCTest
import GRDB
@testable import BogiApp

final class InsightsTests: XCTestCase {

    // A fixed UTC calendar so period math + labels are deterministic across machines.
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func makeSegment(
        id: String,
        start: Date,
        minutes: Double,
        category: String?,
        onTask: Bool?,
        plannedBlockId: String? = nil
    ) -> ActivitySegment {
        ActivitySegment(
            id: id,
            startAt: start,
            endAt: start.addingTimeInterval(minutes * 60),
            minutes: minutes,
            plannedBlockId: plannedBlockId,
            category: category,
            subCategory: nil,
            subSub: "did \(category ?? "stuff")",
            onTask: onTask,
            confidence: 0.9,
            judgedAt: start
        )
    }

    private func makeBlock(id: String, title: String, start: Date, end: Date) -> PlannedBlock {
        PlannedBlock(
            id: id,
            source: "local",
            externalEventId: nil,
            title: title,
            startAt: start,
            endAt: end,
            category: nil,
            goalId: nil,
            status: "planned",
            createdByBogi: true,
            updatedAt: start
        )
    }

    // MARK: - Day aggregation

    func testDayInsightTotalsCategoryOrderingAndOnTask() throws {
        let db = try DatabaseService(inMemory: true)
        let cal = calendar
        // Noon UTC on 2026-06-06.
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 6, hour: 12))!

        let segments = [
            makeSegment(id: "a", start: day, minutes: 60, category: "work", onTask: true),
            makeSegment(id: "b", start: day.addingTimeInterval(3600), minutes: 30, category: "work", onTask: false),
            makeSegment(id: "c", start: day.addingTimeInterval(7200), minutes: 45, category: "social", onTask: false),
            makeSegment(id: "d", start: day.addingTimeInterval(10_800), minutes: 15, category: nil, onTask: true)
        ]
        try db.dbQueue.write { dbc in
            for seg in segments { try seg.insert(dbc) }
        }

        let service = InsightsService(database: db)
        let insight = service.insight(for: .day, containing: day, calendar: cal)

        XCTAssertEqual(insight.label, "2026-06-06")
        XCTAssertEqual(insight.totalMinutes, 150, accuracy: 0.001)
        XCTAssertEqual(insight.onTaskMinutes, 75, accuracy: 0.001) // a (60) + d (15)

        // Categories sorted desc by minutes: work 90, social 45, uncategorized 15.
        XCTAssertEqual(insight.categories.map(\.category), ["work", "social", "uncategorized"])
        let work = insight.categories.first { $0.category == "work" }
        XCTAssertEqual(work!.minutes, 90, accuracy: 0.001)
        XCTAssertEqual(work!.onTaskMinutes, 60, accuracy: 0.001) // only segment a was on task
        let social = insight.categories.first { $0.category == "social" }
        XCTAssertEqual(social!.onTaskMinutes, 0, accuracy: 0.001)
        let uncat = insight.categories.first { $0.category == "uncategorized" }
        XCTAssertEqual(uncat!.minutes, 15, accuracy: 0.001)
        XCTAssertEqual(uncat!.onTaskMinutes, 15, accuracy: 0.001)
    }

    // MARK: - Plan vs reality

    func testDayInsightBuildsBlockComparison() throws {
        let db = try DatabaseService(inMemory: true)
        let cal = calendar
        let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 6, hour: 9))!
        let blockEnd = day.addingTimeInterval(3600) // 1h planned

        let block = makeBlock(id: "blk", title: "Deep Work", start: day, end: blockEnd)
        let segments = [
            makeSegment(id: "s1", start: day, minutes: 40, category: "work", onTask: true, plannedBlockId: "blk"),
            makeSegment(id: "s2", start: day.addingTimeInterval(2400), minutes: 20, category: "social", onTask: false, plannedBlockId: "blk"),
            // Unrelated segment not attached to any block.
            makeSegment(id: "s3", start: day.addingTimeInterval(3600), minutes: 10, category: "work", onTask: true)
        ]
        try db.dbQueue.write { dbc in
            try block.insert(dbc)
            for seg in segments { try seg.insert(dbc) }
        }

        let service = InsightsService(database: db)
        let insight = service.insight(for: .day, containing: day, calendar: cal)

        XCTAssertEqual(insight.blocks.count, 1)
        let comparison = try XCTUnwrap(insight.blocks.first)
        XCTAssertEqual(comparison.blockTitle, "Deep Work")
        XCTAssertEqual(comparison.plannedMinutes, 60, accuracy: 0.001)
        XCTAssertEqual(comparison.onTaskMinutes, 40, accuracy: 0.001)
        XCTAssertEqual(comparison.offTaskMinutes, 20, accuracy: 0.001)
    }

    // MARK: - Week aggregation across two days

    func testWeekInsightAggregatesAcrossDays() throws {
        let db = try DatabaseService(inMemory: true)
        let cal = calendar
        // 2026-06-06 is a Saturday; 2026-06-07 Sunday — same ISO week W23 in this calendar
        // only if week boundaries land right, so pick two clearly-same-week days: Mon + Tue.
        let mon = cal.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 10))!
        let tue = cal.date(from: DateComponents(year: 2026, month: 6, day: 9, hour: 10))!

        let segments = [
            makeSegment(id: "m1", start: mon, minutes: 50, category: "work", onTask: true),
            makeSegment(id: "t1", start: tue, minutes: 70, category: "work", onTask: false)
        ]
        try db.dbQueue.write { dbc in
            for seg in segments { try seg.insert(dbc) }
        }

        let service = InsightsService(database: db)
        let insight = service.insight(for: .week, containing: mon, calendar: cal)

        XCTAssertTrue(insight.label.hasPrefix("2026-W"), "got \(insight.label)")
        XCTAssertEqual(insight.totalMinutes, 120, accuracy: 0.001) // both days included
        XCTAssertEqual(insight.onTaskMinutes, 50, accuracy: 0.001)
        XCTAssertTrue(insight.blocks.isEmpty) // blocks only populated for .day
        XCTAssertEqual(insight.categories.first?.category, "work")
        XCTAssertEqual(insight.categories.first!.minutes, 120, accuracy: 0.001)
    }

    // MARK: - CoachService.buildContext (pure, no network)

    func testBuildContextContainsCategoryAndGoal() {
        let insight = PeriodInsight(
            label: "2026-06-06",
            totalMinutes: 120,
            onTaskMinutes: 80,
            categories: [
                CategoryTotal(category: "work", minutes: 90, onTaskMinutes: 80),
                CategoryTotal(category: "social", minutes: 30, onTaskMinutes: 0)
            ],
            blocks: [
                BlockComparison(blockTitle: "Deep Work", plannedMinutes: 60, onTaskMinutes: 50, offTaskMinutes: 10)
            ]
        )
        let goals = [
            GoalRecord(id: "g1", title: "Ship Bogi v1", period: "quarter", target: "by July", createdAt: Date())
        ]
        let context = CoachService.buildContext(insight: insight, goals: goals, snippets: ["scrolled LinkedIn [social]"])

        XCTAssertFalse(context.isEmpty)
        XCTAssertTrue(context.contains("work"), "context should mention a category")
        XCTAssertTrue(context.contains("Ship Bogi v1"), "context should mention the goal title")
        XCTAssertTrue(context.contains("Deep Work"), "context should mention plan-vs-reality block")
        XCTAssertTrue(context.contains("scrolled LinkedIn"), "context should include retrieved snippet")
    }

    // MARK: - End-to-end ask() with mock inference

    func testAskFeedsGroundedContextToInference() async throws {
        let db = try DatabaseService(inMemory: true)
        let cal = Calendar.current
        let now = Date()
        let dayStart = cal.startOfDay(for: now).addingTimeInterval(3600)

        let seg = makeSegment(id: "x", start: dayStart, minutes: 60, category: "work", onTask: true)
        try await db.dbQueue.write { dbc in try seg.insert(dbc) }

        let goalsService = GoalsService(database: db)
        goalsService.add(title: "Finish the report", period: "month", target: nil)

        let insights = InsightsService(database: db)
        let embedder = FakeNoopEmbedding()
        let search = SearchService(database: db, index: VectorIndex(database: db), embedder: embedder)
        let mock = MockInferenceClient(response: "You spent your hour on work. Keep it up isn't my style — just don't slip.")

        let northStar = NorthStarService(database: db)
        northStar.save(text: "Become a full-time creator", why: nil)

        let coach = CoachService(
            inference: mock,
            insights: insights,
            search: search,
            goals: goalsService,
            northStar: northStar,
            database: db,
            clock: { now }
        )

        let answer = try await coach.ask("how did I do today?")
        XCTAssertFalse(answer.isEmpty)
        // The system prompt + grounded context must have been passed through.
        XCTAssertNotNil(mock.lastSystem)
        XCTAssertTrue(mock.lastSystem?.contains("accountability coach") ?? false)
        let userMsg = mock.lastMessages.first?.content ?? ""
        XCTAssertTrue(userMsg.contains("work"), "grounded context should include the category")
        XCTAssertTrue(userMsg.contains("Finish the report"), "grounded context should include the goal")
        XCTAssertTrue(userMsg.contains("Become a full-time creator"), "grounded context should include the North Star")
    }
}

/// Embedder that returns nil so SearchService falls back to keyword-only (no semantic hits).
private final class FakeNoopEmbedding: EmbeddingService {
    var dimension: Int { 3 }
    func embed(_ text: String) -> [Float]? { nil }
}
