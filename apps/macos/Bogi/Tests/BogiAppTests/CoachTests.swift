import XCTest
import GRDB
@testable import BogiApp

// MARK: - Test doubles

/// Records the request it was handed and returns a canned answer.
private final class MockInferenceClient: InferenceClient, @unchecked Sendable {
    var lastRequest: InferenceRequest?
    var response: InferenceResponse
    init(response: InferenceResponse = InferenceResponse(text: "blunt answer")) {
        self.response = response
    }
    func infer(_ request: InferenceRequest) async throws -> InferenceResponse {
        lastRequest = request
        return response
    }
}

/// Returns fixed retrieval results and records the query it saw.
private final class StubRetriever: SegmentRetrieving, @unchecked Sendable {
    var results: [ActivitySegment]
    var lastQuery: String?
    var lastK: Int?
    init(results: [ActivitySegment] = []) { self.results = results }
    func search(_ query: String, k: Int) async throws -> [ActivitySegment] {
        lastQuery = query
        lastK = k
        return results
    }
}

// MARK: - Fixtures

private let refDate = Date(timeIntervalSince1970: 1_700_000_000) // fixed instant

private func utcCalendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}

private func segment(
    id: String,
    start: Date,
    minutes: Double,
    category: String?,
    sub: String? = nil,
    desc: String? = nil,
    onTask: Bool?,
    block: String? = nil
) -> ActivitySegment {
    ActivitySegment(
        id: id,
        startAt: start,
        endAt: start.addingTimeInterval(minutes * 60),
        minutes: minutes,
        plannedBlockId: block,
        category: category,
        subCategory: sub,
        subSub: desc,
        onTask: onTask,
        confidence: 0.9,
        judgedAt: start
    )
}

private func block(
    id: String,
    title: String,
    start: Date,
    minutes: Double,
    category: String? = nil,
    goalId: String? = nil,
    status: BlockStatus = .planned
) -> PlannedBlock {
    PlannedBlock(
        id: id,
        source: .local,
        externalEventId: nil,
        title: title,
        startAt: start,
        endAt: start.addingTimeInterval(minutes * 60),
        category: category,
        goalId: goalId,
        status: status,
        createdByBogi: false,
        updatedAt: start
    )
}

// MARK: - InsightAggregator

final class InsightAggregatorTests: XCTestCase {
    private let aggregator = InsightAggregator()

    func testCategoryBreakdownSumsAndSortsDescending() {
        let segments = [
            segment(id: "a", start: refDate, minutes: 30, category: "work", onTask: true),
            segment(id: "b", start: refDate, minutes: 15, category: "social", onTask: false),
            segment(id: "c", start: refDate, minutes: 20, category: "work", onTask: true),
            segment(id: "d", start: refDate, minutes: 10, category: nil, onTask: nil),
        ]
        let breakdown = aggregator.categoryBreakdown(segments)
        XCTAssertEqual(breakdown, [
            .init(category: "work", minutes: 50),
            .init(category: "social", minutes: 15),
            .init(category: InsightAggregator.uncategorized, minutes: 10),
        ])
        XCTAssertEqual(aggregator.totalMinutes(segments), 75)
    }

    func testOnTaskSplit() {
        let segments = [
            segment(id: "a", start: refDate, minutes: 30, category: "work", onTask: true),
            segment(id: "b", start: refDate, minutes: 15, category: "social", onTask: false),
            segment(id: "c", start: refDate, minutes: 10, category: nil, onTask: nil),
        ]
        let split = aggregator.onTaskSplit(segments)
        XCTAssertEqual(split.onTask, 30)
        XCTAssertEqual(split.offTask, 15)
        XCTAssertEqual(split.unknown, 10)
        XCTAssertEqual(split.total, 55)
    }

    func testTimeLeaksOnlyOffTaskBiggestFirst() {
        let segments = [
            segment(id: "a", start: refDate, minutes: 30, category: "work", onTask: true),
            segment(id: "b", start: refDate, minutes: 25, category: "social", onTask: false),
            segment(id: "c", start: refDate, minutes: 40, category: "news", onTask: false),
        ]
        let leaks = aggregator.timeLeaks(segments)
        XCTAssertEqual(leaks, [
            .init(category: "news", minutes: 40),
            .init(category: "social", minutes: 25),
        ])
    }

    func testPlanVsRealityPerBlock() {
        let start = refDate
        let blocks = [block(id: "blk", title: "Edit video", start: start, minutes: 60, category: "work")]
        let segments = [
            segment(id: "s1", start: start, minutes: 25, category: "work", onTask: true, block: "blk"),
            segment(id: "s2", start: start, minutes: 15, category: "work", onTask: true, block: "blk"),
            segment(id: "s3", start: start, minutes: 10, category: "social", onTask: false, block: "blk"),
            segment(id: "s4", start: start, minutes: 20, category: "work", onTask: true, block: nil),
        ]
        let outcomes = aggregator.blockOutcomes(segments: segments, blocks: blocks)
        XCTAssertEqual(outcomes.count, 1)
        let outcome = outcomes[0]
        XCTAssertEqual(outcome.plannedMinutes, 60)
        XCTAssertEqual(outcome.actualMinutes, 50)   // segments attributed to block
        XCTAssertEqual(outcome.onTaskMinutes, 40)   // only on-task ones
        XCTAssertEqual(outcome.fulfilment, 40.0 / 60.0, accuracy: 0.0001)
    }

