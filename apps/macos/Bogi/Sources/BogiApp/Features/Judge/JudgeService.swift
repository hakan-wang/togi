import Foundation
import GRDB

/// Embeds a freshly-judged segment's `sub_sub` description for semantic search.
///
/// Defined here as a thin seam so the judge does not depend on the embeddings
/// session's concrete `EmbeddingService`/`VectorIndex`. The integrator wires a
/// real implementation in `AppEnvironment`; if none is wired the judge skips
/// embedding gracefully.
protocol SegmentEmbedder: AnyObject {
    func embed(segmentId: String, text: String) async throws
}

// `NudgeSink` (the seam the judge hands fired nudges to) is declared in the
// Mascot module (`Features/Mascot/NudgePresenter.swift`) and conformed to by
// `NudgePresenter`. The judge depends only on that protocol, not the concrete type.

/// Outcome of a single judge tick — surfaced so callers and tests can reason
/// about what the heartbeat did without inspecting the database.
enum JudgeTickOutcome: Equatable {
    case skippedPaused
    case skippedNoActivity
    case judged(segmentCount: Int, nudged: Bool)
}

/// The 5-minute heartbeat: turns raw `activity_observations` into categorized
/// `activity_segments` plus a nudge decision.
///
/// `tick()` holds the whole cycle (gather → infer → parse → persist → embed →
/// nudge) and is the unit-testable entry point. `start()`/`stop()` drive it on a
/// repeating timer in production. The DB-free decision logic lives in
/// `JudgeNudgePolicy`; the prompt and parsing live in `JudgePrompt`/`JudgeResponseParser`.
final class JudgeService {
    /// How often the heartbeat fires.
    static let interval: TimeInterval = 5 * 60
    /// How far back observations are gathered for each tick.
    static let observationWindow: TimeInterval = 5 * 60
    /// How far back recent off-task minutes are summed for the "sustained" signal.
    static let offTaskLookback: TimeInterval = 60 * 60

    private let database: DatabaseService
    private let inference: InferenceClient
    private let settings: SettingsStore
    private weak var embedder: SegmentEmbedder?
    private weak var nudgeSink: NudgeSink?
    private let now: () -> Date
    private let policy: JudgeNudgePolicy

    /// In-memory nudge state. `lastNudgeAt` debounces; `snoozedUntil` honors a
    /// user/mascot snooze. DND is read from settings per tick.
    private var lastNudgeAt: Date?
    private var snoozedUntil: Date?

    private var timer: Timer?
    private var isTicking = false

    init(
        database: DatabaseService,
        inference: InferenceClient,
        settings: SettingsStore,
        embedder: SegmentEmbedder? = nil,
        nudgeSink: NudgeSink? = nil,
        policy: JudgeNudgePolicy = JudgeNudgePolicy(),
        now: @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.inference = inference
        self.settings = settings
        self.embedder = embedder
        self.nudgeSink = nudgeSink
        self.policy = policy
        self.now = now
    }

    // MARK: Heartbeat lifecycle

