import XCTest
@testable import BogiApp

@MainActor
final class PlannerTests: XCTestCase {
    private func makeService(sources: [CalendarSource] = []) throws -> (PlannerService, DatabaseService) {
        let db = try DatabaseService(inMemory: true)
        var counter = 0
        let service = PlannerService(
            database: db,
            sources: sources,
            now: { TestClock.reference },
            idGenerator: { counter += 1; return "block-\(counter)" }
        )
        return (service, db)
    }

    // MARK: - CRUD

    func testCreateFetchUpdateDeleteBlock() async throws {
        let (service, _) = try makeService()
        let start = TestClock.date(2026, 6, 6, 9, 0)
        let end = TestClock.date(2026, 6, 6, 10, 0)

        let block = try service.createBlock(title: "Edit videos", startAt: start, endAt: end, category: "content")
        XCTAssertEqual(block.id, "block-1")
        XCTAssertEqual(block.status, .planned)
        XCTAssertTrue(block.createdByBogi)

        let dayBlocks = try service.blocks(on: start, calendar: TestClock.utcCalendar)
        XCTAssertEqual(dayBlocks.count, 1)
        XCTAssertEqual(dayBlocks.first?.title, "Edit videos")

        var edited = try XCTUnwrap(service.block(id: block.id))
        edited.title = "Edit reels"
        try service.update(edited)
        XCTAssertEqual(try service.block(id: block.id)?.title, "Edit reels")

        try await service.deleteBlock(id: block.id)
        XCTAssertNil(try service.block(id: block.id))
    }

    func testBlocksOnDayFiltersByDate() throws {
        let (service, _) = try makeService()
        _ = try service.createBlock(title: "Today",
                                    startAt: TestClock.date(2026, 6, 6, 9),
                                    endAt: TestClock.date(2026, 6, 6, 10))
        _ = try service.createBlock(title: "Tomorrow",
                                    startAt: TestClock.date(2026, 6, 7, 9),
                                    endAt: TestClock.date(2026, 6, 7, 10))

        let today = try service.blocks(on: TestClock.date(2026, 6, 6), calendar: TestClock.utcCalendar)
        XCTAssertEqual(today.map(\.title), ["Today"])
    }

    // MARK: - Delete guardrails

    func testDeletingBogiBlockRemovesExternalEvent() async throws {
        let source = MockCalendarSource(provider: .apple)
        let (service, _) = try makeService(sources: [source])
        let block = try service.createBlock(
            title: "Bogi block",
            startAt: TestClock.date(2026, 6, 6, 9),
            endAt: TestClock.date(2026, 6, 6, 10),
            source: .apple,
            externalEventId: "apple-123",
            createdByBogi: true
        )
        try await service.deleteBlock(id: block.id)
        XCTAssertEqual(source.removedIds, ["apple-123"])
    }

    func testDeletingUserBlockNeverTouchesExternalEvent() async throws {
        let source = MockCalendarSource(provider: .apple)
        let (service, _) = try makeService(sources: [source])
        // A user-authored event imported as a block (createdByBogi == false).
        let block = try service.createBlock(
            title: "User meeting",
            startAt: TestClock.date(2026, 6, 6, 9),
            endAt: TestClock.date(2026, 6, 6, 10),
            source: .apple,
            externalEventId: "apple-999",
            createdByBogi: false
        )
        try await service.deleteBlock(id: block.id)
        // Local row gone, but the external user event was NOT deleted.
        XCTAssertNil(try service.block(id: block.id))
        XCTAssertTrue(source.removedIds.isEmpty)
    }

    // MARK: - Reconcile