    func testRecurringFailureDetection() {
        // "Email manufacturers" planned 3 days, missed every time; "Gym" planned
        // twice and done — should not be flagged.
        let day0 = refDate
        let day1 = refDate.addingTimeInterval(86_400)
        let day2 = refDate.addingTimeInterval(2 * 86_400)
        let blocks = [
            block(id: "e0", title: "Email manufacturers", start: day0, minutes: 30, status: .missed),
            block(id: "e1", title: "email manufacturers", start: day1, minutes: 30, status: .planned),
            block(id: "e2", title: "Email manufacturers ", start: day2, minutes: 30, status: .planned),
            block(id: "g0", title: "Gym", start: day0, minutes: 60, status: .done),
            block(id: "g1", title: "Gym", start: day1, minutes: 60, status: .done),
        ]
        // e1 gets only 5 on-task minutes of 30 planned (< 50% → miss); e2 gets nothing.
        let segments = [
            segment(id: "s1", start: day1, minutes: 5, category: "work", onTask: true, block: "e1"),
            segment(id: "g", start: day0, minutes: 60, category: "health", onTask: true, block: "g0"),
        ]
        let failures = aggregator.recurringFailures(segments: segments, blocks: blocks)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0].intention, "Email manufacturers") // first-seen title
        XCTAssertEqual(failures[0].plannedCount, 3)
        XCTAssertEqual(failures[0].missedCount, 3)
    }

    func testGoalOutcomesRollUpFromLinkedBlocks() {
        let goal = Goal(id: "goal1", title: "Ship app", period: .month, target: "launch", createdAt: refDate)
        let blocks = [
            block(id: "b1", title: "Build", start: refDate, minutes: 60, goalId: "goal1"),
            block(id: "b2", title: "Test", start: refDate, minutes: 30, goalId: "goal1"),
            block(id: "b3", title: "Lunch", start: refDate, minutes: 30, goalId: nil),
        ]
        let segments = [
            segment(id: "s1", start: refDate, minutes: 50, category: "work", onTask: true, block: "b1"),
            segment(id: "s2", start: refDate, minutes: 10, category: "work", onTask: false, block: "b2"),
        ]
        let outcomes = aggregator.goalOutcomes(segments: segments, blocks: blocks, goals: [goal])
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].plannedMinutes, 90)        // b1 + b2
        XCTAssertEqual(outcomes[0].actualOnTaskMinutes, 50)   // only on-task from b1
        XCTAssertTrue(outcomes[0].hasProgress)
    }

    func testDayAndPeriodInsightCompose() {
        let blocks = [block(id: "b1", title: "Focus", start: refDate, minutes: 60, goalId: nil)]
        let segments = [
            segment(id: "s1", start: refDate, minutes: 40, category: "work", onTask: true, block: "b1"),
            segment(id: "s2", start: refDate, minutes: 20, category: "social", onTask: false),
        ]
        let day = aggregator.dayInsight(segments: segments, blocks: blocks)
        XCTAssertEqual(day.totalMinutes, 60)
        XCTAssertEqual(day.blocks.count, 1)

        let period = aggregator.periodInsight(segments: segments, blocks: blocks, goals: [])
        XCTAssertEqual(period.totalMinutes, 60)
        XCTAssertEqual(period.timeLeaks, [.init(category: "social", minutes: 20)])
    }
}

// MARK: - GoalsService

final class GoalsServiceTests: XCTestCase {
    func testCRUD() throws {
        let db = try DatabaseService(inMemory: true)
        let service = GoalsService(database: db, now: { refDate })

        let created = try service.create(title: "Read 12 books", period: .year, target: "12")
        XCTAssertEqual(created.title, "Read 12 books")
        XCTAssertEqual(created.period, .year)

        var fetched = try XCTUnwrap(try service.goal(id: created.id))
        XCTAssertEqual(fetched.target, "12")

        fetched.title = "Read 24 books"
        fetched.target = "24"
        try service.update(fetched)
        XCTAssertEqual(try service.goal(id: created.id)?.title, "Read 24 books")

        _ = try service.create(title: "Monthly review", period: .month)
        XCTAssertEqual(try service.all().count, 2)
        XCTAssertEqual(try service.goals(period: .year).count, 1)

        try service.delete(id: created.id)
        XCTAssertNil(try service.goal(id: created.id))
        XCTAssertEqual(try service.all().count, 1)
    }
}

// MARK: - FTS retrieval

