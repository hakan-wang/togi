import Foundation

// Pure reconciliation between external calendar events and the canonical
// `planned_blocks` table. No I/O — `PlannerService` applies the resulting
// actions. SQLite is canonical; this decides how external state folds in.
//
// Guardrails encoded here:
//   * Bogi NEVER deletes a user-authored external event — reconciliation only
//     ever produces inserts/updates of local blocks, never an external delete.
//   * An external edit to a Bogi-owned event updates the local block (the user
//     dragged the block in Calendar.app — that wins for time/title).

/// A change reconciliation wants applied to the canonical store.
enum ReconcileAction: Equatable {
    /// A new block mirroring an external event Bogi hadn't seen before.
    case insert(PlannedBlock)
    /// An existing block whose external counterpart was edited externally.
    case update(PlannedBlock)
}

enum CalendarReconciler {
    /// Map external events into insert/update actions against existing blocks.
    ///
    /// - Parameters:
    ///   - external: events read from a `CalendarSource`.
    ///   - existing: the current `planned_blocks` rows (canonical).
    ///   - now: clock for `updatedAt` when the event has no `lastModified`.
    static func reconcile(
        external: [ExternalCalendarEvent],
        existing: [PlannedBlock],
        now: Date = Date()
    ) -> [ReconcileAction] {
        // Index existing blocks by their external id for O(1) matching.
        var byExternalId: [String: PlannedBlock] = [:]
        for block in existing {
            if let extId = block.externalEventId {
                byExternalId[extId] = block
            }
        }

        var actions: [ReconcileAction] = []
        for event in external {
            if let current = byExternalId[event.externalId] {
                if let updated = updatedBlock(from: current, event: event, now: now) {
                    actions.append(.update(updated))
                }
            } else {
                actions.append(.insert(makeBlock(from: event, now: now)))
            }
        }
        // Note: blocks present locally but absent externally are intentionally
        // left untouched — we do not delete, to honor "never delete user events"
        // and because a narrow time window may simply not include them.
        return actions
    }

    /// Deterministic id for a freshly-imported external event. Reuses Bogi's own
    /// block id when the event is one we created (round-trips cleanly).
    static func blockId(for event: ExternalCalendarEvent) -> String {
        if let bogiBlockId = event.bogiBlockId { return bogiBlockId }
        return "ext:\(event.provider.rawValue):\(event.externalId)"
    }

    static func makeBlock(from event: ExternalCalendarEvent, now: Date) -> PlannedBlock {
        PlannedBlock(
            id: blockId(for: event),
            source: source(for: event.provider),
            externalEventId: event.externalId,
            title: event.title,
            startAt: event.startAt,
            endAt: event.endAt,
            category: nil,
            goalId: nil,
            status: .planned,
            createdByBogi: event.isBogiCreated,
            updatedAt: event.lastModified ?? now
        )
    }

    /// Returns an updated copy of `block` if the external event diverges from it,
    /// otherwise nil (no-op). Title/time follow the external edit; local-only
    /// fields (category, goal, status) are preserved.
    static func updatedBlock(from block: PlannedBlock, event: ExternalCalendarEvent, now: Date) -> PlannedBlock? {
        let changed = block.title != event.title
            || block.startAt != event.startAt
            || block.endAt != event.endAt
        guard changed else { return nil }
        var copy = block
        copy.title = event.title
        copy.startAt = event.startAt
        copy.endAt = event.endAt
        copy.updatedAt = event.lastModified ?? now
        return copy
    }

    static func source(for provider: CalendarProvider) -> BlockSource {
        switch provider {
        case .apple: return .apple
        case .google: return .google
        }
    }
}
