import Foundation

/// Parses a free-form "Hey Bogi" utterance into a structured planner command using an injected
/// LLM closure. The AI type itself is owned by another layer; we only depend on the closure.
final class PlannerCommandParser {
    /// A structured planning intent extracted from natural language.
    enum PlannerCommand: Equatable {
        case createBlock(title: String, start: Date, end: Date)
        case move(title: String, start: Date, end: Date)
        case unknown
    }

    private let ai: (_ prompt: String) async throws -> String

    init(ai: @escaping (_ prompt: String) async throws -> String) {
        self.ai = ai
    }

    /// Send the utterance to the LLM and decode its strict-JSON reply into a command.
    func parse(_ utterance: String, now: Date) async throws -> PlannerCommand {
        let prompt = Self.buildPrompt(utterance: utterance, now: now)
        let raw = try await ai(prompt)
        return Self.decode(raw, now: now)
    }

    // MARK: - Prompt

    static func buildPrompt(utterance: String, now: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let nowString = iso.string(from: now)

        return """
        You are the intent parser for Bogi, an accountability coach. The user spoke a short \
        command to schedule or move a planned block of focused time. Convert it into STRICT JSON \
        and nothing else: no prose, no markdown fences.

        The current time is \(nowString) (ISO-8601). Resolve all relative dates/times against it.

        Output exactly one JSON object with this shape:
        {
          "action": "create" | "move" | "unknown",
          "title": "string, the activity name (\"\" if unknown)",
          // Provide EITHER an explicit start/end ...
          "start": "ISO-8601 datetime or null",
          "end": "ISO-8601 datetime or null",
          // ... OR a relative day plus duration:
          "relativeDay": "today" | "tomorrow" | "yyyy-MM-dd" | null,
          "startTime": "HH:mm 24h local or null",
          "durationMinutes": integer or null
        }

        Rules:
        - If you cannot confidently extract a schedulable intent, return {"action":"unknown"}.
        - Prefer explicit ISO start/end when the user named both a date and time.
        - Otherwise use relativeDay + startTime + durationMinutes.
        - Default durationMinutes to 60 if a start is clear but no duration was given.

        User utterance: "\(utterance)"
        """
    }

    // MARK: - Decode (pure, testable without the AI closure)

    private struct Payload: Decodable {
        var action: String?
        var title: String?
        var start: String?
        var end: String?
        var relativeDay: String?
        var startTime: String?
        var durationMinutes: Int?
    }

    /// Decode a JSON string (the LLM reply) into a command. Tolerant of surrounding whitespace and
    /// accidental code fences. Returns `.unknown` on any failure rather than throwing.
    static func decode(_ json: String, now: Date) -> PlannerCommand {
        guard let data = sanitize(json).data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .unknown
        }

        let action = (payload.action ?? "unknown").lowercased()
        guard action == "create" || action == "move" else { return .unknown }

        guard let (start, end) = resolveInterval(payload, now: now) else { return .unknown }
        let title = (payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        switch action {
        case "create": return .createBlock(title: title, start: start, end: end)
        case "move": return .move(title: title, start: start, end: end)
        default: return .unknown
        }
    }

    // MARK: - Helpers

    private static func sanitize(_ json: String) -> String {
        var s = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            // Strip an opening fence (optionally ```json) and a closing fence.
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if let fence = s.range(of: "```", options: .backwards) {
                s = String(s[..<fence.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolve a (start, end) interval from either explicit ISO timestamps or relativeDay+startTime.
    private static func resolveInterval(_ p: Payload, now: Date) -> (Date, Date)? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseISO(_ value: String?) -> Date? {
            guard let value, !value.isEmpty else { return nil }
            return iso.date(from: value) ?? isoFractional.date(from: value)
        }

        // 1) Explicit start/end.
        if let start = parseISO(p.start) {
            if let end = parseISO(p.end), end > start {
                return (start, end)
            }
            let minutes = p.durationMinutes ?? 60
            return (start, start.addingTimeInterval(Double(max(minutes, 1)) * 60))
        }

        // 2) relativeDay + startTime + durationMinutes.
        guard let startTime = p.startTime, !startTime.isEmpty else { return nil }
        var cal = Calendar.current
        cal.timeZone = TimeZone.current

        let dayBase: Date
        switch (p.relativeDay ?? "today").lowercased() {
        case "today", "":
            dayBase = now
        case "tomorrow":
            dayBase = cal.date(byAdding: .day, value: 1, to: now) ?? now
        case let explicit:
            let df = DateFormatter()
            df.calendar = cal
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = cal.timeZone
            df.dateFormat = "yyyy-MM-dd"
            guard let parsed = df.date(from: explicit) else { return nil }
            dayBase = parsed
        }

        let timeParts = startTime.split(separator: ":")
        guard let hour = timeParts.first.flatMap({ Int($0) }) else { return nil }
        let minute = timeParts.count > 1 ? (Int(timeParts[1]) ?? 0) : 0

        var comps = cal.dateComponents([.year, .month, .day], from: dayBase)
        comps.hour = hour
        comps.minute = minute
        guard let start = cal.date(from: comps) else { return nil }

        let minutes = p.durationMinutes ?? 60
        let end = start.addingTimeInterval(Double(max(minutes, 1)) * 60)
        return (start, end)
    }
}
