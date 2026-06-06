import Foundation

/// Forwards a question to the on-device agent, which queries the data bank via tools.
protocol CoachBackend {
    func chat(_ text: String, threadId: String) async throws -> String
    /// Streaming variant: `onToken` is called for each token as it arrives; returns the
    /// final accumulated reply. Defaults to the non-streaming `chat` for backends that
    /// don't stream (the tokens simply never fire).
    func chat(_ text: String, threadId: String, onToken: ((String) -> Void)?) async throws -> String
}

extension CoachBackend {
    func chat(_ text: String, threadId: String, onToken: ((String) -> Void)?) async throws -> String {
        try await chat(text, threadId: threadId)
    }
}

extension SidecarClient: CoachBackend {}

/// The accountability coach. Persona, grounding, and data access now live in the agent
/// (sidecar); this type just carries the question to it on a stable conversation thread.
final class CoachService {
    private let backend: CoachBackend
    private let threadId: String

    init(backend: CoachBackend, threadId: String = "coach") {
        self.backend = backend
        self.threadId = threadId
    }

    func ask(_ question: String) async throws -> String {
        try await backend.chat(question, threadId: threadId)
    }

    /// Streaming ask: `onToken` fires for each token as the agent streams it; returns the
    /// final accumulated reply.
    func ask(_ question: String, onToken: @escaping (String) -> Void) async throws -> String {
        try await backend.chat(question, threadId: threadId, onToken: onToken)
    }

    // MARK: - Suggested openers

    /// Up to three blunt, lowercase openers grounded in the live numbers: the biggest
    /// off-task sink, today's focus ratio, an active goal, then safe generics. Pure — no
    /// db or network — so the same data always yields the same chips. Falls back to plain
    /// starters when there isn't enough tracked time to say anything specific yet. The
    /// companion empty state renders these; the host feeds it today's insight + goals.
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
