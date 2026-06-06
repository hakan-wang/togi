import Foundation
import EventKit

/// Apple Calendar integration via EventKit. Reads events, creates/updates the
/// blocks Bogi owns, and detects external edits. It NEVER deletes or mutates a
/// user-authored event: every write path checks the Bogi ownership tag first.
///
/// Calendar data stays on the Mac — EventKit talks to the local Calendar store;
/// nothing here touches the backend.
final class EventKitService: CalendarSource {
    let provider: CalendarProvider = .apple

    private let store: EKEventStore
    /// Calendar Bogi writes its own blocks into; defaults to the user's default
    /// calendar for new events. Resolved lazily so init never blocks on access.
    private let preferredCalendarId: String?

    init(store: EKEventStore = EKEventStore(), preferredCalendarId: String? = nil) {
        self.store = store
        self.preferredCalendarId = preferredCalendarId
    }

    func requestAccess() async throws -> Bool {
        // macOS 14 split calendar access into full / write-only. Bogi needs full
        // access to read existing events for the plan-vs-reality comparison.
        if #available(macOS 14.0, *) {
            return try await store.requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { cont in
                store.requestAccess(to: .event) { granted, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: granted) }
                }
            }
        }
    }

    func fetchEvents(from: Date, to: Date) async throws -> [ExternalCalendarEvent] {
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        let events = store.events(matching: predicate)
        return events.map { Self.makeExternalEvent(from: $0) }
    }

    func createBogiEvent(_ draft: CalendarEventDraft) async throws -> ExternalCalendarEvent {
        let event = EKEvent(eventStore: store)
        apply(draft, to: event)
        event.calendar = resolveWritableCalendar()
        try store.save(event, span: .thisEvent, commit: true)
        return Self.makeExternalEvent(from: event)
    }

    func updateBogiEvent(externalId: String, with draft: CalendarEventDraft) async throws -> ExternalCalendarEvent {
        guard let event = store.event(withIdentifier: externalId) else {
            throw CalendarSourceError.eventNotFound
        }
        // Guardrail: only events Bogi tagged may be mutated here.
        guard CalendarEventTag.isBogiCreated(notes: event.notes) else {
            throw CalendarSourceError.notBogiOwned
        }
        apply(draft, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        return Self.makeExternalEvent(from: event)
    }

    func removeBogiEvent(externalId: String) async throws {
        guard let event = store.event(withIdentifier: externalId) else {
            throw CalendarSourceError.eventNotFound
        }
        // Hard guardrail per spec: never delete a user-created event.
        guard CalendarEventTag.isBogiCreated(notes: event.notes) else {
            throw CalendarSourceError.notBogiOwned
        }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    // MARK: - Mapping

    private func apply(_ draft: CalendarEventDraft, to event: EKEvent) {
        event.title = draft.title
        event.startDate = draft.startAt
        event.endDate = draft.endAt
        // Always (re)write the ownership tag so the event stays detectable as Bogi's.
        event.notes = CalendarEventTag.annotate(notes: draft.notes ?? event.notes, blockId: draft.bogiBlockId)
    }

    private func resolveWritableCalendar() -> EKCalendar? {
        if let preferredCalendarId,
           let match = store.calendar(withIdentifier: preferredCalendarId),
           match.allowsContentModifications {
            return match
        }
        return store.defaultCalendarForNewEvents
    }

    static func makeExternalEvent(from event: EKEvent) -> ExternalCalendarEvent {
        ExternalCalendarEvent(
            externalId: event.eventIdentifier ?? UUID().uuidString,
            provider: .apple,
            title: event.title ?? "",
            startAt: event.startDate,
            endAt: event.endDate,
            isBogiCreated: CalendarEventTag.isBogiCreated(notes: event.notes),
            bogiBlockId: CalendarEventTag.blockId(fromNotes: event.notes),
            lastModified: event.lastModifiedDate,
            calendarId: event.calendar?.calendarIdentifier
        )
    }
}