    func testReconcileExternalEditUpdatesBogiBlockAndKeepsUserEvent() async throws {
        // Existing Bogi block linked to an external event.
        let source = MockCalendarSource(provider: .apple)
        let (service, _) = try makeService(sources: [source])
        _ = try service.upsert(PlannedBlock(
            id: "block-A", source: .apple, externalEventId: "apple-1",
            title: "Old title", startAt: TestClock.date(2026, 6, 6, 9),
            endAt: TestClock.date(2026, 6, 6, 10), category: "content", goalId: nil,
            status: .planned, createdByBogi: true, updatedAt: TestClock.date(2026, 6, 5)
        ))

        // The user edited that event in Calendar.app (new title + time), and a
        // brand-new user event also appeared.
        source.events = [
            ExternalCalendarEvent(
                externalId: "apple-1", provider: .apple, title: "New title",
                startAt: TestClock.date(2026, 6, 6, 11), endAt: TestClock.date(2026, 6, 6, 12),
                isBogiCreated: true, bogiBlockId: "block-A",
                lastModified: TestClock.date(2026, 6, 6, 10, 30)
            ),
            ExternalCalendarEvent(
                externalId: "apple-2", provider: .apple, title: "User lunch",
                startAt: TestClock.date(2026, 6, 6, 13), endAt: TestClock.date(2026, 6, 6, 14),
                isBogiCreated: false, lastModified: TestClock.date(2026, 6, 6, 8)
            ),
        ]

        let actions = try await service.sync(
            provider: .apple,
            from: TestClock.date(2026, 6, 6),
            to: TestClock.date(2026, 6, 7)
        )

        // The Bogi block was updated to mirror the external edit; category preserved.
        let updated = try XCTUnwrap(service.block(id: "block-A"))
        XCTAssertEqual(updated.title, "New title")
        XCTAssertEqual(updated.startAt, TestClock.date(2026, 6, 6, 11))
        XCTAssertEqual(updated.category, "content")

        // The new user event was imported as a (non-Bogi) block, not deleted.
        let imported = try XCTUnwrap(service.block(id: "ext:apple:apple-2"))
        XCTAssertFalse(imported.createdByBogi)
        XCTAssertEqual(imported.title, "User lunch")

        // Reconciliation never issues an external delete.
        XCTAssertTrue(source.removedIds.isEmpty)
        XCTAssertEqual(actions.count, 2)
    }

    func testReconcileNoChangeProducesNoActions() {
        let block = PlannedBlock(
            id: "b1", source: .google, externalEventId: "g1", title: "Same",
            startAt: TestClock.date(2026, 6, 6, 9), endAt: TestClock.date(2026, 6, 6, 10),
            category: nil, goalId: nil, status: .planned, createdByBogi: true,
            updatedAt: TestClock.reference
        )
        let event = ExternalCalendarEvent(
            externalId: "g1", provider: .google, title: "Same",
            startAt: TestClock.date(2026, 6, 6, 9), endAt: TestClock.date(2026, 6, 6, 10),
            isBogiCreated: true, bogiBlockId: "b1"
        )
        let actions = CalendarReconciler.reconcile(external: [event], existing: [block], now: TestClock.reference)
        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - Push

    func testPushNewBlockCreatesExternalEventAndStoresId() async throws {
        let source = MockCalendarSource(provider: .google)
        let (service, _) = try makeService(sources: [source])
        let block = try service.createBlock(
            title: "Deep work",
            startAt: TestClock.date(2026, 6, 6, 9),
            endAt: TestClock.date(2026, 6, 6, 11)
        )
        let pushed = try await service.pushToCalendar(blockId: block.id, provider: .google)
        XCTAssertEqual(source.createdDrafts.count, 1)
        XCTAssertEqual(pushed.externalEventId, "ext-\(block.id)")
        XCTAssertEqual(pushed.source, .google)
    }

    func testPushExistingExternalBlockUpdatesInsteadOfCreating() async throws {
        let source = MockCalendarSource(provider: .google)
        let (service, _) = try makeService(sources: [source])
        let block = try service.createBlock(
            title: "Standup",
            startAt: TestClock.date(2026, 6, 6, 9),
            endAt: TestClock.date(2026, 6, 6, 10),
            source: .google,
            externalEventId: "g-77",
            createdByBogi: true
        )
        _ = try await service.pushToCalendar(blockId: block.id, provider: .google)
        XCTAssertTrue(source.createdDrafts.isEmpty)
        XCTAssertEqual(source.updatedDrafts.first?.externalId, "g-77")
    }
}
