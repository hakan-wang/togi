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

    /// Format minutes without trailing ".0" noise.
    private static func fmt(_ minutes: Double) -> String {
        if minutes.rounded() == minutes {
            return String(Int(minutes))
        }
        return String(format: "%.1f", minutes)
    }
}
