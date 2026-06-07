import XCTest
@testable import BogiApp

final class SidecarActionHandlerTests: XCTestCase {
    func testCreateBlockHandlerParsesAndDelegates() async {
        var created: (String, Date, Date)?
        let handlers = SidecarActionHandlers(
            createBlock: { title, start, end in created = (title, start, end); return "blk-1" },
            moveBlock: { _, _, _ in nil })
        let iso = ISO8601DateFormatter()
        let input: [String: Any] = [
            "title": "Edit video",
            "start": "2026-06-07T15:00:00Z",
            "end": "2026-06-07T16:00:00Z",
        ]
        let result = await handlers.handle("create_block", input)
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(result["id"] as? String, "blk-1")
        XCTAssertEqual(created?.0, "Edit video")
        XCTAssertEqual(created?.1, iso.date(from: "2026-06-07T15:00:00Z"))
    }

    func testRecordSegmentsPersists() async throws {
        var inserted: [ActivitySegment] = []
        let handlers = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            postNudge: { _, _ in },
            recordSegments: { segs in inserted = segs; return segs.count })
        let input: [String: Any] = ["segments": [[
            "start_at": "2026-06-06T10:00:00Z", "end_at": "2026-06-06T10:05:00Z",
            "minutes": 5, "cat": "deepwork", "sub": "Litro", "title": "Editing",
            "on_task": true, "confidence": 0.9,
        ]]]
        let result = await handlers.handle("record_segments", input)
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(result["count"] as? Int, 1)
        XCTAssertEqual(inserted.first?.cat, "deepwork")
        XCTAssertEqual(inserted.first?.onTask, true)
    }

    func testManageCategoriesAdd() async {
        var op: (String, [String: Any])?
        let handlers = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            manageCategories: { o, args in op = (o, args); return ["ok": true] })
        let result = await handlers.handle("manage_categories", ["op": "add", "name": "Side Project", "color": "#123456"])
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(op?.0, "add")
        XCTAssertEqual(op?.1["name"] as? String, "Side Project")
    }

    func testWriteBehaviourRejectsEmpty() async {
        var saved: String?
        let handlers = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            writeBehaviour: { saved = $0 })
        let emptyResult = await handlers.handle("write_behaviour", ["text": ""])
        XCTAssertEqual(emptyResult["error"] as? String, "bad_input")
        XCTAssertNil(saved)
        let okResult = await handlers.handle("write_behaviour", ["text": "loses focus after 35m"])
        XCTAssertEqual(okResult["ok"] as? Bool, true)
        XCTAssertEqual(saved, "loses focus after 35m")
    }

    func testAddEventValidatesCategory() async {
        var inserted: UserEvent?
        let handlers = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            categoryExists: { $0 == "health" },
            addEvent: { inserted = $0; return $0.id })
        // unknown cat rejected
        let bad = await handlers.handle("add_event", ["title": "Gym", "cat": "nope",
            "start": "2026-06-06T18:00:00Z", "end": "2026-06-06T19:00:00Z"])
        XCTAssertEqual(bad["error"] as? String, "bad_input")
        XCTAssertNil(inserted)
        // valid cat accepted
        let ok = await handlers.handle("add_event", ["title": "Gym", "cat": "health",
            "start": "2026-06-06T18:00:00Z", "end": "2026-06-06T19:00:00Z"])
        XCTAssertEqual(ok["ok"] as? Bool, true)
        XCTAssertEqual(inserted?.cat, "health")
    }

    func testRecordSegmentsRejectsUnknownCat() async {
        let handlers = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            categoryExists: { $0 == "deepwork" },
            recordSegments: { _ in 0 })
        let input: [String: Any] = ["segments": [[
            "start_at": "2026-06-06T10:00:00Z", "end_at": "2026-06-06T10:05:00Z",
            "minutes": 5, "cat": "bogus", "on_task": true]]]
        let result = await handlers.handle("record_segments", input)
        XCTAssertEqual(result["error"] as? String, "bad_input")
    }
}
