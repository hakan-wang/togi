import XCTest
import GRDB
@testable import BogiApp

// MARK: - Test doubles

/// Inference client that returns a canned text and records the request it saw.
private final class MockInferenceClient: InferenceClient {
    var responseText: String
    private(set) var lastRequest: InferenceRequest?
    private(set) var callCount = 0

    init(responseText: String) { self.responseText = responseText }

    func infer(_ request: InferenceRequest) async throws -> InferenceResponse {
        lastRequest = request
        callCount += 1
        return InferenceResponse(text: responseText)
    }
}

private final class MockEmbedder: SegmentEmbedder {
    private(set) var embedded: [(id: String, text: String)] = []
    func embed(segmentId: String, text: String) async throws {
        embedded.append((segmentId, text))
    }
}

private final class MockNudgeSink: NudgeSink {
    private(set) var presented: [Nudge] = []
    func present(_ nudge: Nudge) { presented.append(nudge) }
}

final class JudgeTests: XCTestCase {

    // MARK: Fixtures

    private func makeObservation(
        id: String,
        at date: Date,
        app: String?,
        window: String?,
        text: String?
    ) -> ActivityObservation {
        ActivityObservation(
            id: id, capturedAt: date, activeApp: app, activeAppBundleId: nil,
            activeWindowTitle: window, text: text, contentHash: nil,
            captureMethod: .ax, excluded: false
        )
    }

    private func insert(_ db: DatabaseService, observations: [ActivityObservation]) throws {
        try db.dbQueue.write { conn in
            for var obs in observations { try obs.insert(conn) }
        }
    }

    private func insert(_ db: DatabaseService, block: PlannedBlock) throws {
        try db.dbQueue.write { conn in
            var b = block
            try b.insert(conn)
        }
    }

    /// Canned judge output: 4 min off-task on LinkedIn, 1 min on-task editing,
    /// plus a nudge — mirrors the plan's "Expected output" fixture.
    private let cannedJSON = """
    {
      "segments": [
        {"start_at":"2026-06-06T10:00:00Z","end_at":"2026-06-06T10:04:00Z","minutes":4,
         "category":"distraction","sub_category":"social media",
         "sub_sub":"scrolling LinkedIn feed","on_task":false,"confidence":0.9},
        {"start_at":"2026-06-06T10:04:00Z","end_at":"2026-06-06T10:05:00Z","minutes":1,
         "category":"work","sub_category":"video editing",
         "sub_sub":"Final Cut timeline","on_task":true,"confidence":0.8}
      ],
      "nudge": {"should": true, "severity": 1,
        "message": "You blocked this hour to edit videos — that's 4 minutes on LinkedIn. Back to the timeline?"}
    }
    """

    private func makeActiveBlock(now: Date) -> PlannedBlock {
        PlannedBlock(
            id: "block-1", source: .local, externalEventId: nil, title: "Edit videos",
            startAt: now.addingTimeInterval(-600), endAt: now.addingTimeInterval(3000),
            category: "work/content", goalId: nil, status: .active,
            createdByBogi: false, updatedAt: now
        )
    }

    // MARK: Prompt builder

    func testPromptBuilderShape() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let block = makeActiveBlock(now: now)
        let observations = [
            makeObservation(id: "o1", at: now.addingTimeInterval(-120),
                            app: "Safari", window: "LinkedIn Feed", text: "scrolling"),
            makeObservation(id: "o2", at: now.addingTimeInterval(-60),
                            app: "Final Cut Pro", window: "Timeline", text: "editing"),
        ]

