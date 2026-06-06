import Foundation

/// Togi's voice brain. Turns a short spoken back-and-forth into a calendar action with one LLM
/// call per turn. The whole running conversation is replayed each turn so the model accumulates
/// the WHAT (title) and the WHEN (time) across follow-ups. The network is injected as a closure,
/// so the JSON-decode logic stays unit-testable without a backend (mirrors `PlannerCommandParser`).
final class VoiceCommandAgent {
    /// What Togi decided to do this turn.
    enum Decision: Equatable {
        /// Enough is known — put it on the calendar. `say` is the spoken confirmation.
        case schedule(title: String, start: Date, end: Date, say: String)
        /// Something essential is missing — ask `say`, then listen again.
        case needInfo(say: String)
        /// Ordinary talk that isn't a scheduling request.
        case chat(say: String)
        /// The user wants to stop.
        case cancel(say: String)
    }

    /// One line of the spoken mini-conversation. `role` is "user" or "togi".
    struct Turn: Equatable {
        let role: String
        let text: String
        init(role: String, text: String) { self.role = role; self.text = text }
    }

    private let infer: (_ system: String?, _ messages: [InferenceMessage]) async throws -> String
    private let clock: () -> Date

    init(clock: @escaping () -> Date = { Date() },
         infer: @escaping (_ system: String?, _ messages: [InferenceMessage]) async throws -> String) {
        self.infer = infer
        self.clock = clock
    }

    /// Decide the next action given the conversation so far.
    func decide(history: [Turn]) async throws -> Decision {
        let now = clock()
        let convo = history
            .map { "\($0.role == "togi" ? "Togi" : "User"): \($0.text)" }
            .joined(separator: "\n")
        let user = "Conversation so far:\n\(convo)\n\nReturn the JSON for your next action now."
        let raw = try await infer(Self.systemPrompt(now: now), [InferenceMessage(role: "user", content: user)])
        return Self.decode(raw, now: now)
    }

    // MARK: - Prompt

    static func systemPrompt(now: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let nowString = iso.string(from: now)
        let tz = TimeZone.current.identifier

        return """
        You are Togi, a warm, concise voice companion living in a floating window on the user's \
        Mac. The user talks to you out loud to put things on their calendar. Hold a short spoken \
        back-and-forth: work out WHAT the event is and WHEN, then schedule it.

        The current time is \(nowString) (time zone \(tz)). Resolve every relative date and time \
        ("tomorrow", "in an hour", "friday at 3") against it, in the user's local time zone.

        Reply with STRICT JSON ONLY — no prose, no markdown fences:
        {
          "intent": "schedule" | "need_info" | "chat" | "cancel",
          "title": "short event title, e.g. \\"Call with Sarah\\" (\\"\\" if not yet known)",
          "start": "local ISO-8601 datetime with offset, or null",
          "end": "local ISO-8601 datetime with offset, or null",
          "say": "one short, friendly sentence for Togi to speak aloud"
        }

        Rules:
        - Use "schedule" ONLY when you have a clear title AND a concrete start time. Pick a \
        sensible end (a call or meeting defaults to 30 minutes, anything else 60). "say" confirms \
        it naturally, e.g. "done, i've put a call with sarah on your calendar for tomorrow at 3 pm."
        - Use "need_info" when something essential is missing or ambiguous (no time, unclear day, \
        unclear who or what). "say" is the single question to ask — short and natural.
        - Use "chat" for talk that is not a scheduling request. You cannot see the user's activity \
        data here, so for questions about their time or stats, tell them to ask in the chat box. \
        Never invent facts, numbers, or events.
        - Use "cancel" if the user says never mind, stop, or cancel.
        - Never invent a time the user did not give. When unsure, ask.
        - Keep "say" to one short sentence, in lowercase, with no em dashes; it is spoken aloud.
        """
    }

    // MARK: - Decode (pure, testable without the network)

    private struct Payload: Decodable {
        var intent: String?
        var title: String?
        var start: String?
        var end: String?
        var say: String?
    }

    /// Decode an LLM reply into a decision. Tolerant of code fences and surrounding prose;
    /// never throws — it degrades to a sensible conversational fallback.
    static func decode(_ raw: String, now: Date) -> Decision {
        guard let data = sanitize(raw).data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .chat(say: "sorry, i didn't catch that. could you say it again?")
        }

        let intent = (payload.intent ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let say = (payload.say ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        switch intent {
        case "schedule":
            let title = (payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let start = parseDate(payload.start, now: now), !title.isEmpty else {
                return .needInfo(say: say.isEmpty ? "what should i call it, and when?" : say)
            }
            let parsedEnd = parseDate(payload.end, now: now)
            let end = (parsedEnd != nil && parsedEnd! > start) ? parsedEnd! : start.addingTimeInterval(30 * 60)
            return .schedule(
                title: title,
                start: start,
                end: end,
                say: say.isEmpty ? "done, i've added \(title) to your calendar." : say
            )

        case "need_info", "needinfo":
            return .needInfo(say: say.isEmpty ? "could you tell me a bit more?" : say)

        case "cancel":
            return .cancel(say: say.isEmpty ? "okay, never mind." : say)

        case "chat":
            return .chat(say: say.isEmpty ? "i'm here." : say)

        default:
            return say.isEmpty ? .needInfo(say: "could you say that again?") : .chat(say: say)
        }
    }

    // MARK: - Helpers

    private static func sanitize(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if let fence = s.range(of: "```", options: .backwards) {
                s = String(s[..<fence.lowerBound])
            }
        }
        // If the model wrapped the JSON in prose, keep just the outermost object.
        if let open = s.firstIndex(of: "{"), let close = s.lastIndex(of: "}"), open < close {
            s = String(s[open...close])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse a datetime string the model produced. Accepts ISO-8601 (with or without fractional
    /// seconds / offset) and a few offset-less local formats, resolved in the current time zone.
    static func parseDate(_ value: String?, now: Date) -> Date? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw.lowercased() != "null" else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFractional.date(from: raw) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            df.dateFormat = format
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }
}