final class SegmentRetrievingTests: XCTestCase {
    func testFTSRetrieverReturnsMatches() async throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.write { dbConn in
            var s1 = segment(id: "s1", start: refDate, minutes: 30, category: "work",
                             sub: "video", desc: "editing the launch trailer", onTask: true)
            var s2 = segment(id: "s2", start: refDate, minutes: 20, category: "social",
                             sub: "feed", desc: "scrolling twitter timeline", onTask: false)
            try s1.insert(dbConn)
            try s2.insert(dbConn)
        }
        let retriever = FTSSegmentRetriever(database: db)

        let trailer = try await retriever.search("trailer", k: 10)
        XCTAssertEqual(trailer.map(\.id), ["s1"])

        let twitter = try await retriever.search("twitter", k: 10)
        XCTAssertEqual(twitter.map(\.id), ["s2"])

        let none = try await retriever.search("nonexistentword", k: 10)
        XCTAssertTrue(none.isEmpty)

        let zeroK = try await retriever.search("trailer", k: 0)
        XCTAssertTrue(zeroK.isEmpty)
    }
}

// MARK: - Coach context + prompt

final class CoachServiceTests: XCTestCase {
    func testPromptBuilderIncludesGoalsPlanAndSegments() {
        let context = CoachContext(
            question: "where did my day go?",
            now: refDate,
            goals: [Goal(id: "g1", title: "Ship Bogi", period: .month, target: "v1", createdAt: refDate)],
            todayPlan: [block(id: "b1", title: "Deep work", start: refDate, minutes: 90, category: "work")],
            todaySegments: [
                segment(id: "s1", start: refDate, minutes: 30, category: "social",
                        desc: "scrolling linkedin", onTask: false),
            ],
            retrieved: []
        )
        let messages = CoachPromptBuilder.messages(for: context)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertTrue(messages[0].content.lowercased().contains("blunt"))
        XCTAssertTrue(messages[0].content.lowercased().contains("cheerleader"),
                      "persona must explicitly disclaim being a cheerleader")

        let user = messages[1].content
        XCTAssertTrue(user.contains("Ship Bogi"))         // goal present
        XCTAssertTrue(user.contains("Deep work"))         // plan present
        XCTAssertTrue(user.contains("scrolling linkedin")) // today's segment present
        XCTAssertTrue(user.contains("OFF-TASK"))           // judgment surfaced
        XCTAssertTrue(user.contains("where did my day go?")) // question present
    }

    func testMakeContextFiltersToTodayAndCallsRetriever() async throws {
        let db = try DatabaseService(inMemory: true)
        let cal = utcCalendar()
        let todayStart = cal.startOfDay(for: refDate)
        let yesterday = cal.date(byAdding: .day, value: -1, to: todayStart)!

        try db.dbQueue.write { dbConn in
            var todaySeg = segment(id: "today", start: todayStart.addingTimeInterval(3600),
                                   minutes: 30, category: "work", onTask: true)
            var oldSeg = segment(id: "old", start: yesterday, minutes: 30, category: "work", onTask: true)
            var todayBlk = block(id: "tb", title: "Plan today", start: todayStart.addingTimeInterval(3600), minutes: 60)
            var oldBlk = block(id: "ob", title: "Plan yesterday", start: yesterday, minutes: 60)
            try todaySeg.insert(dbConn)
            try oldSeg.insert(dbConn)
            try todayBlk.insert(dbConn)
            try oldBlk.insert(dbConn)
        }

        let goals = GoalsService(database: db, now: { refDate })
        _ = try goals.create(title: "Focus", period: .week)
        let retriever = StubRetriever(results: [
            segment(id: "r1", start: yesterday, minutes: 10, category: "work", desc: "hit", onTask: true),
        ])
        let coach = CoachService(
            inference: MockInferenceClient(),
            database: db,
            goals: goals,
            retriever: retriever,
            calendar: cal,
            now: { refDate }
        )

        let context = try await coach.makeContext(for: "where did my time go?")
        XCTAssertEqual(context.todaySegments.map(\.id), ["today"])
        XCTAssertEqual(context.todayPlan.map(\.id), ["tb"])
        XCTAssertEqual(context.goals.count, 1)
        XCTAssertEqual(context.retrieved.map(\.id), ["r1"])
        XCTAssertEqual(retriever.lastQuery, "where did my time go?")
    }

    func testAskSendsBuiltMessagesAndReturnsAnswer() async throws {
        let db = try DatabaseService(inMemory: true)
        let goals = GoalsService(database: db, now: { refDate })
        _ = try goals.create(title: "Ship Bogi", period: .month)
        let inference = MockInferenceClient(response: InferenceResponse(text: "You leaked 2h to LinkedIn."))
        let coach = CoachService(
            inference: inference,
            database: db,
            goals: goals,
            retriever: StubRetriever(),
            calendar: utcCalendar(),
            now: { refDate }
        )

        let answer = try await coach.ask("where do I leak time?")
        XCTAssertEqual(answer, "You leaked 2h to LinkedIn.")
        let request = try XCTUnwrap(inference.lastRequest)
        XCTAssertEqual(request.messages.first?.role, .system)
        XCTAssertTrue(request.messages.last?.content.contains("where do I leak time?") ?? false)
        XCTAssertTrue(request.messages.last?.content.contains("Ship Bogi") ?? false)
    }
}
