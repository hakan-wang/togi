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

    init(store: EKEventStore = EKEventStore(), bogiCalendarTitle: String = "Togi") {
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

    /// Create a standalone event in the user's default (synced) calendar — used by voice
    /// scheduling for ordinary events like "call with a friend", which aren't focus blocks.
    /// Returns the new event's identifier (for later undo), or nil if it couldn't be saved.
    @discardableResult
    func createEvent(title: String, start: Date, end: Date, notes: String? = nil) -> String? {
        guard authorizationStatus() == .granted else { return nil }

        let event = EKEvent(eventStore: store)
        event.calendar = targetCalendar()
        event.title = title
        event.startDate = start
        event.endDate = end > start ? end : start.addingTimeInterval(30 * 60)
        if let notes { event.notes = notes }

        // Remind ahead of the event: 1 hour, 30 minutes, and 10 minutes before.
        for offset in [-3600.0, -1800.0, -600.0] {
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    /// Remove an event Bogi created, identified by the id returned from ``createEvent`` /
    /// ``upsertBogiBlock``. Returns true on success. No-op if permission is missing or the
    /// event no longer exists.
    @discardableResult
    func deleteEvent(identifier: String) -> Bool {
        guard authorizationStatus() == .granted,
              let event = store.event(withIdentifier: identifier) else { return false }
        do {
            try store.remove(event, span: .thisEvent, commit: true)
            return true
        } catch {
            return false
        }
    }

    /// The calendar Togi writes to. Prefers a Google calendar connected to macOS Calendar so
    /// voice-scheduled events sync straight to Google; otherwise the system default.
    private func targetCalendar() -> EKCalendar? {
        let writable = store.calendars(for: .event).filter { $0.allowsContentModifications }
        if let google = writable.first(where: { Self.isGoogle($0) }) { return google }
        return store.defaultCalendarForNewEvents ?? bogiCalendar() ?? writable.first
    }

    /// Whether a writable Google calendar is connected (used to tell the user it'll sync to Google).
    func hasGoogleCalendar() -> Bool {
        guard authorizationStatus() == .granted else { return false }
        return store.calendars(for: .event).contains { $0.allowsContentModifications && Self.isGoogle($0) }
    }

    /// Recognise a Google calendar among macOS Calendar sources (Google syncs via CalDAV, titled
    /// with the account's name or email).
    private static func isGoogle(_ calendar: EKCalendar) -> Bool {
        let title = (calendar.source?.title ?? "").lowercased()
        if title.contains("icloud") { return false }
        if title.contains("google") || title.contains("gmail") { return true }
        if calendar.source?.sourceType == .calDAV, title.contains("@") { return true }
        return false
    }

    private func bogiCalendar() -> EKCalendar? {
        if let match = store.calendars(for: .event).first(where: { $0.title == bogiCalendarTitle }) {
            return match
        }
        return store.defaultCalendarForNewEvents
    }
}
