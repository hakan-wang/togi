import Foundation

/// Everything the judge needs for one 5-minute tick: the active calendar block (if any),
/// the recent observations, and how long the user has already drifted off-task.
struct JudgeInput {
    var activeBlock: (title: String, cat: String?, startAt: Date, endAt: Date)?
    var observations: [(t: Date, app: String?, window: String?, text: String?, focused: Bool)]
    var recentOffTaskMinutes: Int
    var activeEvents: [(title: String, cat: String?, startAt: Date, endAt: Date)] = []
    var activeGoals: [(id: String, title: String, status: String, cat: String?)] = []
    var dueCheckIns: [(eventId: String, goalId: String?, title: String)] = []
}

/// Builds the user payload for the activity judge tick. Pure string construction so the
/// shape of what we send the agent is unit-testable. The persona/segmentation instructions
/// now live in the sidecar agent; this only serializes the observations + active block.
enum JudgePrompt {
    // Expected output JSON shape (strict, no prose):
    // {
    //   "segments": [
    //     { "start_at": ISO8601, "end_at": ISO8601, "minutes": Double,
    //       "cat": String, "sub": String, "title": String, "desc": String,
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
            if let cat = block.cat { b["cat"] = cat }
            root["planned_block"] = b
        } else {
            root["planned_block"] = NSNull()
        }

        root["recent_off_task_minutes"] = input.recentOffTaskMinutes

        if !input.activeEvents.isEmpty {
            root["active_events"] = input.activeEvents.map { e -> [String: Any] in
                var o: [String: Any] = ["title": e.title,
                                        "start_at": iso.string(from: e.startAt),
                                        "end_at": iso.string(from: e.endAt)]
                if let cat = e.cat { o["cat"] = cat }
                return o
            }
        }

        if !input.activeGoals.isEmpty {
            root["active_goals"] = input.activeGoals.map { g -> [String: Any] in
                var o: [String: Any] = ["id": g.id, "title": g.title, "status": g.status]
                if let cat = g.cat { o["cat"] = cat }
                return o
            }
        }

        if !input.dueCheckIns.isEmpty {
            root["due_check_ins"] = input.dueCheckIns.map { c -> [String: Any] in
                var o: [String: Any] = ["event_id": c.eventId, "title": c.title]
                if let goalId = c.goalId { o["goal_id"] = goalId }
                return o
            }
        }

        root["observations"] = input.observations.map { obs -> [String: Any] in
            var o: [String: Any] = ["t": iso.string(from: obs.t), "focused": obs.focused]
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
