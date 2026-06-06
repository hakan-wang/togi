import Foundation

/// A planned event sourced from an external calendar (Apple EventKit / Google Calendar API).
/// Carried into the planner layer so calendar plumbing stays decoupled from persistence.
struct ExternalCalendarEvent {
    let source: String          // apple | google
    let externalId: String
    let title: String
    let start: Date
    let end: Date
    /// The calendar the event lives in (Google calendarId, e.g. "primary"). nil for Apple events.
    var calendarId: String? = nil
}

/// Writes Bogi-created blocks out to an external calendar (Google). Implemented by an adapter over
/// `GoogleCalendarService`; injected so the planner stays decoupled from networking and is testable.
/// All methods no-op/return nil when the provider isn't connected, leaving the block local-only.
protocol PlannedBlockCalendarWriter {
    /// Create the matching event upstream. Returns the new (calendarId, externalEventId), or nil
    /// on failure / not-connected.
    func createEvent(for block: PlannedBlock) async -> (calendarId: String, externalEventId: String)?
    /// Push a changed block to its existing upstream event. Returns true on success.
    func updateEvent(for block: PlannedBlock) async -> Bool
}

/// Orchestrates planned blocks: local block creation and reconciliation of external calendars.
///
/// Reconciliation policy (local-first, never destructive to the user):
/// - External events are upserted keyed by (source, external_event_id).
/// - When an existing block's title/time changed upstream, it is updated.
/// - When a previously-synced external event disappears upstream, the block is NOT deleted if it
///   was user-created — it is marked `orphaned` so the user keeps their data. Bogi-created mirror
///   blocks (created_by_bogi == true) may be safely removed.
final class PlannerService {
    static let statusPlanned = "planned"
    static let statusOrphaned = "orphaned"

    private let repository: PlannedBlockRepository
    private let sidecar: SidecarClient?
    /// Optional sink that mirrors Bogi-created blocks into Google Calendar (two-way sync). When nil
    /// or not connected, blocks stay local-only.
    var calendarWriter: PlannedBlockCalendarWriter?

    init(repository: PlannedBlockRepository, sidecar: SidecarClient? = nil) {
        self.repository = repository
        self.sidecar = sidecar
    }

    /// Route a natural-language planning utterance to the on-device agent. The agent calls
    /// the `create_block` / `move_block` action tools itself, which round-trip back to the
    /// repository via the app's SidecarActionHandlers.
    func handle(utterance: String) async throws {
        guard let sidecar else { return }
        _ = try await sidecar.plan(utterance, threadId: "planner")
    }

    /// Move the soonest planned block whose title contains `match` (case-insensitive) to a new
    /// time window. Returns the moved block, or nil if no block matched. Used by the agent's
    /// `move_block` action tool.
    @discardableResult
    func moveBlock(matching match: String, start: Date, end: Date) -> PlannedBlock? {
        let needle = match.lowercased()
        let candidates = repository.all()
            .filter { $0.title.lowercased().contains(needle) }
            .sorted { $0.startAt < $1.startAt }
        guard var block = candidates.first else { return nil }
        block.startAt = start
        block.endAt = end
        block.updatedAt = Date()
        repository.upsert(block)
        pushUpdateIfNeeded(block)
        return block
    }

    /// Create a Bogi-owned local block (no external calendar backing).
    @discardableResult
    func createLocalBlock(title: String, start: Date, end: Date, category: String?) -> PlannedBlock {
        let block = PlannedBlock(
            id: UUID().uuidString,
            source: "local",
            externalEventId: nil,
            title: title,
            startAt: start,
            endAt: end,
            category: category,
            goalId: nil,
            status: Self.statusPlanned,
            createdByBogi: true,
            updatedAt: Date()
        )
        repository.upsert(block)
        pushCreateIfNeeded(block)
        return block
    }

    // MARK: - Two-way push (Bogi-created blocks → Google)

