import XCTest
@testable import BogiApp

/// Records pushes from PlannerService without touching the network.
private final class StubCalendarWriter: PlannedBlockCalendarWriter {
    private(set) var created: [PlannedBlock] = []
    private(set) var updated: [PlannedBlock] = []
    let calendarId: String
    let eventId: String

    init(calendarId: String = "primary", eventId: String = "g-evt-1") {
        self.calendarId = calendarId
        self.eventId = eventId
    }

    func createEvent(for block: PlannedBlock) async -> (calendarId: String, externalEventId: String)? {
        created.append(block)
        return (calendarId, eventId)
    }

    func updateEvent(for block: PlannedBlock) async -> Bool {
        updated.append(block)
        return true
    }
}

final class PlannerTests: XCTestCase {

    /// Pump the run loop until `condition` holds (lets fire-and-forget push Tasks complete).
    private func waitUntil(timeout: TimeInterval = 2, _ condition: @autoclosure () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s")
    }

    // MARK: - Repository CRUD + activeBlock

    private func makeBlock(
        id: String,
        title: String = "Focus",
        start: Date,
        end: Date,
        source: String = "local",
        externalId: String? = nil,
        createdByBogi: Bool = true,
        status: String = "planned"
    ) -> PlannedBlock {
        PlannedBlock(
            id: id,
            source: source,
            externalEventId: externalId,
            title: title,
            startAt: start,
            endAt: end,
            category: nil,
            goalId: nil,
            status: status,
            createdByBogi: createdByBogi,
            updatedAt: Date()
        )
    }

    func testRepositoryCRUDAndActiveBlock() throws {
        let db = try DatabaseService(inMemory: true)
        let repo = PlannedBlockRepository(database: db)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let blockA = makeBlock(id: "a", start: base, end: base.addingTimeInterval(3600))
        let blockB = makeBlock(id: "b", start: base.addingTimeInterval(7200), end: base.addingTimeInterval(10_800))

        repo.upsert(blockA)
        repo.upsert(blockB)
        XCTAssertEqual(repo.count(), 2)
        XCTAssertEqual(repo.all().map(\.id), ["a", "b"])

        // activeBlock: inside A, gap between A and B, inside B.
        XCTAssertEqual(repo.activeBlock(at: base.addingTimeInterval(1800))?.id, "a")
        XCTAssertNil(repo.activeBlock(at: base.addingTimeInterval(5400)))
        XCTAssertEqual(repo.activeBlock(at: base.addingTimeInterval(9000))?.id, "b")
        // Boundary: end is exclusive, start is inclusive.
        XCTAssertNil(repo.activeBlock(at: base.addingTimeInterval(3600)))
        XCTAssertEqual(repo.activeBlock(at: base)?.id, "a")

        // Update via upsert.
        var updated = blockA
        updated.title = "Renamed"
        repo.upsert(updated)
        XCTAssertEqual(repo.count(), 2)
        XCTAssertEqual(repo.all().first(where: { $0.id == "a" })?.title, "Renamed")

        repo.delete(id: "a")
        XCTAssertEqual(repo.count(), 1)
        XCTAssertNil(repo.activeBlock(at: base.addingTimeInterval(1800)))
    }

    func testBlocksOnDay() throws {
        let db = try DatabaseService(inMemory: true)
        let repo = PlannedBlockRepository(database: db)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        repo.upsert(makeBlock(id: "today", start: today.addingTimeInterval(3600), end: today.addingTimeInterval(7200)))
        repo.upsert(makeBlock(id: "tomorrow", start: tomorrow.addingTimeInterval(3600), end: tomorrow.addingTimeInterval(7200)))

        let onDay = repo.blocks(onDay: today)
        XCTAssertEqual(onDay.map(\.id), ["today"])
    }

    // MARK: - reconcileExternal

