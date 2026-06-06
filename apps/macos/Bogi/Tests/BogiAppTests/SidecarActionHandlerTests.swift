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
            "minutes": 5, "category": "Work", "sub_category": "Coding", "sub_sub": "Editing",
            "on_task": true, "confidence": 0.9,
        ]]]
        let result = await handlers.handle("record_segments", input)
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(result["count"] as? Int, 1)
        XCTAssertEqual(inserted.first?.category, "Work")
        XCTAssertEqual(inserted.first?.onTask, true)
    }
}
