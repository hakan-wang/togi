import Foundation

/// Executes agent action calls that only the app can perform (calendar writes, nudges).
/// Pure routing + parsing; the actual side effects are injected closures so this is testable.
final class SidecarActionHandlers {
    typealias CreateBlock = (_ title: String, _ start: Date, _ end: Date) async -> String?
    typealias MoveBlock = (_ match: String, _ start: Date, _ end: Date) async -> String?

    private let createBlock: CreateBlock
    private let moveBlock: MoveBlock
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    init(createBlock: @escaping CreateBlock, moveBlock: @escaping MoveBlock) {
        self.createBlock = createBlock
        self.moveBlock = moveBlock
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
        default:
            return ["ok": false, "error": "unknown_action"]
        }
    }

    private func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        return iso.date(from: s)
    }
}