    /// Starts the repeating 5-minute timer. Each fire launches an async `tick()`,
    /// guarded so overlapping ticks (e.g. a slow inference call) cannot stack.
    func start() {
        stop()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.tickIfIdle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Records that the user snoozed nudges until `date`.
    func snooze(until date: Date) {
        snoozedUntil = date
    }

    private func tickIfIdle() async {
        guard !isTicking else { return }
        isTicking = true
        defer { isTicking = false }
        _ = try? await tick()
    }

    // MARK: The cycle

    /// Runs one judge cycle and returns what it did. Throws only on inference or
    /// parse failure; persistence/embedding errors are contained so one bad tick
    /// never tears down the heartbeat.
    @discardableResult
    func tick() async throws -> JudgeTickOutcome {
        if settings.isPaused { return .skippedPaused }

        let current = now()
        let windowStart = current.addingTimeInterval(-Self.observationWindow)
        let observations = try fetchObservations(since: windowStart)
        guard !observations.isEmpty else { return .skippedNoActivity }

        let activeBlock = try fetchActiveBlock(at: current)
        let recentOffTask = try recentOffTaskMinutes(before: current)

        let messages = JudgePrompt.buildMessages(
            now: current,
            activeBlock: activeBlock,
            observations: observations,
            recentOffTaskMinutes: Int(recentOffTask.rounded())
        )
        let response = try await inference.infer(InferenceRequest(messages: messages))
        let result = try JudgeResponseParser.parse(response.text)

        let segments = try persistSegments(
            result.segments,
            windowStart: windowStart,
            windowEnd: current,
            activeBlock: activeBlock
        )
        await embed(segments)

        var nudged = false
        if let nudge = result.nudge, nudge.should {
            nudged = persistNudgeIfAllowed(
                nudge,
                at: current,
                segment: segments.first(where: { $0.onTask == false }) ?? segments.first,
                activeBlock: activeBlock
            )
        }

        return .judged(segmentCount: segments.count, nudged: nudged)
    }

    // MARK: Gathering

    private func fetchObservations(since windowStart: Date) throws -> [ActivityObservation] {
        try database.dbQueue.read { db in
            try ActivityObservation
                .filter(Column("captured_at") >= windowStart)
                .filter(Column("excluded") == false)
                .order(Column("captured_at"))
                .fetchAll(db)
        }
    }

    private func fetchActiveBlock(at instant: Date) throws -> PlannedBlock? {
        try database.dbQueue.read { db in
            try PlannedBlock
                .filter(Column("start_at") <= instant && Column("end_at") >= instant)
                .order(Column("start_at").desc)
                .fetchOne(db)
        }
    }

    /// Sum of minutes the user has already been judged off-task in the recent
    /// lookback window — the signal that distinguishes a momentary glance from a
    /// sustained drift.
    private func recentOffTaskMinutes(before instant: Date) throws -> Double {
        let lookbackStart = instant.addingTimeInterval(-Self.offTaskLookback)
        return try database.dbQueue.read { db in
            let segments = try ActivitySegment
                .filter(Column("start_at") >= lookbackStart)
                .filter(Column("on_task") == false)
                .fetchAll(db)
            return segments.reduce(0) { $0 + $1.minutes }
        }
    }

    // MARK: Persistence

    /// Maps judged segments onto `ActivitySegment` rows and writes them. Segment
    /// timestamps fall back to the capture window when the model omits or garbles
    /// them, so a row is always durable.
    private func persistSegments(
        _ judged: [JudgeSegment],
        windowStart: Date,
        windowEnd: Date,
        activeBlock: PlannedBlock?
    ) throws -> [ActivitySegment] {
        let judgedAt = now()
        let rows: [ActivitySegment] = judged.map { segment in
            let start = segment.startAt.flatMap(JudgeTime.date) ?? windowStart
            let end = segment.endAt.flatMap(JudgeTime.date) ?? windowEnd
            return ActivitySegment(
                id: UUID().uuidString,
                startAt: start,
                endAt: end,
                minutes: segment.minutes,
                plannedBlockId: activeBlock?.id,
                category: segment.category,
                subCategory: segment.subCategory,
                subSub: segment.subSub,
                onTask: segment.onTask,
                confidence: segment.confidence,
                judgedAt: judgedAt
            )
        }
        try database.dbQueue.write { db in
            for var row in rows { try row.insert(db) }
        }
        return rows
    }

    /// Requests an embedding for each segment's `sub_sub` description. Best-effort:
    /// a missing embedder or a per-segment failure is swallowed so judging never
    /// blocks on the embeddings pipeline.
    private func embed(_ segments: [ActivitySegment]) async {
        guard let embedder else { return }
        for segment in segments {
            guard let text = segment.subSub, !text.isEmpty else { continue }
            try? await embedder.embed(segmentId: segment.id, text: text)
        }
    }

    /// Persists a `Nudge` row and hands it to the sink, subject to debounce,
    /// snooze and DND. Returns whether a nudge actually fired.
    private func persistNudgeIfAllowed(
        _ nudge: JudgeNudge,
        at instant: Date,
        segment: ActivitySegment?,
        activeBlock: PlannedBlock?
    ) -> Bool {
        let dndUntil = settings.bool(.dnd) ? Date.distantFuture : nil
        guard policy.shouldEmit(
            now: instant,
            lastNudgeAt: lastNudgeAt,
            snoozedUntil: snoozedUntil,
            dndUntil: dndUntil
        ) else { return false }

        var row = Nudge(
            id: UUID().uuidString,
            segmentId: segment?.id,
            plannedBlockId: activeBlock?.id,
            severity: nudge.severity ?? 1,
            message: nudge.message ?? "",
            shownAt: nil,
            outcome: nil
        )
        do {
            try database.dbQueue.write { db in try row.insert(db) }
        } catch {
            return false
        }
        lastNudgeAt = instant
        nudgeSink?.present(row)
        return true
    }
}

/// Pure, DB-free nudge gating: enforces do-not-disturb, an active snooze, and a
/// debounce interval so nudges fire on sustained mismatch, not every tick (the
/// PDF's "don't bury them in notifications" guardrail).
struct JudgeNudgePolicy: Equatable {
    /// Minimum spacing between fired nudges.
    var minInterval: TimeInterval = 10 * 60

    func shouldEmit(
        now: Date,
        lastNudgeAt: Date?,
        snoozedUntil: Date?,
        dndUntil: Date?
    ) -> Bool {
        if let dndUntil, now < dndUntil { return false }
        if let snoozedUntil, now < snoozedUntil { return false }
        if let lastNudgeAt, now.timeIntervalSince(lastNudgeAt) < minInterval { return false }
        return true
    }
}
