import Foundation

// Shared, framework-light types for the calendar integrations. `EventKitService`
// (Apple) and `GoogleCalendarService` (Google) both adopt `CalendarSource` and
// speak in these value types, so the planner and the reconciler never depend on
// EventKit / Google API objects directly and stay unit-testable.

/// A calendar event as seen by Bogi, normalized across providers. SQLite
/// (`planned_blocks`) is canonical; these are the external rows we reconcile in.
struct ExternalCalendarEvent: Equatable {
    var externalId: String
    var provider: CalendarProvider
    var title: String
    var startAt: Date
    var endAt: Date
    /// True when the event carries Bogi's tag in its notes (we created it).
    var isBogiCreated: Bool
    /// The `planned_blocks.id` parsed from the Bogi tag, when present.
    var bogiBlockId: String?
    /// Provider's last-modified timestamp, used to decide whose edit wins.
    var lastModified: Date?
    /// Identifier of the owning calendar (EventKit calendar id / Google calendar id).
    var calendarId: String?

    init(
        externalId: String,
        provider: CalendarProvider,
        title: String,
        startAt: Date,
        endAt: Date,
        isBogiCreated: Bool = false,
        bogiBlockId: String? = nil,
        lastModified: Date? = nil,
        calendarId: String? = nil
    ) {
        self.externalId = externalId
        self.provider = provider
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.isBogiCreated = isBogiCreated
        self.bogiBlockId = bogiBlockId
        self.lastModified = lastModified
        self.calendarId = calendarId
    }
}

/// The data needed to create or update a Bogi-owned event in an external
/// calendar. Mirrors the canonical `PlannedBlock`.
struct CalendarEventDraft: Equatable {
    var bogiBlockId: String
    var title: String
    var startAt: Date
    var endAt: Date
    var notes: String?
    var calendarId: String?

    init(
        bogiBlockId: String,
        title: String,
        startAt: Date,
        endAt: Date,
        notes: String? = nil,
        calendarId: String? = nil
    ) {
        self.bogiBlockId = bogiBlockId
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.notes = notes
        self.calendarId = calendarId
    }
}

enum CalendarSourceError: Error, Equatable {
    case accessDenied
    case notAuthenticated
    /// Refused because the target event was not created by Bogi — we never
    /// mutate or delete user-owned events.
    case notBogiOwned
    case eventNotFound
    case http(status: Int)
    case invalidResponse
}

/// Mockable contract over a calendar backend. Implementations MUST NOT delete or
/// destructively edit events that Bogi did not create (`isBogiCreated == false`).
protocol CalendarSource {
    var provider: CalendarProvider { get }

    /// Prompt for / verify access. Returns true when access is granted.
    func requestAccess() async throws -> Bool

    /// All events overlapping `[from, to)` across the user's calendars.
    func fetchEvents(from: Date, to: Date) async throws -> [ExternalCalendarEvent]

    /// Create a new Bogi-owned event; the returned event carries the provider's id.
    func createBogiEvent(_ draft: CalendarEventDraft) async throws -> ExternalCalendarEvent

    /// Update an existing Bogi-owned event. Throws `.notBogiOwned` if the target
    /// is a user event.
    func updateBogiEvent(externalId: String, with draft: CalendarEventDraft) async throws -> ExternalCalendarEvent

    /// Remove a Bogi-owned event. Throws `.notBogiOwned` for user events so the
    /// "never delete user events" guardrail is enforced at the source boundary.
    func removeBogiEvent(externalId: String) async throws
}

/// Pure helpers for embedding/reading Bogi's ownership tag in an event's notes.
/// Bogi marks events it creates with `[bogi:<blockId>]` so external edits can be
/// distinguished from user-authored events without a separate store.
enum CalendarEventTag {
    static let open = "[bogi:"
    static let close = "]"

    /// The marker string for a given block, e.g. `[bogi:1234]`.
    static func marker(for blockId: String) -> String {
        "\(open)\(blockId)\(close)"
    }

    /// Whether the given notes contain a Bogi ownership marker.
    static func isBogiCreated(notes: String?) -> Bool {
        blockId(fromNotes: notes) != nil
    }

    /// Extract the block id from a Bogi marker in `notes`, if present.
    static func blockId(fromNotes notes: String?) -> String? {
        guard let notes, let openRange = notes.range(of: open) else { return nil }
        let afterOpen = notes[openRange.upperBound...]
        guard let closeRange = afterOpen.range(of: close) else { return nil }
        let id = afterOpen[afterOpen.startIndex..<closeRange.lowerBound]
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Return `notes` with the Bogi marker for `blockId` present exactly once.
    /// Any pre-existing Bogi marker is replaced so the tag never duplicates.
    static func annotate(notes: String?, blockId: String) -> String {
        let marker = marker(for: blockId)
        let base = strip(notes: notes)
        if base.isEmpty { return marker }
        return base + "\n\n" + marker
    }

    /// Remove any Bogi marker from `notes`, returning the user-visible remainder.
    static func strip(notes: String?) -> String {
        guard let notes else { return "" }
        guard let openRange = notes.range(of: open),
              let closeRange = notes[openRange.upperBound...].range(of: close)
        else {
            return notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var copy = notes
        copy.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
        return copy.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
