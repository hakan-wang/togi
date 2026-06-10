import Foundation

/// A planned event sourced from an external calendar (Apple EventKit / Google Calendar API).
/// Carried into the planner layer so calendar plumbing stays decoupled from persistence.
struct ExternalCalendarEvent {
    let source: String          // apple | google
    let externalId: String
    let title: String
    let start: Date
    let end: Date
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
        return block
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
                    || existing.status == Self.statusOrphaned   // re-appeared upstream
                if changed {
                    existing.title = event.title
                    existing.startAt = event.start
                    existing.endAt = event.end
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
                    updatedAt: now
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