    func testReconcileUpdatesExistingAndInsertsNew() throws {
        let db = try DatabaseService(inMemory: true)
        let repo = PlannedBlockRepository(database: db)
        let service = PlannerService(repository: repo)

        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // Seed an existing external (user-created) block.
        repo.upsert(makeBlock(
            id: "existing",
            title: "Old Title",
            start: base,
            end: base.addingTimeInterval(3600),
            source: "google",
            externalId: "g-1",
            createdByBogi: false
        ))

        // Reconcile: g-1 changed time+title, g-2 is brand new.
        let events = [
            ExternalCalendarEvent(source: "google", externalId: "g-1", title: "New Title",
                                  start: base.addingTimeInterval(1800), end: base.addingTimeInterval(5400)),
            ExternalCalendarEvent(source: "google", externalId: "g-2", title: "Standup",
                                  start: base.addingTimeInterval(7200), end: base.addingTimeInterval(9000))
        ]
        service.reconcileExternal(events)

        XCTAssertEqual(repo.count(), 2)
        let updated = repo.block(source: "google", externalEventId: "g-1")
        XCTAssertEqual(updated?.title, "New Title")
        XCTAssertEqual(updated?.startAt, base.addingTimeInterval(1800))
        XCTAssertEqual(updated?.endAt, base.addingTimeInterval(5400))
        XCTAssertEqual(updated?.id, "existing")   // same row, not duplicated

        let inserted = repo.block(source: "google", externalEventId: "g-2")
        XCTAssertEqual(inserted?.title, "Standup")
        XCTAssertEqual(inserted?.createdByBogi, false)
    }

