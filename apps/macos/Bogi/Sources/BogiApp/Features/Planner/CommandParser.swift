import Foundation

// "Hey Bogi" command parsing. A deterministic local parser handles the common
// shapes offline ("one hour to edit videos tomorrow", "put a meeting at 3");
// anything it can't confidently parse is handed to `InferenceClient` with a
// strict-JSON prompt. The local parser is pure and heavily unit-tested.

/// A structured planning intent extracted from a natural-language command.
struct ParsedCommand: Equatable {
    enum Action: String, Equatable, Codable { case create, move }

    var action: Action
    var title: String
    var category: String?
    /// Resolved absolute start, when a time-of-day was given.
    var startAt: Date?
    /// Resolved absolute end (`startAt + duration`, or +default when only a time).
    var endAt: Date?
    /// Parsed duration in minutes, when given (independent of an absolute time).
    var durationMinutes: Int?
    /// True when the local parser is confident; false routes the caller to the LLM.
    var confident: Bool

    init(
        action: Action,
        title: String,
        category: String? = nil,
        startAt: Date? = nil,
        endAt: Date? = nil,
        durationMinutes: Int? = nil,
        confident: Bool = true
    ) {
        self.action = action
        self.title = title
        self.category = category
        self.startAt = startAt
        self.endAt = endAt
        self.durationMinutes = durationMinutes
        self.confident = confident
    }
}

enum CommandParser {
    /// Default block length when a command gives a time but no duration.
    static let defaultDurationMinutes = 60