        let messages = JudgePrompt.buildMessages(
            now: now, activeBlock: block, observations: observations, recentOffTaskMinutes: 4
        )

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[0].content, JudgePrompt.systemPrompt)
        XCTAssertTrue(messages[0].content.contains("STRICT JSON only"))

        XCTAssertEqual(messages[1].role, .user)
        let data = try XCTUnwrap(messages[1].content.data(using: .utf8))
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertNotNil(json["now"])
        XCTAssertEqual(json["recent_off_task_minutes"] as? Int, 4)

        let activeBlock = try XCTUnwrap(json["active_block"] as? [String: Any])
        XCTAssertEqual(activeBlock["title"] as? String, "Edit videos")
        XCTAssertEqual(activeBlock["category"] as? String, "work/content")
        XCTAssertNotNil(activeBlock["start_at"])
        XCTAssertNotNil(activeBlock["end_at"])

        let obs = try XCTUnwrap(json["observations"] as? [[String: Any]])
        XCTAssertEqual(obs.count, 2)
        XCTAssertEqual(obs[0]["app"] as? String, "Safari")
        XCTAssertEqual(obs[0]["window"] as? String, "LinkedIn Feed")
        XCTAssertNotNil(obs[0]["t"])
    }

    func testPromptOmitsActiveBlockWhenNoneAndStillValidJSON() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let messages = JudgePrompt.buildMessages(
            now: now, activeBlock: nil, observations: [], recentOffTaskMinutes: 0
        )
        let data = try XCTUnwrap(messages[1].content.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["active_block"])
        XCTAssertEqual(json["recent_off_task_minutes"] as? Int, 0)
        XCTAssertEqual((json["observations"] as? [Any])?.count, 0)
    }

    // MARK: Response parsing

    func testParsePlainObject() throws {
        let result = try JudgeResponseParser.parse(cannedJSON)
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].subSub, "scrolling LinkedIn feed")
        XCTAssertEqual(result.segments[0].onTask, false)
        XCTAssertEqual(result.segments[1].onTask, true)
        XCTAssertEqual(result.nudge?.should, true)
        XCTAssertEqual(result.nudge?.severity, 1)
    }

    func testParseFencedOutput() throws {
        let fenced = "Here is the judgment:\n```json\n\(cannedJSON)\n```\nLet me know if you need more."
        let result = try JudgeResponseParser.parse(fenced)
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.nudge?.should, true)
    }

    func testParseProseWrappedWithBracesInMessage() throws {
        // Braces inside the message string must not confuse the extractor.
        let raw = """
        Sure! {note: ignore this prefix}
        {"segments": [], "nudge": {"should": false, "message": "all good {really}"}}
        trailing prose }
        """
        let result = try JudgeResponseParser.parse(raw)
        XCTAssertEqual(result.segments.count, 0)
        XCTAssertEqual(result.nudge?.should, false)
        XCTAssertEqual(result.nudge?.message, "all good {really}")
    }

    func testParseThrowsWhenNoJSON() {
        XCTAssertThrowsError(try JudgeResponseParser.parse("no json here")) { error in
            XCTAssertEqual(error as? JudgeParseError, .noJSONObject)
        }
    }

    // MARK: tick() — write + classify

    func testTickWritesSegmentsClassifiesAndNudges() async throws {
        let db = try DatabaseService(inMemory: true)
        let settings = SettingsStore(database: db)
        let now = JudgeTime.date("2026-06-06T10:05:00Z")!

        try insert(db, block: makeActiveBlock(now: now))
        try insert(db, observations: [
            makeObservation(id: "o1", at: now.addingTimeInterval(-180),
                            app: "Safari", window: "LinkedIn", text: "scrolling"),
            makeObservation(id: "o2", at: now.addingTimeInterval(-30),
                            app: "Final Cut Pro", window: "Timeline", text: "editing"),
        ])

        let inference = MockInferenceClient(responseText: cannedJSON)
        let embedder = MockEmbedder()
        let sink = MockNudgeSink()
        let service = JudgeService(
            database: db, inference: inference, settings: settings,
            embedder: embedder, nudgeSink: sink, now: { now }
        )

        let outcome = try await service.tick()
        XCTAssertEqual(outcome, .judged(segmentCount: 2, nudged: true))
        XCTAssertEqual(inference.callCount, 1)

        let segments = try db.dbQueue.read { conn in
            try ActivitySegment.order(Column("start_at")).fetchAll(conn)
        }
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].onTask, false)
        XCTAssertEqual(segments[0].subSub, "scrolling LinkedIn feed")
        XCTAssertEqual(segments[0].minutes, 4)
        XCTAssertEqual(segments[1].onTask, true)
        // All segments are attributed to the active planned block.
        XCTAssertTrue(segments.allSatisfy { $0.plannedBlockId == "block-1" })

        // Embeddings requested for each sub_sub description.
        XCTAssertEqual(Set(embedder.embedded.map { $0.text }),
                       ["scrolling LinkedIn feed", "Final Cut timeline"])

        // Nudge persisted and delivered to the sink, linked to the off-task segment.
        let nudges = try db.dbQueue.read { conn in try Nudge.fetchAll(conn) }
        XCTAssertEqual(nudges.count, 1)
        XCTAssertEqual(nudges[0].severity, 1)
        XCTAssertEqual(sink.presented.count, 1)
        XCTAssertEqual(sink.presented[0].id, nudges[0].id)
        let offTask = segments.first { $0.onTask == false }
        XCTAssertEqual(nudges[0].segmentId, offTask?.id)
    }

    func testTickSkipsWhenPaused() async throws {
        let db = try DatabaseService(inMemory: true)
        let settings = SettingsStore(database: db)
        settings.setBool(.paused, true)
        let now = JudgeTime.date("2026-06-06T10:05:00Z")!
        try insert(db, observations: [
            makeObservation(id: "o1", at: now.addingTimeInterval(-30),
                            app: "Safari", window: "x", text: "y"),
        ])
        let service = JudgeService(
            database: db, inference: MockInferenceClient(responseText: cannedJSON),
            settings: settings, now: { now }
        )
        let outcome = try await service.tick()
        XCTAssertEqual(outcome, .skippedPaused)
    }

    func testTickSkipsWhenNoActivity() async throws {
        let db = try DatabaseService(inMemory: true)
        let settings = SettingsStore(database: db)
        let now = JudgeTime.date("2026-06-06T10:05:00Z")!
        let inference = MockInferenceClient(responseText: cannedJSON)
        let service = JudgeService(database: db, inference: inference, settings: settings, now: { now })

        let outcome = try await service.tick()
        XCTAssertEqual(outcome, .skippedNoActivity)
        XCTAssertEqual(inference.callCount, 0)
    }

    func testTickIgnoresObservationsOutsideWindow() async throws {
        let db = try DatabaseService(inMemory: true)
        let settings = SettingsStore(database: db)
        let now = JudgeTime.date("2026-06-06T10:05:00Z")!
        // Only a stale observation (10 min old) → outside the 5-min window.
        try insert(db, observations: [
            makeObservation(id: "old", at: now.addingTimeInterval(-600),
                            app: "Safari", window: "x", text: "y"),
        ])
        let inference = MockInferenceClient(responseText: cannedJSON)
        let service = JudgeService(database: db, inference: inference, settings: settings, now: { now })
        let outcome = try await service.tick()
        XCTAssertEqual(outcome, .skippedNoActivity)
    }

    // MARK: Nudge debounce / snooze / DND

    func testNudgePolicyDebounce() {
        let policy = JudgeNudgePolicy(minInterval: 600)
        let now = Date(timeIntervalSince1970: 1_000_000)
        // No prior nudge → allowed.
        XCTAssertTrue(policy.shouldEmit(now: now, lastNudgeAt: nil, snoozedUntil: nil, dndUntil: nil))
        // Within the debounce interval → suppressed.
        XCTAssertFalse(policy.shouldEmit(now: now, lastNudgeAt: now.addingTimeInterval(-60),
                                         snoozedUntil: nil, dndUntil: nil))
        // After the interval → allowed.
        XCTAssertTrue(policy.shouldEmit(now: now, lastNudgeAt: now.addingTimeInterval(-601),
                                        snoozedUntil: nil, dndUntil: nil))
    }

    func testNudgePolicySnoozeAndDND() {
        let policy = JudgeNudgePolicy(minInterval: 600)
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Active snooze suppresses.
        XCTAssertFalse(policy.shouldEmit(now: now, lastNudgeAt: nil,
                                         snoozedUntil: now.addingTimeInterval(60), dndUntil: nil))
        // Expired snooze does not.
        XCTAssertTrue(policy.shouldEmit(now: now, lastNudgeAt: nil,
                                        snoozedUntil: now.addingTimeInterval(-1), dndUntil: nil))
        // DND window suppresses.
        XCTAssertFalse(policy.shouldEmit(now: now, lastNudgeAt: nil, snoozedUntil: nil,
                                         dndUntil: now.addingTimeInterval(60)))
    }

    func testTickDebouncesNudgeAcrossTicks() async throws {
        let db = try DatabaseService(inMemory: true)
        let settings = SettingsStore(database: db)
        let now = JudgeTime.date("2026-06-06T10:05:00Z")!
        try insert(db, block: makeActiveBlock(now: now))
        try insert(db, observations: [
            makeObservation(id: "o1", at: now.addingTimeInterval(-30),
                            app: "Safari", window: "LinkedIn", text: "scrolling"),
        ])
        let sink = MockNudgeSink()
        let service = JudgeService(
            database: db, inference: MockInferenceClient(responseText: cannedJSON),
            settings: settings, nudgeSink: sink, policy: JudgeNudgePolicy(minInterval: 600), now: { now }
        )

        let first = try await service.tick()
        let second = try await service.tick()

        // First tick nudges; second (same instant, within debounce) does not.
        XCTAssertEqual(first, .judged(segmentCount: 2, nudged: true))
        XCTAssertEqual(second, .judged(segmentCount: 2, nudged: false))
        XCTAssertEqual(sink.presented.count, 1)
    }

    func testTickRespectsDND() async throws {
        let db = try DatabaseService(inMemory: true)
        let settings = SettingsStore(database: db)
        settings.setBool(.dnd, true)
        let now = JudgeTime.date("2026-06-06T10:05:00Z")!
        try insert(db, block: makeActiveBlock(now: now))
        try insert(db, observations: [
            makeObservation(id: "o1", at: now.addingTimeInterval(-30),
                            app: "Safari", window: "LinkedIn", text: "scrolling"),
        ])
        let sink = MockNudgeSink()
        let service = JudgeService(
            database: db, inference: MockInferenceClient(responseText: cannedJSON),
            settings: settings, nudgeSink: sink, now: { now }
        )
        let outcome = try await service.tick()
        XCTAssertEqual(outcome, .judged(segmentCount: 2, nudged: false))
        XCTAssertEqual(sink.presented.count, 0)
        let nudges = try db.dbQueue.read { conn in try Nudge.fetchAll(conn) }
        XCTAssertEqual(nudges.count, 0)
    }

    func testTickToleratesMissingEmbedder() async throws {
        let db = try DatabaseService(inMemory: true)
        let settings = SettingsStore(database: db)
        let now = JudgeTime.date("2026-06-06T10:05:00Z")!
        try insert(db, block: makeActiveBlock(now: now))
        try insert(db, observations: [
            makeObservation(id: "o1", at: now.addingTimeInterval(-30),
                            app: "Safari", window: "LinkedIn", text: "scrolling"),
        ])
        // No embedder wired — should still judge and write segments.
        let service = JudgeService(
            database: db, inference: MockInferenceClient(responseText: cannedJSON),
            settings: settings, now: { now }
        )
        let outcome = try await service.tick()
        XCTAssertEqual(outcome, .judged(segmentCount: 2, nudged: true))
        let count = try db.dbQueue.read { conn in try ActivitySegment.fetchCount(conn) }
        XCTAssertEqual(count, 2)
    }

    // MARK: SummaryAggregator

    private func segment(
        start: String, minutes: Double, category: String?,
        onTask: Bool?, planned: Bool
    ) -> ActivitySegment {
        let startDate = JudgeTime.date(start)!
        return ActivitySegment(
            id: UUID().uuidString, startAt: startDate,
            endAt: startDate.addingTimeInterval(minutes * 60), minutes: minutes,
            plannedBlockId: planned ? "block-1" : nil, category: category,
            subCategory: nil, subSub: nil, onTask: onTask, confidence: nil,
            judgedAt: startDate
        )
    }

    func testSummarizeTotalsAndCategories() {
        let segments = [
            segment(start: "2026-06-06T09:00:00Z", minutes: 30, category: "work",
                    onTask: true, planned: true),
            segment(start: "2026-06-06T09:30:00Z", minutes: 10, category: "distraction",
                    onTask: false, planned: true),
            segment(start: "2026-06-06T10:00:00Z", minutes: 20, category: "work",
                    onTask: true, planned: false),
        ]
        let summary = SummaryAggregator.summarize(segments)

        XCTAssertEqual(summary.totalMinutes, 60)
        XCTAssertEqual(summary.onTaskMinutes, 50)
        XCTAssertEqual(summary.offTaskMinutes, 10)
        XCTAssertEqual(summary.plannedMinutes, 40)
        XCTAssertEqual(summary.unplannedMinutes, 20)
        XCTAssertEqual(summary.segmentCount, 3)

        // Sorted by minutes desc: work(50) then distraction(10).
        XCTAssertEqual(summary.categories.map { $0.category }, ["work", "distraction"])
        XCTAssertEqual(summary.categories[0].minutes, 50)
        XCTAssertEqual(summary.categories[0].onTaskMinutes, 50)
        XCTAssertEqual(summary.categories[1].offTaskMinutes, 10)
    }

    func testSummarizeUsesUncategorizedFallback() {
        let summary = SummaryAggregator.summarize([
            segment(start: "2026-06-06T09:00:00Z", minutes: 5, category: nil,
                    onTask: nil, planned: false),
        ])
        XCTAssertEqual(summary.categories.count, 1)
        XCTAssertEqual(summary.categories[0].category, "uncategorized")
        XCTAssertEqual(summary.onTaskMinutes, 0)
        XCTAssertEqual(summary.offTaskMinutes, 0)
    }

    func testGroupByDayAndWeek() {
        let segments = [
            segment(start: "2026-06-06T09:00:00Z", minutes: 30, category: "work",
                    onTask: true, planned: true),
            segment(start: "2026-06-07T09:00:00Z", minutes: 15, category: "work",
                    onTask: true, planned: true),
        ]
        let daily = SummaryAggregator.group(segments, by: .daily)
        XCTAssertEqual(Set(daily.keys), ["2026-06-06", "2026-06-07"])
        XCTAssertEqual(daily["2026-06-06"]?.totalMinutes, 30)
        XCTAssertEqual(daily["2026-06-07"]?.totalMinutes, 15)

        // Both dates fall in the same ISO week (2026-W23).
        let weekly = SummaryAggregator.group(segments, by: .weekly)
        XCTAssertEqual(weekly.count, 1)
        XCTAssertEqual(weekly.values.first?.totalMinutes, 45)
    }

    func testBucketKeyFormats() {
        let date = JudgeTime.date("2026-06-06T12:00:00Z")!
        XCTAssertEqual(SummaryAggregator.bucketKey(for: date, granularity: .daily), "2026-06-06")
        XCTAssertEqual(SummaryAggregator.bucketKey(for: date, granularity: .monthly), "2026-06")
        XCTAssertEqual(SummaryAggregator.bucketKey(for: date, granularity: .weekly), "2026-W23")
    }

    func testSummaryJSONIsStableSnakeCase() throws {
        let summary = SummaryAggregator.summarize([
            segment(start: "2026-06-06T09:00:00Z", minutes: 30, category: "work",
                    onTask: true, planned: true),
        ])
        let json = try SummaryAggregator.json(summary)
        XCTAssertTrue(json.contains("\"total_minutes\":30"))
        XCTAssertTrue(json.contains("\"on_task_minutes\":30"))
        XCTAssertTrue(json.contains("\"planned_minutes\":30"))
    }
}
