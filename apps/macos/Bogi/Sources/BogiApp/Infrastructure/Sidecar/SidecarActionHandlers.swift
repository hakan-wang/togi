import Foundation

/// Executes agent action calls that only the app can perform (calendar writes, nudges).
/// Pure routing + parsing; the actual side effects are injected closures so this is testable.
final class SidecarActionHandlers {
    typealias CreateBlock = (_ title: String, _ start: Date, _ end: Date) async -> String?
    typealias MoveBlock = (_ match: String, _ start: Date, _ end: Date) async -> String?
    typealias PostNudge = (_ severity: Int, _ message: String) async -> Void
    typealias RecordSegments = (_ segments: [ActivitySegment]) async -> Int
    typealias ManageCategories = (_ op: String, _ args: [String: Any]) async -> [String: Any]
    typealias WriteBehaviour = (_ text: String) async -> Void
    typealias AddEvent = (_ event: UserEvent) async -> String?
    typealias CategoryExists = (_ id: String) async -> Bool
    typealias ManageGoal = (_ op: String, _ args: [String: Any]) async -> [String: Any]
    typealias LogJournal = (_ entry: JournalEntry) async -> String?
    typealias SetJournalStatus = (_ id: String, _ status: String) async -> Bool
    typealias GoalExists = (_ id: String) async -> Bool

    private let createBlock: CreateBlock
    private let moveBlock: MoveBlock
    private let postNudge: PostNudge
    private let recordSegments: RecordSegments
    private let manageCategories: ManageCategories
    private let writeBehaviour: WriteBehaviour
    private let addEvent: AddEvent
    private let categoryExists: CategoryExists
    private let manageGoal: ManageGoal
    private let logJournal: LogJournal
    private let setJournalStatus: SetJournalStatus
    private let goalExists: GoalExists
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    init(createBlock: @escaping CreateBlock,
         moveBlock: @escaping MoveBlock,
         postNudge: @escaping PostNudge = { _, _ in },
         manageCategories: @escaping ManageCategories = { _, _ in ["ok": false, "error": "unsupported"] },
         writeBehaviour: @escaping WriteBehaviour = { _ in },
         categoryExists: @escaping CategoryExists = { _ in true },
         recordSegments: @escaping RecordSegments = { _ in 0 },
         addEvent: @escaping AddEvent = { _ in nil },
         manageGoal: @escaping ManageGoal = { _, _ in ["ok": false, "error": "unsupported"] },
         logJournal: @escaping LogJournal = { _ in nil },
         setJournalStatus: @escaping SetJournalStatus = { _, _ in false },
         goalExists: @escaping GoalExists = { _ in true }) {
        self.createBlock = createBlock
        self.moveBlock = moveBlock
        self.postNudge = postNudge
        self.recordSegments = recordSegments
        self.manageCategories = manageCategories
        self.writeBehaviour = writeBehaviour
        self.addEvent = addEvent
        self.categoryExists = categoryExists
        self.manageGoal = manageGoal
        self.logJournal = logJournal
        self.setJournalStatus = setJournalStatus
        self.goalExists = goalExists
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
            // Validate cats before building segments
            for r in rows {
                if let cat = r["cat"] as? String, !(await categoryExists(cat)) {
                    return ["ok": false, "error": "bad_input"]
                }
            }
            let now = Date()
            let segs: [ActivitySegment] = rows.compactMap { r in
                guard let start = date(r["start_at"]), let end = date(r["end_at"]),
                      let minutes = r["minutes"] as? Double ?? (r["minutes"] as? Int).map(Double.init)
                else { return nil }
                return ActivitySegment(
                    id: UUID().uuidString, startAt: start, endAt: end, minutes: minutes,
                    plannedBlockId: nil,
                    cat: r["cat"] as? String,
                    sub: r["sub"] as? String,
                    title: r["title"] as? String,
                    desc: r["desc"] as? String,
                    onTask: r["on_task"] as? Bool, confidence: r["confidence"] as? Double, judgedAt: now)
            }
            let count = await recordSegments(segs)
            return ["ok": true, "count": count]
        case "manage_categories":
            guard let op = input["op"] as? String else { return ["ok": false, "error": "bad_input"] }
            return await manageCategories(op, input)
        case "write_behaviour":
            guard let text = input["text"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return ["ok": false, "error": "bad_input"] }
            await writeBehaviour(text)
            return ["ok": true]
        case "add_event":
            guard let title = input["title"] as? String,
                  let start = date(input["start"]), let end = date(input["end"]) else {
                return ["ok": false, "error": "bad_input"]
            }
            let cat = input["cat"] as? String
            if let cat, !(await categoryExists(cat)) { return ["ok": false, "error": "bad_input"] }
            let goalId = input["goal_id"] as? String
            if let goalId, !(await goalExists(goalId)) { return ["ok": false, "error": "bad_input"] }
            let event = UserEvent(id: UUID().uuidString, title: title, desc: input["desc"] as? String,
                                  cat: cat, sub: input["sub"] as? String,
                                  startAt: start, endAt: end, createdAt: Date(), goalId: goalId)
            if let id = await addEvent(event) { return ["ok": true, "id": id] }
            return ["ok": false, "error": "insert_failed"]
        case "manage_goal":
            guard let op = input["op"] as? String else { return ["ok": false, "error": "bad_input"] }
            if let cat = input["cat"] as? String, !(await categoryExists(cat)) {
                return ["ok": false, "error": "bad_input"]
            }
            return await manageGoal(op, input)
        case "log_journal":
            let allowedKinds: Set<String> = ["insight", "progress", "checkin", "milestone"]
            guard let kind = input["kind"] as? String, allowedKinds.contains(kind),
                  let title = input["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return ["ok": false, "error": "bad_input"] }
            if let cat = input["cat"] as? String, !(await categoryExists(cat)) {
                return ["ok": false, "error": "bad_input"]
            }
            if let goalId = input["goal_id"] as? String, !(await goalExists(goalId)) {
                return ["ok": false, "error": "bad_input"]
            }
            let evidenceJSON: String? = {
                guard let ev = input["evidence"] else { return nil }
                guard let data = try? JSONSerialization.data(withJSONObject: ev) else { return nil }
                return String(data: data, encoding: .utf8)
            }()
            let entry = JournalEntry(
                id: UUID().uuidString, createdAt: Date(), kind: kind,
                goalId: input["goal_id"] as? String, cat: input["cat"] as? String,
                title: title, desc: input["desc"] as? String,
                confidence: input["confidence"] as? Double, evidence: evidenceJSON, status: "active")
            if let id = await logJournal(entry) { return ["ok": true, "id": id] }
            return ["ok": false, "error": "insert_failed"]
        case "set_journal_status":
            guard let id = input["id"] as? String, let status = input["status"] as? String else {
                return ["ok": false, "error": "bad_input"]
            }
            return ["ok": await setJournalStatus(id, status)]
        default:
            return ["ok": false, "error": "unknown_action"]
        }
    }

    private func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        return iso.date(from: s)
    }
}