    static let wakePhrases = ["hey bogi,", "hey bogi", "ok bogi,", "ok bogi", "bogi,"]
    static let moveVerbs = ["move", "reschedule", "shift", "push", "change"]
    static let createVerbs = ["put", "add", "block", "schedule", "plan", "set", "book"]

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "half": 1, // handled specially for "half an hour"
    ]

    static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
    ]

    /// Parse a command locally. Returns a `ParsedCommand`; `confident == false`
    /// signals the caller should fall back to `InferenceClient`.
    static func parse(_ raw: String, now: Date, calendar: Calendar = .current) -> ParsedCommand {
        let normalized = normalize(raw)
        let tokens = normalized.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else {
            return ParsedCommand(action: .create, title: "", confident: false)
        }

        let action: ParsedCommand.Action = tokens.contains { moveVerbs.contains($0) } ? .move : .create
        let duration = parseDuration(tokens: tokens)
        let day = parseDay(tokens: tokens, now: now, calendar: calendar)
        let timeOfDay = parseTimeOfDay(normalized: normalized)
        let category = parseCategory(tokens: tokens)
        let title = parseTitle(normalized: normalized)

        var startAt: Date?
        var endAt: Date?
        if let timeOfDay {
            let base = day ?? calendar.startOfDay(for: now)
            startAt = calendar.date(
                bySettingHour: timeOfDay.hour, minute: timeOfDay.minute, second: 0, of: base
            )
            if let startAt {
                let mins = duration ?? defaultDurationMinutes
                endAt = startAt.addingTimeInterval(TimeInterval(mins * 60))
            }
        }

        // Confident when we found a real title plus at least one of time/duration.
        let confident = !title.isEmpty && (duration != nil || timeOfDay != nil)

        return ParsedCommand(
            action: action,
            title: title,
            category: category,
            startAt: startAt,
            endAt: endAt,
            durationMinutes: duration,
            confident: confident
        )
    }

    // MARK: - Normalization

    static func normalize(_ raw: String) -> String {
        var text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for wake in wakePhrases where text.hasPrefix(wake) {
            text = String(text.dropFirst(wake.count))
            break
        }
        // Collapse punctuation that breaks tokenization, keep `#`, `:` and digits.
        let kept = text.map { ch -> Character in
            if ch.isLetter || ch.isNumber || ch == " " || ch == "#" || ch == ":" { return ch }
            return " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    // MARK: - Duration

    /// Parse a duration like "one hour", "30 minutes", "1.5 hours", "half an hour".
    static func parseDuration(tokens: [String]) -> Int? {
        // "half an hour" / "half hour"
        if let halfIdx = tokens.firstIndex(of: "half"),
           tokens[safe: halfIdx + 1] == "an" || tokens[safe: halfIdx + 1] == "hour" {
            if tokens[(halfIdx + 1)...].contains("hour") { return 30 }
        }

        for (i, token) in tokens.enumerated() {
            let unit = durationUnit(token)
            guard unit != .none else { continue }
            // Look back for a quantity (digit or number word) immediately before.
            guard let prev = tokens[safe: i - 1], let qty = quantity(prev) else { continue }
            switch unit {
            case .hour: return Int((qty * 60).rounded())
            case .minute: return Int(qty.rounded())
            case .none: continue
            }
        }
        return nil
    }

    enum DurationUnit { case hour, minute, none }

    static func durationUnit(_ token: String) -> DurationUnit {
        if ["hour", "hours", "hr", "hrs", "h"].contains(token) { return .hour }
        if ["minute", "minutes", "min", "mins", "m"].contains(token) { return .minute }
        return .none
    }

    /// A numeric quantity from a digit string ("1.5", "30") or a number word.
    static func quantity(_ token: String) -> Double? {
        if let value = Double(token) { return value }
        if let word = numberWords[token] { return Double(word) }
        return nil
    }

    // MARK: - Day

    /// Resolve "today" / "tomorrow" / a weekday name to a start-of-day date.
    static func parseDay(tokens: [String], now: Date, calendar: Calendar) -> Date? {
        if tokens.contains("today") { return calendar.startOfDay(for: now) }
        if tokens.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        }
        for token in tokens {
            if let target = weekdays[token] {
                return nextWeekday(target, from: now, calendar: calendar)
            }
        }
        return nil
    }

    /// The next occurrence of `weekday` (1=Sun…7=Sat) strictly in the future,
    /// or today if it matches and is treated as upcoming.
    static func nextWeekday(_ weekday: Int, from now: Date, calendar: Calendar) -> Date? {
        let start = calendar.startOfDay(for: now)
        let current = calendar.component(.weekday, from: start)
        var delta = weekday - current
        if delta <= 0 { delta += 7 }
        return calendar.date(byAdding: .day, value: delta, to: start)
    }

    // MARK: - Time of day

    struct TimeOfDay: Equatable { var hour: Int; var minute: Int }

    /// Parse "at 3", "at 3pm", "at 15:00", "at 9am", "to 5pm", "3:30".
    /// A bare hour is only treated as a time when it follows an "at"/"to"
    /// connector, so durations ("2 hours") aren't misread as clock times.
    static func parseTimeOfDay(normalized: String) -> TimeOfDay? {
        let tokens = normalized.split(separator: " ").map(String.init)
        // Prefer a time introduced by an "at"/"to" connector.
        for (i, token) in tokens.enumerated() where token == "at" || token == "to" {
            guard let timeToken = tokens[safe: i + 1] else { continue }
            let meridiem = tokens[safe: i + 2]
            if looksLikeTime(timeToken, meridiem: meridiem) || isBareHour(timeToken),
               let t = parseClock(timeToken, meridiemHint: meridiem) {
                return t
            }
        }
        // Otherwise accept any token that unambiguously looks like a clock time.
        for token in tokens where looksLikeTime(token, meridiem: nil) {
            if let t = parseClock(token, meridiemHint: nil) { return t }
        }
        return nil
    }

    /// Whether a token unambiguously denotes a clock time (has ":" or am/pm),
    /// optionally with a separate meridiem token following a bare number.
    static func looksLikeTime(_ token: String, meridiem: String?) -> Bool {
        if token.contains(":") { return true }
        if token.hasSuffix("am") || token.hasSuffix("pm") { return true }
        if let meridiem, meridiem == "am" || meridiem == "pm", Int(token) != nil { return true }
        return false
    }

    /// A standalone integer in 0...23 (only meaningful right after a connector).
    static func isBareHour(_ token: String) -> Bool {
        guard let value = Int(token) else { return false }
        return (0...23).contains(value)
    }

    /// Parse a single clock token ("3", "3pm", "3:30", "15:00") with optional
    /// separate meridiem hint.
    static func parseClock(_ token: String, meridiemHint: String?) -> TimeOfDay? {
        var body = token
        var pm: Bool?
        if body.hasSuffix("am") { pm = false; body = String(body.dropLast(2)) }
        else if body.hasSuffix("pm") { pm = true; body = String(body.dropLast(2)) }
        if let hint = meridiemHint {
            if hint == "am" { pm = false }
            else if hint == "pm" { pm = true }
        }

        let parts = body.split(separator: ":").map(String.init)
        guard let hourStr = parts.first, var hour = Int(hourStr), hour >= 0, hour <= 23 else { return nil }
        var minute = 0
        if parts.count > 1 {
            guard let m = Int(parts[1]), m >= 0, m < 60 else { return nil }
            minute = m
        }

        if let pm {
            if pm && hour < 12 { hour += 12 }
            if !pm && hour == 12 { hour = 0 }
        }
        guard hour <= 23 else { return nil }
        return TimeOfDay(hour: hour, minute: minute)
    }

    // MARK: - Category

    /// A `#tag` token becomes the category (e.g. "#work" → "work").
    static func parseCategory(tokens: [String]) -> String? {
        for token in tokens where token.hasPrefix("#") && token.count > 1 {
            return String(token.dropFirst())
        }
        return nil
    }

    // MARK: - Title

    /// Extract the activity title by stripping verbs, articles, quantities,
    /// units, day/time words and the time expression from the whole command.
    static func parseTitle(normalized: String) -> String {
        var tokens = normalized.split(separator: " ").map(String.init)
        tokens.removeAll { $0.hasPrefix("#") }
        return stripModifiers(tokens).joined(separator: " ")
    }

    /// Drop verbs, articles, quantities, units, day/time words and the time
    /// expression so what remains is the activity phrase.
    static func stripModifiers(_ tokens: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            // Drop "at <time> [am/pm]" / "to <time> [am/pm]" runs entirely.
            if token == "at" || token == "to" {
                let next = tokens[safe: index + 1]
                let after = tokens[safe: index + 2]
                if let next, looksLikeTime(next, meridiem: after) || isBareHour(next) {
                    index += 2
                    if let m = tokens[safe: index], m == "am" || m == "pm" { index += 1 }
                    continue
                }
                // Plain connector word — drop just the connector.
                index += 1
                continue
            }
            if isModifier(token) { index += 1; continue }
            result.append(token)
            index += 1
        }
        return result
    }

    static func isModifier(_ token: String) -> Bool {
        if moveVerbs.contains(token) || createVerbs.contains(token) { return true }
        if ["a", "an", "the", "me", "to", "for", "of", "i", "need", "want", "some", "my",
            "time", "in", "on", "next", "this", "please", "and", "at"].contains(token) { return true }
        if ["today", "tomorrow"].contains(token) { return true }
        if weekdays[token] != nil { return true }
        if durationUnit(token) != .none { return true }
        if numberWords[token] != nil { return true }
        if Double(token) != nil { return true }
        if token == "half" { return true }
        return false
    }

    // MARK: - LLM fallback

    /// The system+user messages to send to `InferenceClient` for hard cases. The
    /// model must reply with strict JSON matching `LLMCommand`.
    static func inferenceRequest(for raw: String, now: Date, calendar: Calendar = .current) -> InferenceRequest {
        let iso = ISO8601DateFormatter()
        iso.timeZone = calendar.timeZone
        let nowString = iso.string(from: now)
        let system = """
        You convert a user's natural-language scheduling command into JSON for a \
        calendar planner. The current date-time is \(nowString) (timezone \
        \(calendar.timeZone.identifier)). Reply with ONLY a JSON object, no prose, \
        of the form:
        {"action":"create"|"move","title":string,"category":string|null,\
        "start":ISO8601 string|null,"end":ISO8601 string|null,\
        "durationMinutes":integer|null}
        Resolve relative dates ("tomorrow", "next monday") against the current \
        date-time. If a time but no duration is given, leave durationMinutes null. \
        Use null for anything not specified.
        """
        return InferenceRequest(
            messages: [
                InferenceMessage(role: .system, content: system),
                InferenceMessage(role: .user, content: raw),
            ],
            maxTokens: 256
        )
    }

    /// The strict JSON shape the LLM returns.
    struct LLMCommand: Codable, Equatable {
        var action: ParsedCommand.Action
        var title: String
        var category: String?
        var start: String?
        var end: String?
        var durationMinutes: Int?
    }

    /// Decode the LLM's JSON reply into a `ParsedCommand`. Tolerates the model
    /// wrapping JSON in stray text by extracting the first `{...}` span.
    static func parse(llmResponse text: String) -> ParsedCommand? {
        guard let json = extractJSONObject(text),
              let data = json.data(using: .utf8),
              let cmd = try? JSONDecoder().decode(LLMCommand.self, from: data) else { return nil }
        let iso = ISO8601DateFormatter()
        let start = cmd.start.flatMap { iso.date(from: $0) }
        let end = cmd.end.flatMap { iso.date(from: $0) }
        return ParsedCommand(
            action: cmd.action,
            title: cmd.title,
            category: cmd.category,
            startAt: start,
            endAt: end,
            durationMinutes: cmd.durationMinutes,
            confident: true
        )
    }

    static func extractJSONObject(_ text: String) -> String? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else {
            return nil
        }
        return String(text[open...close])
    }
}

fileprivate extension Array {
    /// Safe subscript that returns nil for out-of-range indices.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