    /// Mirror a freshly Bogi-created block into Google, then record the returned ids locally so the
    /// next sync matches it (instead of duplicating) and future moves can update the right event.
    /// Fire-and-forget: failure (incl. not-connected) leaves the block local-only.
    private func pushCreateIfNeeded(_ block: PlannedBlock) {
        guard let writer = calendarWriter, block.createdByBogi, block.source == "local" else { return }
        Task { [repository] in
            guard let ids = await writer.createEvent(for: block) else { return }
            // A sync could have imported this Google event already (narrow race). If so, keep that
            // row (marking it Bogi-owned) and drop our local placeholder instead of duplicating.
            if let dup = repository.block(source: "google", externalEventId: ids.externalEventId),
               dup.id != block.id {
                var merged = dup
                merged.createdByBogi = true
                repository.upsert(merged)
                repository.delete(id: block.id)
                return
            }
            // Re-read in case the block changed meanwhile; only stamp the upstream ids.
            var stored = repository.block(id: block.id) ?? block
            stored.source = "google"
            stored.calendarId = ids.calendarId
            stored.externalEventId = ids.externalEventId
            stored.updatedAt = Date()
            repository.upsert(stored)
        }
    }

    /// Push a moved/edited block to its existing Google event, if it is a Bogi-created google block.
    private func pushUpdateIfNeeded(_ block: PlannedBlock) {
        guard let writer = calendarWriter, block.createdByBogi,
              block.source == "google", block.externalEventId != nil else { return }
        Task { _ = await writer.updateEvent(for: block) }
    }

    /// Reconcile a fresh batch of external events for one or more sources into planned_blocks.
    ///
    /// The `events` array is treated as the authoritative current set for whichever sources appear
    /// in it. Blocks of those sources that are absent from `events` are considered to have lost
    /// their external backing.
    func reconcileExternal(_ events: [ExternalCalendarEvent]) {
        let now = Date()

        // Upsert / update each incoming event, tracking which keys we saw per source.
        var seenKeys: [String: Set<String>] = [:]   // source -> set of externalIds
        for event in events {
            seenKeys[event.source, default: []].insert(event.externalId)

            if var existing = repository.block(source: event.source, externalEventId: event.externalId) {
                // Update title/time only if they actually changed; preserve user metadata.
                let changed = existing.title != event.title
                    || existing.startAt != event.start
                    || existing.endAt != event.end
                    || existing.calendarId != event.calendarId
                    || existing.status == Self.statusOrphaned   // re-appeared upstream
                if changed {
                    existing.title = event.title
                    existing.startAt = event.start
                    existing.endAt = event.end
                    existing.calendarId = event.calendarId ?? existing.calendarId
                    if existing.status == Self.statusOrphaned {
                        existing.status = Self.statusPlanned
                    }
                    existing.updatedAt = now
                    repository.upsert(existing)
                }
            } else {
                let block = PlannedBlock(
                    id: UUID().uuidString,
                    source: event.source,
                    externalEventId: event.externalId,
                    title: event.title,
                    startAt: event.start,
                    endAt: event.end,
                    category: nil,
                    goalId: nil,
                    status: Self.statusPlanned,
                    createdByBogi: false,
                    updatedAt: now,
                    calendarId: event.calendarId
                )
                repository.upsert(block)
            }
        }

        // Handle blocks whose external event disappeared, but only for sources present in this batch.
        for source in seenKeys.keys {
            let seen = seenKeys[source] ?? []
            for var block in repository.blocks(source: source) {
                guard let extId = block.externalEventId, !seen.contains(extId) else { continue }
                if block.createdByBogi {
                    // A Bogi-created mirror lost its backing → safe to remove.
                    repository.delete(id: block.id)
                } else if block.status != Self.statusOrphaned {
                    // User-created event vanished upstream → never delete, just mark it.
                    block.status = Self.statusOrphaned
                    block.updatedAt = now
                    repository.upsert(block)
                }
            }
        }
    }
}
