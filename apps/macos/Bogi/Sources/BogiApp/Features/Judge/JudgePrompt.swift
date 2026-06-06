import Foundation

/// Everything the judge needs for one 5-minute tick: the active calendar block (if any),
/// the recent observations, and how long the user has already drifted off-task.
struct JudgeInput {
    var activeBlock: (title: String, category: String?, startAt: Date, endAt: Date)?
    var observations: [(t: Date, app: String?, window: String?, text: String?)]
    var recentOffTaskMinutes: Int
}

/// Builds the system + user prompt for the activity judge. Pure string construction so the
/// shape of what we send the LLM is unit-testable.
enum JudgePrompt {
    static let system = """
    You are Togi's activity judge. You receive ~5 minutes of a user's on-screen activity \
    and the calendar block they planned. Return STRICT JSON only. \
    1) Segment activity into time segments each labeled category, sub_category, sub_sub \
    (short concrete description) with minutes. \
    2) Judge on_task: does the dominant activity match the planned block's intent? \
    3) Decide a nudge only if sustainedly off-task vs plan; be blunt and specific, never \
    preachy; if on-task or no plan, should=false.
    """

    // Expected output JSON shape (strict, no prose):
    // {
    //   "segments": [
    //     { "start_at": ISO8601, "end_at": ISO8601, "minutes": Double,
    //       "category": String, "sub_category": String, "sub_sub": String,
    //       "on_task": Bool, "confidence": Double }
    //   ],
    //   "nudge": { "should": Bool, "severity": Int, "message": String? }
    // }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Serializes the input into a JSON user message the model can parse deterministically.
    static func userJSON(_ input: JudgeInput) -> String {
        var root: [String: Any] = [:]

        if let block = input.activeBlock {
            var b: [String: Any] = [
                "title": block.title,
                "start_at": iso.string(from: block.startAt),
                "end_at": iso.string(from: block.endAt),
            ]
            if let category = block.category { b["category"] = category }
            root["planned_block"] = b
        } else {
            root["planned_block"] = NSNull()
        }

        root["recent_off_task_minutes"] = input.recentOffTaskMinutes

        root["observations"] = input.observations.map { obs -> [String: Any] in
            var o: [String: Any] = ["t": iso.string(from: obs.t)]
            if let app = obs.app { o["app"] = app }
            if let window = obs.window { o["window"] = window }
            if let text = obs.text { o["text"] = text }
            return o
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys, .prettyPrinted]
        ), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
