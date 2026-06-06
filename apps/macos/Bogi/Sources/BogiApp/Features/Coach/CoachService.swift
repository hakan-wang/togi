import Foundation
import GRDB

// MARK: - Retrieval

/// Pulls the segments most relevant to a free-text question out of the bank.
/// Kept deliberately thin so the coach does not depend on the embeddings stack:
/// the default implementation is FTS5-only, and the richer hybrid
/// `SearchService` (FTS5 + sqlite-vec) can be substituted during integration
/// without touching `CoachService`.
protocol SegmentRetrieving {
    func search(_ query: String, k: Int) async throws -> [ActivitySegment]
}

/// Keyword retrieval over the `segment_fts` FTS5 table (synchronized with
/// `activity_segments` on rowid by the schema migrator). Matches any token in
/// the query and ranks by FTS5 `rank`.
struct FTSSegmentRetriever: SegmentRetrieving {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    func search(_ query: String, k: Int) async throws -> [ActivitySegment] {
        guard k > 0, let pattern = FTS5Pattern(matchingAnyTokenIn: query) else { return [] }
        return try database.dbQueue.read { db in
            try ActivitySegment.fetchAll(db, sql: """
                SELECT activity_segments.*
                FROM activity_segments
                JOIN segment_fts ON segment_fts.rowid = activity_segments.rowid
                WHERE segment_fts MATCH ?
                ORDER BY rank
                LIMIT ?
                """, arguments: [pattern, k])
        }
    }
}

// MARK: - Context

/// Everything the coach is allowed to reason over for one question: the user's
/// standing goals, today's plan, what today actually contained, and the
/// segments retrieved as relevant to the question. Assembled by `CoachService`
/// and rendered into prompt messages by `CoachPromptBuilder` (a pure function).
struct CoachContext {
    var question: String
    var now: Date
    var goals: [Goal]
    var todayPlan: [PlannedBlock]
    var todaySegments: [ActivitySegment]
    var retrieved: [ActivitySegment]
}

/// Turns a `CoachContext` into the messages sent to the inference proxy. Pure
/// and deterministic so the prompt shape is unit-tested rather than mocked.
enum CoachPromptBuilder {
    /// The blunt accountability persona. The coach knows the user's goals and
    /// plan, is grounded strictly in the bank, speaks *to* the user (never
    /// *as* them), and is explicitly not a cheerleader.
    static let persona = """
        You are Bogi, a blunt personal accountability coach. You know the user's \
        goals and what they planned into their calendar, and you can see what \
        they actually did, captured locally on their Mac.

        Rules:
        - Be direct and honest. You are not a cheerleader and you do not flatter. \
        Name the gap between what was planned and what happened.
        - Ground every claim strictly in the data provided below. If the data \
        does not answer the question, say so plainly — never invent activity, \
        times, or numbers.
        - Reference the user's goals and planned blocks when relevant.
        - Speak to the user ("you"), never as the user.
        - Be concise. Lead with the answer, then the evidence (minutes, \
        categories, blocks).
        """

    /// ISO-8601 in UTC for stable, machine-readable timestamps in the prompt.
    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func messages(for context: CoachContext) -> [InferenceMessage] {
        [
            InferenceMessage(role: .system, content: persona),
            InferenceMessage(role: .user, content: userContent(for: context)),
        ]
    }

