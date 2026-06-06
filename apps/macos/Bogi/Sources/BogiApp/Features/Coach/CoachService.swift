import Foundation
import GRDB

/// The accountability coach. Answers blunt questions grounded strictly in the data bank:
/// today's insight, active goals, and a handful of retrieved segment descriptions. The
/// network call is isolated; `buildContext` is pure so the grounding logic stays testable.
final class CoachService {
    private let inference: InferenceClient
    private let insights: InsightsService
    private let search: SearchService
    private let goals: GoalsService
    private let database: DatabaseService
    private let clock: () -> Date

    init(inference: InferenceClient,
         insights: InsightsService,
         search: SearchService,
         goals: GoalsService,
         database: DatabaseService,
         clock: @escaping () -> Date = { Date() }) {
        self.inference = inference
        self.insights = insights
        self.search = search
        self.goals = goals
        self.database = database
        self.clock = clock
    }

    /// The persona. Blunt, honest, grounded — never a cheerleader, never speaks as the user.
    static let systemPrompt = """
    You are Bogi, a blunt and honest accountability coach.

    Rules:
    - Speak directly TO the user (use "you"). Never write as if you were the user.
    - Be honest and direct. Do not flatter, hype, or cheerlead. Call out wasted time and \
    gaps between plans and reality plainly.
    - Ground every claim strictly in the DATA provided below. Do not invent numbers, \
    activities, or goals.
    - If the data does not contain what is needed to answer, say "I don't have data on that." \
    Do not guess.
    - Be concise. Lead with the answer, then the evidence from the data.
    """

    /// Answer a question, grounded in today's data, active goals, and retrieved segments.
    func ask(_ question: String) async throws -> String {
        let now = clock()
        let insight = insights.insight(for: .day, containing: now)
        let activeGoals = goals.all()
        let snippets = retrieveSnippets(for: question)

        let context = Self.buildContext(insight: insight, goals: activeGoals, snippets: snippets)

        let messages = [
            InferenceMessage(role: "user", content: "DATA:\n\(context)\n\nQUESTION:\n\(question)")
        ]
        return try await inference.infer(system: Self.systemPrompt, messages: messages, maxTokens: 600)
    }

    // MARK: - Suggested openers

    /// Tappable conversation starters for the companion's empty state, derived live from
    /// today's data and active goals. Pure (`buildSuggestions`) so the wording stays
    /// testable; this just reads the data bank. No network — instant and never invented.
    func suggestions() -> [String] {
        let insight = insights.insight(for: .day, containing: clock())
        return Self.buildSuggestions(insight: insight, goals: goals.all())
    }

    /// Retrieve up to ~8 relevant segment descriptions via search, then look them up for
    /// their human-readable category / sub-sub text.
    private func retrieveSnippets(for question: String) -> [String] {
        let ids = Array(search.search(question).prefix(8))
        guard !ids.isEmpty else { return [] }
        let segments: [ActivitySegment] = (try? database.dbQueue.read { db in
            try ActivitySegment.filter(ids.contains(Column("id"))).fetchAll(db)
        }) ?? []
        // Preserve search ranking order.
        let byId = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        return ids.compactMap { id in
            guard let seg = byId[id] else { return nil }
            let what = seg.subSub ?? seg.subCategory ?? seg.category ?? "activity"
            let cat = seg.category ?? "uncategorized"
            return "\(what) [\(cat)]"
        }
    }

    // MARK: - Pure context builder

    /// Build the compact, grounded text context fed to the model. Pure — no network or db.
    static func buildContext(insight: PeriodInsight,
                             goals: [GoalRecord],
                             snippets: [String]) -> String {
        var lines: [String] = []

        lines.append("TODAY (\(insight.label)):")
        lines.append("- Total tracked: \(Self.fmt(insight.totalMinutes)) min")
        lines.append("- On task: \(Self.fmt(insight.onTaskMinutes)) min; off task: \(Self.fmt(insight.totalMinutes - insight.onTaskMinutes)) min")

        if insight.categories.isEmpty {
            lines.append("- Categories: none tracked")
        } else {
            lines.append("- Top categories:")
            for cat in insight.categories.prefix(8) {
                lines.append("  - \(cat.category): \(Self.fmt(cat.minutes)) min (\(Self.fmt(cat.onTaskMinutes)) on task)")
            }
        }

        if !insight.blocks.isEmpty {
            lines.append("- Plan vs reality:")
            for block in insight.blocks {
                lines.append("  - \(block.blockTitle): planned \(Self.fmt(block.plannedMinutes)) min, on task \(Self.fmt(block.onTaskMinutes)) min, off task \(Self.fmt(block.offTaskMinutes)) min")
            }
        }

        lines.append("")
        if goals.isEmpty {
            lines.append("ACTIVE GOALS: none set")
        } else {
            lines.append("ACTIVE GOALS:")
            for goal in goals {
                if let target = goal.target, !target.isEmpty {
                    lines.append("- \(goal.title) (\(goal.period)) — target: \(target)")
                } else {
                    lines.append("- \(goal.title) (\(goal.period))")
                }
            }
        }

        if !snippets.isEmpty {
            lines.append("")
            lines.append("RELEVANT ACTIVITY:")
            for snippet in snippets {
                lines.append("- \(snippet)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Up to three blunt, lowercase openers grounded in the live numbers: the biggest
    /// off-task sink, today's focus ratio, an active goal, then safe generics. Pure — no
    /// db or network — so the same data always yields the same chips. Falls back to plain
    /// starters when there isn't enough tracked time to say anything specific yet.
    static func buildSuggestions(insight: PeriodInsight, goals: [GoalRecord]) -> [String] {
        // Too little tracked today to be specific — offer neutral starters.
        guard insight.totalMinutes >= 5 else {
            return ["how am i doing today?",
                    "what should i focus on next?",
                    "plan my next hour"]
        }

        var out: [String] = []

        // 1) The biggest single off-task sink (only if it's worth poking at).
        let sink = insight.categories
            .map { (cat: $0.category, off: $0.minutes - $0.onTaskMinutes) }
            .filter { $0.off >= 10 }
            .max { $0.off < $1.off }
        if let sink {
            out.append("why did i lose \(Self.fmt(sink.off)) min to \(sink.cat.lowercased())?")
        }

        // 2) How focused the day actually was.
        if insight.totalMinutes >= 30 {
            let ratio = insight.onTaskMinutes / max(insight.totalMinutes, 1)
            let pct = Int((ratio * 100).rounded())
            if ratio < 0.5 {
                out.append("why was today only \(pct)% focused?")
            } else if ratio > 0.75 {
                out.append("am i actually being productive today?")
            }
        }

        // 3) An active goal to check in on.
        if let goal = goals.first {
            out.append("how am i tracking on \(goal.title.lowercased())?")
        }

        // 4) Always-relevant generics to round out to three.
        out.append("where did my time go today?")
        out.append("what should i focus on next?")

        var seen = Set<String>()
        return Array(out.filter { seen.insert($0).inserted }.prefix(3))
    }

    /// Format minutes without trailing ".0" noise.
    private static func fmt(_ minutes: Double) -> String {
        if minutes.rounded() == minutes {
            return String(Int(minutes))
        }
        return String(format: "%.1f", minutes)
    }
}
