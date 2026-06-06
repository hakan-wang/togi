import Foundation
import GRDB

/// Owns the canonical `planned_blocks` table and bridges it to external
/// calendars. SQLite is the source of truth: external events are reconciled in,
/// and Bogi-owned blocks are pushed out. CRUD here is synchronous DB work
/// (testable against an in-memory `DatabaseService`); calendar sync is async.
@MainActor
final class PlannerService: ObservableObject {
    private let database: DatabaseService
    /// Registered calendar backends keyed by provider (Apple/Google).
    private var sources: [CalendarProvider: CalendarSource]
    private let now: () -> Date
    private let idGenerator: () -> String

    init(
        database: DatabaseService,
        sources: [CalendarSource] = [],
        now: @escaping () -> Date = Date.init,
        idGenerator: @escaping () -> String = { UUID().uuidString }
    ) {
        self.database = database
        self.now = now
        self.idGenerator = idGenerator
        self.sources = [:]
        for source in sources { self.sources[source.provider] = source }
    }

    func register(_ source: CalendarSource) {
        sources[source.provider] = source
    }

    // MARK: - CRUD (canonical, synchronous)

    @discardableResult
    func createBlock(
        title: String,
        startAt: Date,
        endAt: Date,
        category: String? = nil,
        goalId: String? = nil,
        source: BlockSource = .local,
        externalEventId: String? = nil,
        createdByBogi: Bool = true,
        status: BlockStatus = .planned
    ) throws -> PlannedBlock {
        var block = PlannedBlock(
            id: idGenerator(),
            source: source,
            externalEventId: externalEventId,
            title: title,
            startAt: startAt,
            endAt: endAt,
            category: category,
            goalId: goalId,
            status: status,
            createdByBogi: createdByBogi,
            updatedAt: now()
        )
        try database.dbQueue.write { db in try block.insert(db) }
        return block
    }

    func update(_ block: PlannedBlock) throws {
        var copy = block
        copy.updatedAt = now()
        try database.dbQueue.write { db in try copy.update(db) }
    }

    /// Persist a block whether or not it already exists (insert-or-update).
    func upsert(_ block: PlannedBlock) throws {
        var copy = block
        try database.dbQueue.write { db in try copy.save(db) }
    }

    func block(id: String) throws -> PlannedBlock? {
        try database.dbQueue.read { db in try PlannedBlock.fetchOne(db, key: id) }
    }

    func allBlocks() throws -> [PlannedBlock] {
        try database.dbQueue.read { db in
            try PlannedBlock.order(Column("start_at")).fetchAll(db)
        }
    }

    /// Blocks whose start falls within the given day (local calendar).
    func blocks(on day: Date, calendar: Calendar = .current) throws -> [PlannedBlock] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try blocks(from: start, to: end)
    }

    func blocks(from: Date, to: Date) throws -> [PlannedBlock] {
        try database.dbQueue.read { db in
            try PlannedBlock
                .filter(Column("start_at") >= from && Column("start_at") < to)
                .order(Column("start_at"))
                .fetchAll(db)
        }
    }

    /// Delete a block locally. If it is a Bogi-owned external event, also remove
    /// it from the calendar — but a user-authored event (`createdByBogi == false`)
    /// is only unlinked locally; the external event is left intact.
    func deleteBlock(id: String) async throws {
        guard let block = try block(id: id) else { return }
        _ = try database.dbQueue.write { db in try PlannedBlock.deleteOne(db, key: id) }

        guard block.createdByBogi,
              let externalId = block.externalEventId,
              let source = sources[provider(for: block.source)] else { return }
        // removeBogiEvent re-checks ownership at the source and throws for user
        // events, so this can never delete something the user created.
        try await source.removeBogiEvent(externalId: externalId)
    }

    // MARK: - Calendar sync (external → canonical)

    /// Pull events from a provider over a window and fold them into the canonical
    /// store via the pure `CalendarReconciler`.
    @discardableResult
    func sync(provider: CalendarProvider, from: Date, to: Date) async throws -> [ReconcileAction] {
        guard let source = sources[provider] else { return [] }
        let external = try await source.fetchEvents(from: from, to: to)
        let existing = try blocks(from: from, to: to)
        let actions = CalendarReconciler.reconcile(external: external, existing: existing, now: now())
        try apply(actions)
        return actions
    }

    /// Apply reconciliation actions to the canonical store.
    func apply(_ actions: [ReconcileAction]) throws {
        try database.dbQueue.write { db in
            for action in actions {
                switch action {
                case .insert(let b), .update(let b):
                    var block = b
                    try block.save(db)
                }
            }
        }
    }

    // MARK: - Canonical → external (push Bogi blocks out)

    /// Push a local block to a calendar as a Bogi-owned event, then store the
    /// returned external id so future syncs reconcile rather than duplicate.
    @discardableResult
    func pushToCalendar(blockId: String, provider: CalendarProvider) async throws -> PlannedBlock {
        guard let source = sources[provider] else { throw CalendarSourceError.notAuthenticated }
        guard let block = try block(id: blockId) else { throw CalendarSourceError.eventNotFound }

        let draft = CalendarEventDraft(
            bogiBlockId: block.id,
            title: block.title,
            startAt: block.startAt,
            endAt: block.endAt
        )

        let event: ExternalCalendarEvent
        if let externalId = block.externalEventId {
            event = try await source.updateBogiEvent(externalId: externalId, with: draft)
        } else {
            event = try await source.createBogiEvent(draft)
        }

        var updated = block
        updated.source = CalendarReconciler.source(for: provider)
        updated.externalEventId = event.externalId
        updated.createdByBogi = true
        updated.updatedAt = now()
        try update(updated)
        return updated
    }

    // MARK: - Helpers

    private func provider(for source: BlockSource) -> CalendarProvider {
        switch source {
        case .apple: return .apple
        case .google: return .google
        case .local: return .apple // local blocks have no external provider; default
        }
    }
}
