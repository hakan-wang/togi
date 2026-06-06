import Foundation

/// Executes agent action calls that only the app can perform (calendar writes, nudges).
/// Pure routing + parsing; the actual side effects are injected closures so this is testable.
final class SidecarActionHandlers {
    typealias CreateBlock = (_ title: String, _ start: Date, _ end: Date) async -> String?
    typealias MoveBlock = (_ match: String, _ start: Date, _ end: Date) async -> String?
    typealias PostNudge = (_ severity: Int, _ message: String) async -> Void
    typealias RecordSegments = (_ segments: [ActivitySegment]) async -> Int

    private let createBlock: CreateBlock
    private let moveBlock: MoveBlock
    private let postNudge: PostNudge
    private let recordSegments: RecordSegments
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    init(createBlock: @escaping CreateBlock,
         moveBlock: @escaping MoveBlock,
         postNudge: @escaping PostNudge = { _, _ in },
         recordSegments: @escaping RecordSegments = { _ in 0 }) {
        self.createBlock = createBlock
        self.moveBlock = moveBlock
        self.postNudge = postNudge
        self.recordSegments = recordSegments
    }

    /// Returns a JSON-encodable dictionary result for the given action.
    func handle(_ name: String, _ input: [String: Any]) async -> [String: Any] {
        switch name {
        case "create_block":
            guard let title = input["title"] as? String,
                  let start = date(input["start"]), let end = date(input["end"]) else {
                return ["ok": false, "error": "bad_input"]
            }
            if let id = await createBlock(title, start, end) { return ["ok": true, "id": id] }
            return ["ok": false, "error": "create_failed"]
        case "move_block":
            guard let match = input["match"] as? String,
                  let start = date(input["start"]), let end = date(input["end"]) else {
                return ["ok": false, "error": "bad_input"]
            }
            if let id = await moveBlock(match, start, end) { return ["ok": true, "id": id] }
            return ["ok": false, "error": "not_found"]
        case "post_nudge":
            guard let message = input["message"] as? String else {
                return ["ok": false, "error": "bad_input"]
            }
            let severity = (input["severity"] as? Int) ?? 0
            await postNudge(severity, message)
            return ["ok": true]
        case "record_segments":
            guard let rows = input["segments"] as? [[String: Any]] else {
                return ["ok": false, "error": "bad_input"]
            }
            let now = Date()
            let segs: [ActivitySegment] = rows.compactMap { r in
                guard let start = date(r["start_at"]), let end = date(r["end_at"]),
                      let minutes = r["minutes"] as? Double ?? (r["minutes"] as? Int).map(Double.init)
                else { return nil }
                return ActivitySegment(
                    id: UUID().uuidString, startAt: start, endAt: end, minutes: minutes,
                    plannedBlockId: nil, category: r["category"] as? String,
                    subCategory: r["sub_category"] as? String, subSub: r["sub_sub"] as? String,
                    onTask: r["on_task"] as? Bool, confidence: r["confidence"] as? Double, judgedAt: now)
            }
            let count = await recordSegments(segs)
            return ["ok": true, "count": count]
        default:
            return ["ok": false, "error": "unknown_action"]
        }
    }

    private func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        return iso.date(from: s)
    }
}