    /// Renders the grounded context block followed by the question. Public-ish
    /// (internal) so tests can assert on its shape directly.
    static func userContent(for context: CoachContext) -> String {
        var lines: [String] = []
        lines.append("Current time: \(timestamp(context.now))")

        lines.append("")
        lines.append("# Goals")
        if context.goals.isEmpty {
            lines.append("(none set)")
        } else {
            for goal in context.goals {
                var line = "- [\(goal.period.rawValue)] \(goal.title)"
                if let target = goal.target, !target.isEmpty {
                    line += " — target: \(target)"
                }
                lines.append(line)
            }
        }

        lines.append("")
        lines.append("# Today's plan")
        if context.todayPlan.isEmpty {
            lines.append("(nothing planned)")
        } else {
            for block in context.todayPlan {
                lines.append(
                    "- \(timestamp(block.startAt))–\(timestamp(block.endAt)) "
                    + "\(block.title) [\(block.status.rawValue)]"
                    + (block.category.map { " ·\($0)" } ?? "")
                )
            }
        }

        lines.append("")
        lines.append("# Today's activity (judged segments)")
        if context.todaySegments.isEmpty {
            lines.append("(no activity captured yet)")
        } else {
            for segment in context.todaySegments {
                lines.append(segmentLine(segment))
            }
        }

        if !context.retrieved.isEmpty {
            lines.append("")
            lines.append("# Relevant history (retrieved)")
            for segment in context.retrieved {
                lines.append(segmentLine(segment))
            }
        }

        lines.append("")
        lines.append("# Question")
        lines.append(context.question)

        return lines.joined(separator: "\n")
    }

    private static func segmentLine(_ segment: ActivitySegment) -> String {
        let onTask: String
        switch segment.onTask {
        case .some(true): onTask = "on-task"
        case .some(false): onTask = "OFF-TASK"
        case nil: onTask = "unjudged"
        }
        let category = segment.category ?? InsightAggregator.uncategorized
        var line = "- \(timestamp(segment.startAt)) "
            + "\(Int(segment.minutes.rounded()))m \(category)"
        if let sub = segment.subCategory, !sub.isEmpty { line += "/\(sub)" }
        if let desc = segment.subSub, !desc.isEmpty { line += " — \(desc)" }
        line += " (\(onTask))"
        return line
    }

    private static func timestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }
}

// MARK: - Service

/// Answers on-demand life questions ("where did my week go?", "did I hit my
/// goal, why not?", "where do I leak time?") by assembling a bounded,
/// bank-grounded context and calling the inference proxy with the blunt
/// accountability persona.
final class CoachService {
    private let inference: InferenceClient
    private let database: DatabaseService
    private let goals: GoalsService
    private let retriever: SegmentRetrieving
    private let calendar: Calendar
    private let now: () -> Date
    /// How many retrieved segments to include and the answer token budget.
    private let retrievalK: Int
    private let maxTokens: Int

    init(
        inference: InferenceClient,
        database: DatabaseService,
        goals: GoalsService,
        retriever: SegmentRetrieving,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        retrievalK: Int = 8,
        maxTokens: Int = 1024
    ) {
        self.inference = inference
        self.database = database
        self.goals = goals
        self.retriever = retriever
        self.calendar = calendar
        self.now = now
        self.retrievalK = retrievalK
        self.maxTokens = maxTokens
    }

    /// Assembles today's plan + activity + goals + retrieved history, then asks
    /// the model. Returns the model's text answer.
    func ask(_ question: String) async throws -> String {
        let context = try await makeContext(for: question)
        let request = InferenceRequest(
            messages: CoachPromptBuilder.messages(for: context),
            maxTokens: maxTokens
        )
        let response = try await inference.infer(request)
        return response.text
    }

    /// Builds the grounded context for a question. Exposed (internal) so the UI
    /// can preview the context and tests can assert on it without inference.
    func makeContext(for question: String) async throws -> CoachContext {
        let reference = now()
        let dayStart = calendar.startOfDay(for: reference)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? reference

        let todaySegments = try database.dbQueue.read { db in
            try ActivitySegment
                .filter(Column("start_at") >= dayStart && Column("start_at") < dayEnd)
                .order(Column("start_at"))
                .fetchAll(db)
        }
        let todayPlan = try database.dbQueue.read { db in
            try PlannedBlock
                .filter(Column("start_at") >= dayStart && Column("start_at") < dayEnd)
                .order(Column("start_at"))
                .fetchAll(db)
        }
        let goalList = try goals.all()
        let retrieved = try await retriever.search(question, k: retrievalK)

        return CoachContext(
            question: question,
            now: reference,
            goals: goalList,
            todayPlan: todayPlan,
            todaySegments: todaySegments,
            retrieved: retrieved
        )
    }
}
