import Foundation
import EventKit

/// Wraps EventKit for the Apple Calendar intent source. Defensive throughout: if permission is
/// not granted the read methods return empty and the write methods no-op, so nothing crashes and
/// no user event is ever silently destroyed.
final class EventKitService {
    /// Coarse permission state independent of the EventKit enum churn across OS versions.
    enum Authorization {
        case notDetermined
        case denied
        case granted
    }

    private let store: EKEventStore
    /// Calendar Bogi writes its own blocks into. nil → use the store's default calendar.
    private let bogiCalendarTitle: String

    init(store: EKEventStore = EKEventStore(), bogiCalendarTitle: String = "Bogi") {
        self.store = store
        self.bogiCalendarTitle = bogiCalendarTitle
    }

    // MARK: - Authorization

    func authorizationStatus() -> Authorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted, .denied:
            return .denied
        case .authorized:
            return .granted
        default:
            // macOS 14 adds `.fullAccess` / `.writeOnly`; treat any non-denied newer case as granted.
            if #available(macOS 14.0, *) {
                let status = EKEventStore.authorizationStatus(for: .event)
                if status == .fullAccess || status == .writeOnly { return .granted }
            }
            return .denied
        }
    }

    /// Request access. Uses the macOS 14 full-access API when available, falling back otherwise.
    func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Read

    /// Fetch events in [start, end), mapped into the planner's source-agnostic shape.
    func fetchEvents(start: Date, end: Date) -> [ExternalCalendarEvent] {
        guard authorizationStatus() == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return events.compactMap { event -> ExternalCalendarEvent? in
            guard let externalId = event.eventIdentifier,
                  let startDate = event.startDate,
                  let endDate = event.endDate else { return nil }
            return ExternalCalendarEvent(
                source: "apple",
                externalId: externalId,
                title: event.title ?? "(untitled)",
                start: startDate,
                end: endDate
            )
        }
    }

    // MARK: - Write (Bogi-created blocks only)

    /// Mirror a Bogi-created planned block into Apple Calendar. Creates a new EKEvent or updates the
    /// existing one identified by `block.externalEventId`. Refuses to touch user-created events.
    @discardableResult
    func upsertBogiBlock(_ block: PlannedBlock) -> String? {
        guard block.createdByBogi, authorizationStatus() == .granted else { return nil }

        let event: EKEvent
        if let externalId = block.externalEventId,
           let existing = store.event(withIdentifier: externalId) {
            event = existing
        } else {
            event = EKEvent(eventStore: store)
            event.calendar = bogiCalendar()
        }

        event.title = block.title
        event.startDate = block.startAt
        event.endDate = block.endAt

        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    private func bogiCalendar() -> EKCalendar? {
        if let match = store.calendars(for: .event).first(where: { $0.title == bogiCalendarTitle }) {
            return match
        }
        return store.defaultCalendarForNewEvents
    }
}
