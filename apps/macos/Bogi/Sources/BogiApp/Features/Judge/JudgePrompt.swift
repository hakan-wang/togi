import Foundation

/// Builds the messages for the 5-minute judge `/v1/infer` call.
///
/// The system prompt and the templated user JSON mirror the plan's
/// "The 5-minute judge prompt (concrete)" section exactly: the user payload
/// carries `now`, the (optional) `active_block`, `recent_off_task_minutes`, and
/// the raw `observations` captured over the last ~5 minutes.
///
/// This type is intentionally framework-light and pure so it can be unit tested
/// without a database, network, or AppKit.
enum JudgePrompt {
    /// Verbatim system prompt from the implementation plan. The judge segments
    /// the activity, decides on-task vs the plan, and composes a blunt nudge
    /// only when the user is sustainedly off-task.
    static let systemPrompt = """
    You are Bogi's activity judge. You receive ~5 minutes of a user's on-screen activity \
    (accessibility-captured text snippets, with apps and timestamps) and the calendar block they \
    planned for this time. Do three things and return STRICT JSON only:
    1. Segment the activity into one or more time segments, each labeled \
    category → sub_category → sub_sub (sub_sub is a short concrete description) with minutes.
    2. Judge on_task: does the dominant activity match the planned block's intent?
    3. Decide a nudge: only if the user is sustainedly off-task vs the plan. Be blunt and \
    specific, never preachy, never a wall. If on-task or no plan, should=false.
    """

    /// Builds the `[system, user]` message pair for the judge inference call.
    ///
    /// - Parameters:
    ///   - now: the instant the judge tick fires (end of the captured window).
    ///   - activeBlock: the calendar block the user planned for this time, if any.
    ///   - observations: raw accessibility captures from the last ~5 minutes,
    ///     in chronological order.
    ///   - recentOffTaskMinutes: minutes the user has already been off-task in
    ///     the recent window — the "sustained drift" signal for the nudge call.
    static func buildMessages(
        now: Date,
        activeBlock: PlannedBlock?,
        observations: [ActivityObservation],
        recentOffTaskMinutes: Int
    ) -> [InferenceMessage] {
        let payload = JudgeUserPayload(
            now: JudgeTime.iso(now),
            activeBlock: activeBlock.map { block in
                JudgeUserPayload.Block(
                    title: block.title,
                    category: block.category,
                    startAt: JudgeTime.iso(block.startAt),
                    endAt: JudgeTime.iso(block.endAt)
                )
            },
            recentOffTaskMinutes: recentOffTaskMinutes,
            observations: observations.map { obs in
                JudgeUserPayload.Observation(
                    t: JudgeTime.iso(obs.capturedAt),
                    app: obs.activeApp,
                    window: obs.activeWindowTitle,
                    text: obs.text
                )
            }
        )

        return [
            InferenceMessage(role: .system, content: systemPrompt),
            InferenceMessage(role: .user, content: encode(payload)),
        ]
    }

    /// Encodes the templated user payload. Uses snake_case keys and sorted keys
    /// so the prompt is deterministic (handy for snapshot-style tests). Falls
    /// back to a minimal object if encoding somehow fails.
    private static func encode(_ payload: JudgeUserPayload) -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"now\":\"\(payload.now)\",\"observations\":[]}"
        }
        return json
    }
}

/// The templated user JSON sent to the judge. Property names are camelCase and
/// converted to snake_case by the encoder (`active_block`, `start_at`, …).
struct JudgeUserPayload: Encodable, Equatable {
    struct Block: Encodable, Equatable {
        var title: String
        var category: String?
        var startAt: String
        var endAt: String
    }

    struct Observation: Encodable, Equatable {
        var t: String
        var app: String?
        var window: String?
        var text: String?
    }

    var now: String
    var activeBlock: Block?
    var recentOffTaskMinutes: Int
    var observations: [Observation]
}

/// Shared ISO-8601 conversion for the judge module. Produces internet date-time
/// strings and parses both fractional- and whole-second variants the model may
/// echo back.
enum JudgeTime {
    static func iso(_ date: Date) -> String {
        plain.string(from: date)
    }

    /// Parses an ISO-8601 string, tolerating the optional fractional-seconds the
    /// model may include. Returns `nil` for unparseable input.
    static func date(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return plain.date(from: trimmed) ?? fractional.date(from: trimmed)
    }

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