    func testReconcileOrphansUserBlockButDeletesBogiMirror() throws {
        let db = try DatabaseService(inMemory: true)
        let repo = PlannedBlockRepository(database: db)
        let service = PlannerService(repository: repo)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        // A user-created google block + a bogi-created google mirror, both will vanish upstream.
        repo.upsert(makeBlock(id: "user", start: base, end: base.addingTimeInterval(3600),
                              source: "google", externalId: "u-1", createdByBogi: false))
        repo.upsert(makeBlock(id: "mirror", start: base, end: base.addingTimeInterval(3600),
                              source: "google", externalId: "m-1", createdByBogi: true))

        // Reconcile with an empty google batch → both lost their backing.
        service.reconcileExternal([
            ExternalCalendarEvent(source: "google", externalId: "keep", title: "Keep",
                                  start: base, end: base.addingTimeInterval(60))
        ])

        // User block survives but is marked orphaned; bogi mirror is removed.
        let user = repo.block(source: "google", externalEventId: "u-1")
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.status, "orphaned")
        XCTAssertNil(repo.block(source: "google", externalEventId: "m-1"))
    }

    func testCreateLocalBlock() throws {
        let db = try DatabaseService(inMemory: true)
        let repo = PlannedBlockRepository(database: db)
        let service = PlannerService(repository: repo)
        let start = Date()
        let block = service.createLocalBlock(title: "Deep Work", start: start,
                                             end: start.addingTimeInterval(3600), category: "focus")
        XCTAssertEqual(block.source, "local")
        XCTAssertTrue(block.createdByBogi)
        XCTAssertEqual(block.status, "planned")
        XCTAssertEqual(repo.count(), 1)
    }

    // MARK: - Two-way sync (push to Google)

    func testReconcileStoresCalendarId() throws {
        let db = try DatabaseService(inMemory: true)
        let repo = PlannedBlockRepository(database: db)
        let service = PlannerService(repository: repo)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        service.reconcileExternal([
            ExternalCalendarEvent(source: "google", externalId: "g-9", title: "Shared",
                                  start: base, end: base.addingTimeInterval(3600),
                                  calendarId: "work@example.com")
        ])

        let block = repo.block(source: "google", externalEventId: "g-9")
        XCTAssertEqual(block?.calendarId, "work@example.com")
    }

    func testCreateLocalBlockPushesToGoogleAndStampsIds() throws {
        let db = try DatabaseService(inMemory: true)
        let repo = PlannedBlockRepository(database: db)
        let service = PlannerService(repository: repo)
        let writer = StubCalendarWriter(calendarId: "primary", eventId: "g-created-1")
        service.calendarWriter = writer

        let start = Date()
        let block = service.createLocalBlock(title: "Deep Work", start: start,
                                             end: start.addingTimeInterval(3600), category: nil)
        // Returns immediately as a local block; the push happens asynchronously.
        XCTAssertEqual(block.source, "local")

        waitUntil(repo.block(id: block.id)?.source == "google")
        let stored = repo.block(id: block.id)
        XCTAssertEqual(stored?.externalEventId, "g-created-1")
        XCTAssertEqual(stored?.calendarId, "primary")
        XCTAssertTrue(stored?.createdByBogi ?? false)
        XCTAssertEqual(writer.created.count, 1)
    }

    func testMoveBlockUpdatesExistingGoogleEvent() throws {
        let db = try DatabaseService(inMemory: true)
        let repo = PlannedBlockRepository(database: db)
        let service = PlannerService(repository: repo)
        let writer = StubCalendarWriter()
        service.calendarWriter = writer
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        var seeded = makeBlock(id: "m", title: "Focus", start: base, end: base.addingTimeInterval(3600),
                               source: "google", externalId: "g-evt-1", createdByBogi: true)
        seeded.calendarId = "primary"
        repo.upsert(seeded)

        let moved = service.moveBlock(matching: "focus", start: base.addingTimeInterval(7200),
                                      end: base.addingTimeInterval(10_800))
        XCTAssertEqual(moved?.id, "m")
        waitUntil(writer.updated.count == 1)
        XCTAssertEqual(writer.updated.first?.externalEventId, "g-evt-1")
    }

    func testLocalBlockWithoutWriterStaysLocal() throws {
        let db = try DatabaseService(inMemory: true)
        let repo = PlannedBlockRepository(database: db)
        let service = PlannerService(repository: repo)   // no calendarWriter
        let start = Date()
        let block = service.createLocalBlock(title: "Solo", start: start,
                                             end: start.addingTimeInterval(600), category: nil)
        XCTAssertEqual(repo.block(id: block.id)?.source, "local")
    }

    // MARK: - PlannerCommandParser.decode

    func testDecodeExplicitISOIntoCreateBlock() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {
          "action": "create",
          "title": "Write report",
          "start": "2026-06-06T09:00:00Z",
          "end": "2026-06-06T10:30:00Z"
        }
        """
        let command = PlannerCommandParser.decode(json, now: now)
        guard case let .createBlock(title, start, end) = command else {
            return XCTFail("expected createBlock, got \(command)")
        }
        XCTAssertEqual(title, "Write report")
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(iso.string(from: start), "2026-06-06T09:00:00Z")
        XCTAssertEqual(end.timeIntervalSince(start), 90 * 60, accuracy: 1)
    }

    func testDecodeRelativeDayWithDuration() {
        // 2021-11-14T22:13:20Z roughly; we only assert structure + duration here.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {"action":"create","title":"Gym","relativeDay":"tomorrow","startTime":"07:00","durationMinutes":45}
        """
        let command = PlannerCommandParser.decode(json, now: now)
        guard case let .createBlock(title, start, end) = command else {
            return XCTFail("expected createBlock, got \(command)")
        }
        XCTAssertEqual(title, "Gym")
        XCTAssertEqual(end.timeIntervalSince(start), 45 * 60, accuracy: 1)
    }

    func testDecodeFencedJSON() {
        let now = Date()
        let json = """
        ```json
        {"action":"create","title":"X","start":"2026-01-01T08:00:00Z","durationMinutes":30}
        ```
        """
        let command = PlannerCommandParser.decode(json, now: now)
        guard case .createBlock = command else {
            return XCTFail("expected createBlock from fenced JSON, got \(command)")
        }
    }

    func testDecodeUnknownOnGarbage() {
        XCTAssertEqual(PlannerCommandParser.decode("not json", now: Date()), .unknown)
        XCTAssertEqual(PlannerCommandParser.decode("{\"action\":\"unknown\"}", now: Date()), .unknown)
    }

    // MARK: - Google PKCE

    func testMakePKCEProducesDistinctVerifierAndChallenge() {
        let pkce = GoogleCalendarService.makePKCE()
        XCTAssertEqual(pkce.verifier.count, 64)
        XCTAssertFalse(pkce.challenge.isEmpty)
        XCTAssertNotEqual(pkce.verifier, pkce.challenge)
        // base64url: no padding or url-unsafe chars.
        XCTAssertFalse(pkce.challenge.contains("="))
        XCTAssertFalse(pkce.challenge.contains("+"))
        XCTAssertFalse(pkce.challenge.contains("/"))
        // Two calls yield different verifiers (randomness).
        XCTAssertNotEqual(pkce.verifier, GoogleCalendarService.makePKCE().verifier)
    }
}
